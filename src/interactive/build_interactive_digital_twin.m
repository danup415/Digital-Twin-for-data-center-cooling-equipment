function mdl_path = build_interactive_digital_twin()
%BUILD_INTERACTIVE_DIGITAL_TWIN Build the visual, animated Simulink digital twin.
%
%   mdl_path = BUILD_INTERACTIVE_DIGITAL_TWIN() creates (or, if one
%   already exists, first backs up with a timestamp, then recreates)
%   models/Simulink/InteractiveCoolingDigitalTwin.slx — a SEPARATE model
%   from the original CoolingPredictiveMaintenance.slx, which this
%   function never opens, modifies, or even loads.
%
%   ARCHITECTURE (full detail in docs/INTERACTIVE_SIMULINK_DIGITAL_TWIN.md
%   — read that before presenting this):
%     - Two MATLAB System blocks (interpreted, NOT the code-generation
%       -restricted MATLAB Function block type) do all the real work:
%         MechanicalAnimation.m         - fast rate (0.05 s), pure
%                                          visualization, no physics
%         DigitalTwinCoreAndDashboard.m - slow rate (2 s = 1 simulated
%                                          hour), literally CALLS
%                                          run_single_operating_point.m
%                                          (and through it, every real
%                                          project function) — nothing is
%                                          re-implemented or duplicated
%     - Every OTHER subsystem named in the brief's requested hierarchy
%       (§9) exists in this model as a labeled, single-input,
%       pass-through-to-Terminator container fed by a direct BRANCH of
%       the one relevant control signal (not threaded through a shared
%       bus/chain). This is a deliberate simplification: a Mux/Demux bus
%       run through 12 subsystems in series is a lot of unverifiable
%       wiring for a build I cannot execute-test, where a single mistake
%       would break the whole chain. Independent parallel taps mean one
%       mistake stays local. It is stated here, not silently glossed
%       over, that these subsystems are organizational/labeling only —
%       the real computation is necessarily centralized in the two
%       blocks above, since splitting it apart would mean modifying or
%       duplicating run_single_operating_point.m.
%     - Controls are plain Constant blocks referencing BASE WORKSPACE
%       variables (ICDT_Equipment, ICDT_Fault, ICDT_SeverityPct,
%       ICDT_RPM, ICDT_LoadFracPct, ICDT_Ambient, ICDT_ITLoad) rather than
%       Simulink Dashboard Knob/Dropdown blocks — this build script could
%       not verify the exact Dashboard-block parameter API without a
%       testable environment, so it uses the guaranteed-correct
%       Constant-block + tunable-workspace-variable mechanism instead
%       (the same mechanism run_interactive_demo.m and the three demo
%       scripts use to drive a live parameter sweep). A user with
%       Simulink Dashboard installed can swap in Knob/Dropdown blocks
%       bound to these same variable names in a few minutes.
%
%   Output:
%     mdl_path - full path to the saved .slx

    fprintf('=== build_interactive_digital_twin: Phase 1 - load config ===\n');
    cfg = project_config();
    P = model_parameters();

    fprintf('=== Phase 2 - verify required functions exist ===\n');
    required_functions = { ...
        'run_single_operating_point', 'load_or_train_model', 'interactive_code_tables', ...
        'MechanicalAnimation', 'DigitalTwinCoreAndDashboard', ...
        'pump_model', 'fan_model', 'motor_model', 'apply_pump_fault', 'apply_fan_fault', ...
        'compute_health_index', 'estimate_rul', 'cooling_effectiveness_from_degradation', ...
        'thermal_digital_twin', 'maintenance_decision_engine', 'get_maintenance_thresholds'};
    missing = {};
    for k = 1:numel(required_functions)
        if exist(required_functions{k}, 'file') ~= 2 && exist(required_functions{k}, 'class') ~= 8
            missing{end+1} = required_functions{k}; %#ok<AGROW>
        end
    end
    if ~isempty(missing)
        error('build_interactive_digital_twin:missingFunctions', ...
            'Required function(s) not found on the path: %s', strjoin(missing, ', '));
    end

    fprintf('=== Phase 3 - verify required toolboxes ===\n');
    if isempty(ver('simulink'))
        error('build_interactive_digital_twin:noSimulink', ...
            'Simulink not detected. Base Simulink is required for this model.');
    end
    has_dashboard = ~isempty(ver('sldashboard'));
    fprintf('  Simulink Dashboard detected: %d (informational only, see docstring)\n', has_dashboard);

    mdl_name = 'InteractiveCoolingDigitalTwin';
    models_dir = cfg.paths.models_simulink;
    mdl_path = fullfile(models_dir, [mdl_name '.slx']);

    fprintf('=== Phase 4 - create model (backing up any existing file) ===\n');
    if isfile(mdl_path)
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        backup_path = fullfile(models_dir, sprintf('%s_%s.slx', mdl_name, ts));
        copyfile(mdl_path, backup_path);
        fprintf('  Existing %s backed up to %s\n', mdl_name, backup_path);
    end

    warn_state = warning('off', 'all');
    cleanup_warn = onCleanup(@() warning(warn_state)); %#ok<NASGU>

    if bdIsLoaded(mdl_name)
        close_system(mdl_name, 0);
    end
    new_system(mdl_name);
    open_system(mdl_name);
    set_param(mdl_name, 'InlineParams', 'off');   % required for live-tunable Constant blocks

    % ---- Base-workspace tunable control variables, matching the
    % "Expected Final User Experience": healthy Fan baseline ----
    assignin('base', 'ICDT_Equipment', 2);          % 1=Pump, 2=Fan (interactive_code_tables.m)
    assignin('base', 'ICDT_Fault', 1);               % 1=Healthy
    assignin('base', 'ICDT_SeverityPct', 0);
    assignin('base', 'ICDT_RPM', P.Fan.N_nominal_rpm);
    assignin('base', 'ICDT_LoadFracPct', 80);
    assignin('base', 'ICDT_Ambient', P.Thermal.ambient_C_nominal);
    assignin('base', 'ICDT_ITLoad', P.Thermal.IT_load_kW_nominal);

    fprintf('=== Phase 5/6/7/8 - build subsystems, controls, visualization, scopes ===\n');

    % ---- Controls: 7 Constant blocks (2 of them scaled from % to fraction) ----
    ctrl_specs = { ...
        'Equipment_cmd', 'ICDT_Equipment', [40, 40, 160, 60]; ...
        'Fault_cmd',     'ICDT_Fault',     [40, 90, 160, 110]; ...
        'RPM_cmd',       'ICDT_RPM',       [40, 140, 160, 160]; ...
        'Ambient_cmd',   'ICDT_Ambient',   [40, 190, 160, 210]; ...
        'ITLoad_cmd',    'ICDT_ITLoad',    [40, 240, 160, 260]};
    for k = 1:size(ctrl_specs, 1)
        local_add_constant(mdl_name, ctrl_specs{k,1}, ctrl_specs{k,2}, ctrl_specs{k,3});
    end
    local_add_constant(mdl_name, 'SeverityPct_cmd', 'ICDT_SeverityPct', [40, 290, 160, 310]);
    local_add_constant(mdl_name, 'LoadFracPct_cmd', 'ICDT_LoadFracPct', [40, 340, 160, 360]);

    add_block('simulink/Math Operations/Gain', [mdl_name '/D_cmd'], ...
        'Gain', '0.01', 'Position', [200, 290, 260, 310]);
    add_line(mdl_name, 'SeverityPct_cmd/1', 'D_cmd/1', 'autorouting', 'on');

    add_block('simulink/Math Operations/Gain', [mdl_name '/LoadFrac_cmd'], ...
        'Gain', '0.01', 'Position', [200, 340, 260, 360]);
    add_line(mdl_name, 'LoadFracPct_cmd/1', 'LoadFrac_cmd/1', 'autorouting', 'on');

    % ---- Organizational subsystems (§9), each a labeled single-input
    % pass-through-to-Terminator fed by a direct branch of one relevant
    % control signal (see docstring for why: independent taps, not a
    % shared bus/chain) ----
    org_specs = { ...
        '02_Operating_Conditions', 'Ambient_cmd',  340,  40; ...
        '03_Motor',                'RPM_cmd',      340,  90; ...
        '04_Pump',                 'RPM_cmd',      340, 140; ...
        '05_Pump_Fault_Injection', 'D_cmd',        340, 190; ...
        '06_Chilled_Water_Loop',   'RPM_cmd',      340, 240; ...
        '07_CRAC',                 'ITLoad_cmd',   340, 290; ...
        '08_Fan',                  'RPM_cmd',      500,  40; ...
        '09_Fan_Fault_Injection',  'D_cmd',        500,  90; ...
        '10_Airflow',              'RPM_cmd',      500, 140; ...
        '11_Data_Center_Thermal_Model', 'ITLoad_cmd', 500, 190; ...
        '12_Vibration_Sensor',     'D_cmd',        500, 240; ...
        '13_Current_Sensor',       'RPM_cmd',      500, 290; ...
        '14_Signal_Processing',    'D_cmd',        660,  40};
    for k = 1:size(org_specs, 1)
        local_add_passthrough_tap(mdl_name, org_specs{k,1}, org_specs{k,2}, ...
            [org_specs{k,3}, org_specs{k,4}, org_specs{k,3}+120, org_specs{k,4}+40]);
    end

    % ---- 19_Visualization: the real work ----
    local_build_visualization_subsystem(mdl_name);

    % ---- 15-18: labeled output subsystems, each a real branch of the
    % twin's corresponding output ----
    out_specs = { ...
        '15_AI_Fault_Diagnosis', 'PredictedFault',    1000,  40; ...
        '16_Health_Index',        'HI',                1000,  90; ...
        '17_RUL',                  'RUL_hr',            1000, 140; ...
        '18_Maintenance_Decision', 'DecisionCode',      1000, 190};
    for k = 1:size(out_specs, 1)
        local_add_passthrough_tap(mdl_name, out_specs{k,1}, [], ...
            [out_specs{k,3}, out_specs{k,4}, out_specs{k,3}+140, out_specs{k,4}+40]);
    end
    add_line(mdl_name, '19_Visualization/7', '15_AI_Fault_Diagnosis/1', 'autorouting', 'on');
    add_line(mdl_name, '19_Visualization/1', '16_Health_Index/1', 'autorouting', 'on');
    add_line(mdl_name, '19_Visualization/2', '17_RUL/1', 'autorouting', 'on');
    add_line(mdl_name, '19_Visualization/6', '18_Maintenance_Decision/1', 'autorouting', 'on');

    % ---- Scope (§11): Health Index, Temperature, Thermal margin ----
    add_block('simulink/Sinks/Scope', [mdl_name '/HI_Temp_Margin_Scope'], ...
        'Position', [1000, 260, 1060, 320], 'NumInputPorts', '3');
    add_line(mdl_name, '19_Visualization/1', 'HI_Temp_Margin_Scope/1', 'autorouting', 'on');
    add_line(mdl_name, '19_Visualization/3', 'HI_Temp_Margin_Scope/2', 'autorouting', 'on');
    add_line(mdl_name, '19_Visualization/4', 'HI_Temp_Margin_Scope/3', 'autorouting', 'on');

    % ---- Wire the controls into 19_Visualization's 7 inputs ----
    add_line(mdl_name, 'Equipment_cmd/1', '19_Visualization/1', 'autorouting', 'on');
    add_line(mdl_name, 'Fault_cmd/1', '19_Visualization/2', 'autorouting', 'on');
    add_line(mdl_name, 'D_cmd/1', '19_Visualization/3', 'autorouting', 'on');
    add_line(mdl_name, 'RPM_cmd/1', '19_Visualization/4', 'autorouting', 'on');
    add_line(mdl_name, 'LoadFrac_cmd/1', '19_Visualization/5', 'autorouting', 'on');
    add_line(mdl_name, 'Ambient_cmd/1', '19_Visualization/6', 'autorouting', 'on');
    add_line(mdl_name, 'ITLoad_cmd/1', '19_Visualization/7', 'autorouting', 'on');

    % ---- Wire the organizational taps (each fed by a branch of the same
    % source signal already feeding a control/visualization port) ----
    for k = 1:size(org_specs, 1)
        add_line(mdl_name, [org_specs{k,2} '/1'], [org_specs{k,1} '/1'], 'autorouting', 'on');
    end

    fprintf('=== Phase 9 - save model ===\n');
    if ~isfolder(models_dir); mkdir(models_dir); end
    save_system(mdl_name, mdl_path);
    close_system(mdl_name, 0);
    fprintf('  Saved to %s\n', mdl_path);

    fprintf('=== Phase 10 - structural validation ===\n');
    validate_interactive_digital_twin();
end

% ======================================================================
function local_add_constant(mdl_name, block_name, var_name, position)
    add_block('simulink/Sources/Constant', [mdl_name '/' block_name], ...
        'Value', var_name, 'Position', position);
end

% ------------------------------------------------------------------
function local_add_passthrough_tap(mdl_name, subsys_name, ~, position)
%LOCAL_ADD_PASSTHROUGH_TAP One labeled Subsystem (In1->Out1) with its
%   output terminated — the caller wires In1 separately (either from a
%   direct branch, per org_specs, or from 19_Visualization's outputs,
%   per out_specs).
    blk = [mdl_name '/' subsys_name];
    add_block('built-in/Subsystem', blk, 'Position', position);
    add_block('simulink/Sources/In1', [blk '/In1'], 'Position', [30, 40, 60, 60]);
    add_block('simulink/Sinks/Out1', [blk '/Out1'], 'Position', [150, 40, 180, 60]);
    add_line(blk, 'In1/1', 'Out1/1', 'autorouting', 'on');

    term_pos_x = position(3) + 40;
    add_block('simulink/Sinks/Terminator', [mdl_name '/' subsys_name '_term'], ...
        'Position', [term_pos_x, position(2), term_pos_x+30, position(2)+20]);
    add_line(mdl_name, [subsys_name '/1'], [subsys_name '_term/1'], 'autorouting', 'on');
end

% ------------------------------------------------------------------
function local_build_visualization_subsystem(mdl_name)
%LOCAL_BUILD_VISUALIZATION_SUBSYSTEM 19_Visualization: 7 named inputs ->
%   MechanicalAnimation (fast, sink) + DigitalTwinCoreAndDashboard (slow,
%   7 outputs) -> 7 named outputs. The isPump/isFan/Product blocks derive
%   per-equipment severity for the animation's coloring, per
%   MechanicalAnimation.m's docstring.

    v = [mdl_name '/19_Visualization'];
    add_block('built-in/Subsystem', v, 'Position', [740, 60, 960, 420]);

    in_names = {'Equipment','Fault','D','RPM','LoadFrac','Ambient','ITLoad'};
    for k = 1:numel(in_names)
        add_block('simulink/Sources/In1', [v '/' in_names{k}], ...
            'Position', [30, 30 + (k-1)*40, 60, 50 + (k-1)*40]);
    end

    out_names = {'HI','RUL_hr','T_server','Margin','CoolEff','DecisionCode','PredictedCode'};
    for k = 1:numel(out_names)
        add_block('simulink/Sinks/Out1', [v '/' out_names{k}], ...
            'Position', [700, 30 + (k-1)*40, 730, 50 + (k-1)*40]);
    end

    add_block('simulink/User-Defined Functions/MATLAB System', [v '/DigitalTwinCoreAndDashboard'], ...
        'Position', [300, 30, 500, 320]);
    set_param([v '/DigitalTwinCoreAndDashboard'], 'System', 'DigitalTwinCoreAndDashboard');

    for k = 1:numel(in_names)
        add_line(v, [in_names{k} '/1'], ...
            ['DigitalTwinCoreAndDashboard/' num2str(k)], 'autorouting', 'on');
    end
    for k = 1:numel(out_names)
        add_line(v, ['DigitalTwinCoreAndDashboard/' num2str(k)], ...
            [out_names{k} '/1'], 'autorouting', 'on');
    end

    add_block('simulink/Logic and Bit Operations/Compare To Constant', [v '/isPump'], ...
        'Position', [150, 380, 220, 410], 'relop', '==', 'const', '1');
    add_line(v, 'Equipment/1', 'isPump/1', 'autorouting', 'on');

    add_block('simulink/Logic and Bit Operations/Compare To Constant', [v '/isFan'], ...
        'Position', [150, 430, 220, 460], 'relop', '==', 'const', '2');
    add_line(v, 'Equipment/1', 'isFan/1', 'autorouting', 'on');

    add_block('simulink/Math Operations/Product', [v '/D_pump_display'], ...
        'Position', [260, 380, 300, 410]);
    add_line(v, 'D/1', 'D_pump_display/1', 'autorouting', 'on');
    add_line(v, 'isPump/1', 'D_pump_display/2', 'autorouting', 'on');

    add_block('simulink/Math Operations/Product', [v '/D_fan_display'], ...
        'Position', [260, 430, 300, 460]);
    add_line(v, 'D/1', 'D_fan_display/1', 'autorouting', 'on');
    add_line(v, 'isFan/1', 'D_fan_display/2', 'autorouting', 'on');

    add_block('simulink/User-Defined Functions/MATLAB System', [v '/MechanicalAnimation'], ...
        'Position', [400, 380, 600, 470]);
    set_param([v '/MechanicalAnimation'], 'System', 'MechanicalAnimation');
    add_line(v, 'RPM/1', 'MechanicalAnimation/1', 'autorouting', 'on');
    add_line(v, 'RPM/1', 'MechanicalAnimation/2', 'autorouting', 'on');
    add_line(v, 'D_pump_display/1', 'MechanicalAnimation/3', 'autorouting', 'on');
    add_line(v, 'D_fan_display/1', 'MechanicalAnimation/4', 'autorouting', 'on');
    add_line(v, 'Equipment/1', 'MechanicalAnimation/5', 'autorouting', 'on');
end
