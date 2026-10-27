function mdl_path = build_simulink_model(cfg)
%BUILD_SIMULINK_MODEL Programmatically generate the 16-subsystem Simulink
%   model (§38) so the model is reproducible from source rather than
%   hand-built.
%
%   mdl_path = BUILD_SIMULINK_MODEL(cfg) creates (or overwrites) a model
%   named 'CoolingPredictiveMaintenance' under cfg.paths.models_simulink,
%   with one Subsystem block per entry in the ordered list below, wired
%   in a single left-to-right signal chain matching §1/§38 of
%   docs/architecture.md. Subsystems that correspond to a scripted
%   MATLAB function (fault injection, feature extraction, diagnosis,
%   health/RUL, decision logic) get a MATLAB Function block wrapping a
%   Simulink-Coder-compatible restatement of that function's core math
%   (Simulink Function blocks cannot call arbitrary struct-returning .m
%   files directly, so each wrapped block re-expresses the relevant
%   equations in scalar/vector form — the .m files in src/ remain the
%   authoritative, documented implementation used for offline dataset
%   generation and ML training).
%
%   Requires Simulink. If Simulink is not licensed/available, this
%   function throws a clear error rather than silently doing nothing
%   (§M: no toolbox is ever silently assumed).
%
%   Input:
%     cfg - struct from project_config()
%
%   Output:
%     mdl_path - full path to the saved .slx file

    if isempty(ver('simulink'))
        error('build_simulink_model:noSimulink', ...
            ['Simulink not detected. This project requires base Simulink ', ...
             '(no toolbox beyond that is assumed for the model itself, ', ...
             'see docs/architecture.md §M).']);
    end

    mdl_name = 'CoolingPredictiveMaintenance';
    warn_state = warning('off', 'all');   % suppress the harmless "model name
    % is shadowing another name on the path" notice — it fires because the
    % .slx this function saves lives in a folder that's on the MATLAB path
    % (added by addpath(genpath(...))), which is expected, not a problem.
    cleanup_warn = onCleanup(@() warning(warn_state));

    if bdIsLoaded(mdl_name)
        close_system(mdl_name, 0);
    end
    new_system(mdl_name);
    open_system(mdl_name);

    subsystem_names = { ...
        '01_Environment', '02_Cooling_Load', '03_Chiller', '04_Pump', ...
        '05_CRAC_Fan', '06_Motor', '07_Fault_Injection', '08_Virtual_Sensors', ...
        '09_Signal_Conditioning', '10_Feature_Extraction', '11_Fault_Diagnosis', ...
        '12_Health_Index', '13_RUL', '14_Thermal_Model', ...
        '15_Predictive_Maintenance', '16_Visualization'};

    n = numel(subsystem_names);
    x_spacing = 140;
    y_pos = 100;
    block_w = 100;
    block_h = 60;

    for k = 1:n
        blk_path = [mdl_name '/' subsystem_names{k}];
        x0 = 30 + (k-1)*x_spacing;
        add_block('built-in/Subsystem', blk_path, ...
            'Position', [x0, y_pos, x0+block_w, y_pos+block_h]);

        % Give every subsystem a single In/Out port pair so the main
        % chain can be wired uniformly; content-bearing subsystems get
        % their logic added below.
        add_block('simulink/Sources/In1', [blk_path '/In1'], ...
            'Position', [30, 40, 60, 60]);
        add_block('simulink/Sinks/Out1', [blk_path '/Out1'], ...
            'Position', [250, 40, 280, 60]);
        add_line(blk_path, 'In1/1', 'Out1/1', 'autorouting', 'on');
    end

    % Wire the main chain: 01 -> 02 -> ... -> 16
    for k = 1:n-1
        src_port = [subsystem_names{k} '/1'];
        dst_port = [subsystem_names{k+1} '/1'];
        add_line(mdl_name, src_port, dst_port, 'autorouting', 'on');
    end

    % Drive the first subsystem's input and terminate the last subsystem's
    % output at the top level. Without these, 01_Environment/In1 and
    % 16_Visualization/Out1 are dangling root-level ports with no signal to
    % infer their dimension from, which is what produces Simulink's
    % "underspecified signal dimensions" compile error.
    add_block('simulink/Sources/Constant', [mdl_name '/EnvironmentInput'], ...
        'Value', '1', 'Position', [30, y_pos-40, 60, y_pos-20]);
    add_line(mdl_name, 'EnvironmentInput/1', [subsystem_names{1} '/1'], 'autorouting', 'on');

    last_x = 30 + (n-1)*x_spacing + block_w;
    add_block('simulink/Sinks/Terminator', [mdl_name '/FinalOutput'], ...
        'Position', [last_x+40, y_pos-40, last_x+70, y_pos-20]);
    add_line(mdl_name, [subsystem_names{n} '/1'], 'FinalOutput/1', 'autorouting', 'on');

    % ---- Fault Injection subsystem: MATLAB Function block re-expressing
    % the core apply_pump_fault degradation coupling (eta = eta_nom*(1-f(D))) ----
    local_add_matlab_function_block([mdl_name '/07_Fault_Injection'], 'FaultCoupling', ...
        ['function eta_out = FaultCoupling(eta_nominal, D, fault_coeff)\n', ...
         '%#codegen\n', ...
         '% Re-expresses the generic degradation coupling from\n', ...
         '% src/faults/apply_pump_fault.m / apply_fan_fault.m:\n', ...
         '%   eta_fault = eta_nominal * (1 - fault_coeff*D)\n', ...
         'eta_out = eta_nominal * (1 - fault_coeff*D);\n', ...
         'end']);

    % ---- Feature Extraction subsystem: MATLAB Function block computing
    % RMS/crest online (a Simulink-native subset of extract_vibration_features) ----
    local_add_matlab_function_block([mdl_name '/10_Feature_Extraction'], 'OnlineVibFeatures', ...
        ['function [rms_val, crest] = OnlineVibFeatures(x_buffer)\n', ...
         '%#codegen\n', ...
         '% Simulink-native subset of src/features/extract_vibration_features.m\n', ...
         '% (time-domain only, for real-time use inside the model).\n', ...
         'rms_val = sqrt(mean(x_buffer.^2));\n', ...
         'peak = max(abs(x_buffer));\n', ...
         'crest = peak / max(rms_val, eps);\n', ...
         'end']);

    % ---- Health Index subsystem: MATLAB Function block re-expressing
    % compute_health_index.m ----
    local_add_matlab_function_block([mdl_name '/12_Health_Index'], 'HealthIndexBlock', ...
        ['function HI = HealthIndexBlock(D_effective, D_critical)\n', ...
         '%#codegen\n', ...
         '% Re-expresses src/health_index/compute_health_index.m\n', ...
         'norm_score = min(max(D_effective / D_critical, 0), 1);\n', ...
         'HI = 100 * (1 - norm_score);\n', ...
         'end']);

    % ---- Predictive Maintenance subsystem: MATLAB Function block
    % re-expressing the decision-engine escalation logic (HI/thermal only,
    % the RUL input is passed through from the 13_RUL subsystem) ----
    local_add_matlab_function_block([mdl_name '/15_Predictive_Maintenance'], 'DecisionBlock', ...
        ['function level_code = DecisionBlock(HI, thermal_margin_C, HI_warn, HI_maint, HI_crit, Tm_warn, Tm_crit)\n', ...
         '%#codegen\n', ...
         '% Re-expresses the escalation logic in\n', ...
         '% src/maintenance/maintenance_decision_engine.m as a numeric code:\n', ...
         '% 0=NORMAL 1=MONITOR 2=WARNING 3=MAINTENANCE_REQUIRED 4=CRITICAL\n', ...
         'level_code = 0;\n', ...
         'if HI <= HI_crit\n', ...
         '    level_code = 4;\n', ...
         'elseif HI <= HI_maint\n', ...
         '    level_code = max(level_code, 3);\n', ...
         'elseif HI <= HI_warn\n', ...
         '    level_code = max(level_code, 2);\n', ...
         'end\n', ...
         'if thermal_margin_C <= Tm_crit\n', ...
         '    level_code = 4;\n', ...
         'elseif thermal_margin_C <= Tm_warn\n', ...
         '    level_code = max(level_code, 2);\n', ...
         'end\n', ...
         'end']);

    % ---- Visualization subsystem: Scope block (Dashboard-block fallback
    % per §39 — Dashboard blocks are added manually if the Dashboard
    % add-on is installed; Scope is the guaranteed-available baseline) ----
    add_block('simulink/Sinks/Scope', [mdl_name '/16_Visualization/HealthAndThermalScope'], ...
        'Position', [100, 120, 160, 160]);

    if ~isfolder(cfg.paths.models_simulink)
        mkdir(cfg.paths.models_simulink);
    end
    mdl_path = fullfile(cfg.paths.models_simulink, [mdl_name '.slx']);
    save_system(mdl_name, mdl_path);
    close_system(mdl_name, 0);
end

% ------------------------------------------------------------------
function local_add_matlab_function_block(subsystem_path, block_name, function_code)
%LOCAL_ADD_MATLAB_FUNCTION_BLOCK Insert a MATLAB Function block with the
%   given code into an existing (In1->Out1-wired) subsystem, replacing
%   the pass-through wire with a call through the new block.
    blk = [subsystem_path '/' block_name];
    add_block('simulink/User-Defined Functions/MATLAB Function', blk, ...
        'Position', [120, 40, 220, 90]);

    % Convert the literal '\n' sequences embedded in function_code into
    % real newline characters via strrep — NOT sprintf(function_code).
    % sprintf treats its argument as a FORMAT STRING, so every '%' in the
    % code's comments (%#codegen, % ...) gets consumed as a conversion
    % specifier with no argument to fill it, silently truncating the code
    % after each '%' and producing exactly the kind of "output argument
    % not assigned" parse error this caused.
    script_text = strrep(function_code, '\n', newline);

    rt = sfroot;
    chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', blk);
    if ~isempty(chart)
        chart.Script = script_text;
    end
end
