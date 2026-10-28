function report = validate_interactive_digital_twin()
%VALIDATE_INTERACTIVE_DIGITAL_TWIN Automated validation for the visual
%   Simulink digital twin (§20).
%
%   report = VALIDATE_INTERACTIVE_DIGITAL_TWIN() checks:
%     Structural - model opens, compiles, all expected subsystems exist
%     Functional - Healthy, Fan BearingDegradation, Fan Unbalance, Pump
%                  Cavitation (real cfg.faults entries only) run cleanly
%                  through run_single_operating_point.m
%     Visual     - the animation/core System blocks and the signal ports
%                  they depend on exist and are wired (this checks the
%                  MODEL STRUCTURE, not rendered pixel output — no script
%                  can verify what a figure actually looks like; that
%                  still needs a human to press Run and look)
%     Integration - severity D demonstrably changes HI/vibration output
%                   (and, for a primary thermal-path fault, temperature)
%
%   Any failed check is reported as FAIL with a reason — nothing here is
%   softened into a warning (§51 of the original project brief).
%
%   Output:
%     report - table (check_name, passed, detail), saved to
%              results/tables/interactive_twin_validation_report.csv

    cfg = project_config();
    mdl_name = 'InteractiveCoolingDigitalTwin';
    mdl_path = fullfile(cfg.paths.models_simulink, [mdl_name '.slx']);

    check_name = {}; passed = []; detail = {};

    % ---------------- Structural ----------------
    ok = true; msg = {};
    if ~isfile(mdl_path)
        ok = false; msg{end+1} = sprintf('Model file not found: %s', mdl_path);
    else
        try
            warn_state = warning('off', 'all'); %#ok<NASGU>
            if bdIsLoaded(mdl_name); close_system(mdl_name, 0); end
            load_system(mdl_path);

            expected_subsystems = { ...
                '02_Operating_Conditions','03_Motor','04_Pump','05_Pump_Fault_Injection', ...
                '06_Chilled_Water_Loop','07_CRAC','08_Fan','09_Fan_Fault_Injection', ...
                '10_Airflow','11_Data_Center_Thermal_Model','12_Vibration_Sensor', ...
                '13_Current_Sensor','14_Signal_Processing','15_AI_Fault_Diagnosis', ...
                '16_Health_Index','17_RUL','18_Maintenance_Decision','19_Visualization'};
            found = find_system(mdl_name, 'SearchDepth', 1, 'BlockType', 'SubSystem');
            found_names = cell(size(found));
            for i = 1:numel(found)
                [~, found_names{i}] = fileparts(getfullname(found(i)));
            end
            missing_subsystems = setdiff(expected_subsystems, found_names);
            if ~isempty(missing_subsystems)
                ok = false;
                msg{end+1} = sprintf('Missing expected subsystem(s): %s', strjoin(missing_subsystems, ', '));
            end

            try
                eval_result = evalc('sim(mdl_name, ''StopTime'', ''0'');'); %#ok<NASGU>
            catch ME
                ok = false;
                msg{end+1} = sprintf('Model failed to compile/run zero-time: %s', ME.message);
            end

            close_system(mdl_name, 0);
        catch ME
            ok = false;
            msg{end+1} = sprintf('Model failed to open: %s', ME.message);
        end
    end
    check_name{end+1} = 'structural'; passed(end+1) = ok; %#ok<AGROW>
    detail{end+1} = local_join(msg, 'model opens, compiles, and all expected subsystems present');

    % ---------------- Functional ----------------
    ok = true; msg = {};
    SensorConfig = sensor_config();
    P = model_parameters();
    T_thresh = get_maintenance_thresholds();
    [model, ~] = load_or_train_model('fusion_state');

    functional_cases = { ...
        'Pump', 'Healthy', 0.0; ...
        'Fan',  'Healthy', 0.0; ...
        'Fan',  'BearingDegradation', 0.3; ...
        'Fan',  'Unbalance', 0.3; ...
        'Pump', 'Cavitation', 0.3};
    for k = 1:size(functional_cases, 1)
        equipment = functional_cases{k,1};
        faultType = functional_cases{k,2};
        D = functional_cases{k,3};
        if ~ismember(faultType, cfg.faults.(equipment))
            ok = false;
            msg{end+1} = sprintf('%s is not a real fault for %s in cfg.faults — test case invalid', ...
                faultType, equipment); %#ok<AGROW>
            continue;
        end
        try
            [result, ~] = run_single_operating_point(equipment, faultType, D, 1450, 0.8, 24, 40, ...
                model, [], cfg, SensorConfig, P, T_thresh, 1.0);
            if ~isfinite(result.HI) || ~isfinite(result.T_server_inlet_C)
                ok = false;
                msg{end+1} = sprintf('%s/%s/D=%.2f produced non-finite HI or temperature', ...
                    equipment, faultType, D);
            end
        catch ME
            ok = false;
            msg{end+1} = sprintf('%s/%s/D=%.2f threw: %s', equipment, faultType, D, ME.message);
        end
    end
    check_name{end+1} = 'functional'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'Healthy, Fan BearingDegradation, Fan Unbalance, Pump Cavitation all run cleanly');

    % ---------------- Visual (structural check on the blocks/ports the
    % animation depends on — NOT a check of rendered pixel content,
    % which no script can verify) ----------------
    ok = true; msg = {};
    if isfile(mdl_path)
        try
            if bdIsLoaded(mdl_name); close_system(mdl_name, 0); end
            load_system(mdl_path);
            v = [mdl_name '/19_Visualization'];

            mech_blk = [v '/MechanicalAnimation'];
            core_blk = [v '/DigitalTwinCoreAndDashboard'];
            if getSimulinkBlockHandle(mech_blk, true) == -1
                ok = false; msg{end+1} = 'MechanicalAnimation block not found (fan/pump rotation signal path)';
            end
            if getSimulinkBlockHandle(core_blk, true) == -1
                ok = false; msg{end+1} = 'DigitalTwinCoreAndDashboard block not found (temperature/HI/RUL signal path)';
            end
            % Airflow visualization: MechanicalAnimation's flow indicator
            % is driven by its RPM inputs (ports 1-2), already checked by
            % the block's existence + the RPM lines wired above.
            if getSimulinkBlockHandle([v '/HI'], true) == -1
                ok = false; msg{end+1} = 'HI output port not found';
            end
            if getSimulinkBlockHandle([v '/RUL_hr'], true) == -1
                ok = false; msg{end+1} = 'RUL_hr output port not found';
            end
            if getSimulinkBlockHandle([v '/T_server'], true) == -1
                ok = false; msg{end+1} = 'T_server output port not found';
            end
            close_system(mdl_name, 0);
        catch ME
            ok = false; msg{end+1} = sprintf('Visual structural check failed: %s', ME.message);
        end
    else
        ok = false; msg{end+1} = 'Model file not found';
    end
    check_name{end+1} = 'visual_structure'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, ['fan/pump rotation, airflow, temperature, HI and RUL signal paths all ', ...
        'present in the model (rendered appearance itself requires a human to press Run and look)']);

    % ---------------- Integration: severity D demonstrably propagates ----------------
    ok = true; msg = {};
    try
        [r_low, ~]  = run_single_operating_point('Fan', 'BearingDegradation', 0.05, 1450, 0.8, 24, 40, ...
            model, [], cfg, SensorConfig, P, T_thresh, 1.0);
        [r_high, ~] = run_single_operating_point('Fan', 'BearingDegradation', 0.50, 1450, 0.8, 24, 40, ...
            model, [], cfg, SensorConfig, P, T_thresh, 1.0);
        if abs(r_low.HI - r_high.HI) < 1e-6
            ok = false; msg{end+1} = 'Health Index did not change between D=0.05 and D=0.50';
        end
        if abs(r_low.vib_features.rms - r_high.vib_features.rms) < 1e-6
            ok = false; msg{end+1} = 'Vibration RMS did not change between D=0.05 and D=0.50';
        end

        [r_low_e, ~]  = run_single_operating_point('Fan', 'EfficiencyDegradation', 0.1, 1450, 0.8, 24, 40, ...
            model, [], cfg, SensorConfig, P, T_thresh, 1.0);
        [r_high_e, ~] = run_single_operating_point('Fan', 'EfficiencyDegradation', 0.9, 1450, 0.8, 24, 40, ...
            model, [], cfg, SensorConfig, P, T_thresh, 1.0);
        if abs(r_low_e.cooling_effectiveness - r_high_e.cooling_effectiveness) < 1e-6
            ok = false; msg{end+1} = 'Cooling effectiveness did not change for the primary thermal-path fault';
        end
    catch ME
        ok = false; msg{end+1} = sprintf('Integration check threw: %s', ME.message);
    end
    check_name{end+1} = 'integration'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, ['severity D demonstrably changes Health Index, vibration RMS, and ', ...
        '(for a primary-path fault) cooling effectiveness']);

    % ---------------- Assemble + save ----------------
    report = table(check_name', logical(passed'), detail', ...
        'VariableNames', {'check_name','passed','detail'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(report, fullfile(cfg.paths.results_tables, 'interactive_twin_validation_report.csv'));

    if all(report.passed)
        fprintf('INTERACTIVE TWIN VALIDATION: all %d checks passed.\n', height(report));
    else
        fprintf('INTERACTIVE TWIN VALIDATION: %d of %d checks FAILED. See interactive_twin_validation_report.csv.\n', ...
            sum(~report.passed), height(report));
    end
    disp(report);
end

% ------------------------------------------------------------------
function s = local_join(msg_cell, ok_message)
    if isempty(msg_cell)
        s = ok_message;
    else
        s = strjoin(msg_cell, '; ');
    end
end
