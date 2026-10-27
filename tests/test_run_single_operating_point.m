function report = test_run_single_operating_point()
%TEST_RUN_SINGLE_OPERATING_POINT Integration tests for the interactive
%   backend (Phase B).
%
%   report = TEST_RUN_SINGLE_OPERATING_POINT() runs the 5 required
%   scenarios against run_single_operating_point.m, each stepped forward
%   3 times (1 simulated hour apart) so the history-dependent outputs
%   (RUL, thermal trajectory) are actually exercised rather than trivially
%   evaluated on a single point. Returns/prints a pass/fail report in the
%   same style as validate_project.m, and saves it to
%   results/tables/phaseB_test_report.csv.
%
%   A quick classifier is trained once (via the EXISTING
%   generate_scenarios/generate_dataset/train_random_forest pipeline —
%   nothing new) and reused across all 5 scenarios, since Phase C
%   (train_and_save_model.m) does not exist yet at this point in the
%   phased build.
%
%   Each scenario is checked for:
%     - no NaN/Inf in vibration/MCSA features, Health Index, thermal
%       output, or cooling effectiveness
%     - finite server-inlet temperature
%     - thermal_margin_C internally consistent with T_safe - T_server
%     - Health Index in [0,100]
%     - decision.level is one of the 5 valid enumerated states
%     - predicted_fault_type is a member of the equipment's valid fault set
%     - vibration/current signal dimensions match the sampling
%       configuration
%     - AI inference completes without error
%     - RUL is NaN for a flat/healthy trend (expected, not a failure) and
%       finite for a genuinely degrading trend

    cfg = project_config();
    SensorConfig = sensor_config();
    P = model_parameters();
    T_thresh = get_maintenance_thresholds();

    % ---- Train one quick model via the EXISTING pipeline, reused below ----
    scenarios = generate_scenarios(cfg, 6);
    dataset = generate_dataset(cfg, SensorConfig, P, scenarios);
    [X_train, y_train, feat_names] = load_dataset_split(dataset, 'Train', 'fusion_state');
    model = train_random_forest(X_train, y_train, feat_names, cfg);

    test_name = {}; passed = []; detail = {};

    % =================================================================
    % Test 1: Pump + Healthy + D=0 (flat, 3 steps)
    % =================================================================
    [ok, msg] = local_run_case('Test1_Pump_Healthy', 'Pump', 'Healthy', ...
        [0 0 0], model, cfg, SensorConfig, P, T_thresh, true);
    test_name{end+1} = 'Test1_Pump_Healthy_D0'; passed(end+1) = ok; detail{end+1} = msg; %#ok<AGROW>

    % =================================================================
    % Test 2: Fan + Healthy + D=0 (flat, 3 steps)
    % =================================================================
    [ok, msg] = local_run_case('Test2_Fan_Healthy', 'Fan', 'Healthy', ...
        [0 0 0], model, cfg, SensorConfig, P, T_thresh, true);
    test_name{end+1} = 'Test2_Fan_Healthy_D0'; passed(end+1) = ok; detail{end+1} = msg;

    % =================================================================
    % Test 3: Fan + BearingDegradation + mild D (slowly ramping, 3 steps)
    % =================================================================
    [ok, msg] = local_run_case('Test3_Fan_Bearing_Mild', 'Fan', 'BearingDegradation', ...
        [0.02 0.05 0.08], model, cfg, SensorConfig, P, T_thresh, false);
    test_name{end+1} = 'Test3_Fan_BearingDegradation_Mild'; passed(end+1) = ok; detail{end+1} = msg;

    % =================================================================
    % Test 4: Fan + BearingDegradation + moderate D (ramping, 3 steps)
    % =================================================================
    [ok, msg] = local_run_case('Test4_Fan_Bearing_Moderate', 'Fan', 'BearingDegradation', ...
        [0.10 0.15 0.20], model, cfg, SensorConfig, P, T_thresh, false);
    test_name{end+1} = 'Test4_Fan_BearingDegradation_Moderate'; passed(end+1) = ok; detail{end+1} = msg;

    % =================================================================
    % Test 5: Severe fault scenario — Fan EfficiencyDegradation (the
    % primary fan->thermal path, §28), ramping toward Critical severity,
    % so this test also meaningfully exercises the thermal-consequence
    % chain, not just the AI/HI path.
    % =================================================================
    [ok, msg] = local_run_case('Test5_Fan_Efficiency_Severe', 'Fan', 'EfficiencyDegradation', ...
        [0.25 0.35 0.45], model, cfg, SensorConfig, P, T_thresh, false);
    test_name{end+1} = 'Test5_Fan_EfficiencyDegradation_Severe'; passed(end+1) = ok; detail{end+1} = msg;

    % ---- Assemble + save report ----
    report = table(test_name', logical(passed'), detail', ...
        'VariableNames', {'test_name','passed','detail'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(report, fullfile(cfg.paths.results_tables, 'phaseB_test_report.csv'));

    if all(report.passed)
        fprintf('PHASE B: all %d tests PASSED.\n', height(report));
    else
        fprintf('PHASE B: %d of %d tests FAILED. See phaseB_test_report.csv.\n', ...
            sum(~report.passed), height(report));
    end
    disp(report);
end

% ==================================================================
function [ok, msg] = local_run_case(case_label, equipment, fault_type, D_sequence, ...
    model, cfg, SensorConfig, P, T_thresh, expect_flat_rul)
%LOCAL_RUN_CASE Step run_single_operating_point through D_sequence and
%   check the final result against every Phase-B requirement. Wrapped in
%   try/catch so an error in one case is reported as a failure, not a
%   crash of the whole suite.

    try
        N_rpm = 1450;
        load_frac = 0.8;
        ambient_C = 24;
        IT_load_kW = 40;
        elapsed_hr = 1.0;

        history = [];
        result = [];
        for step = 1:numel(D_sequence)
            D = D_sequence(step);
            [result, history] = run_single_operating_point(equipment, fault_type, D, ...
                N_rpm, load_frac, ambient_C, IT_load_kW, model, history, cfg, SensorConfig, P, T_thresh, elapsed_hr);
        end

        problems = {};

        % ---- correct equipment/fault handling ----
        if ~strcmp(result.equipment, equipment)
            problems{end+1} = sprintf('equipment mismatch: got %s', result.equipment); %#ok<AGROW>
        end
        if ~strcmp(result.fault_type_injected, fault_type)
            problems{end+1} = sprintf('fault_type_injected mismatch: got %s', result.fault_type_injected);
        end
        if result.D_injected ~= D_sequence(end)
            problems{end+1} = 'D_injected does not match the last commanded severity';
        end

        % ---- vibration/MCSA features: no NaN/Inf ----
        if ~local_all_finite_struct(result.vib_features)
            problems{end+1} = 'vib_features contains NaN/Inf';
        end
        if ~local_all_finite_struct(result.mcsa_features)
            problems{end+1} = 'mcsa_features contains NaN/Inf';
        end

        % ---- Health Index ----
        if ~isfinite(result.HI) || result.HI < 0 || result.HI > 100
            problems{end+1} = sprintf('HI out of [0,100] or non-finite: %g', result.HI);
        end

        % ---- finite temperature ----
        if ~isfinite(result.T_server_inlet_C)
            problems{end+1} = sprintf('T_server_inlet_C non-finite: %g', result.T_server_inlet_C);
        end
        % Sanity-bound: a lumped data-hall thermal model has no physical
        % business producing triple-digit-or-worse temperatures; this
        % catches a silent return to the old Euler-instability failure
        % mode without hard-coding an exact expected value.
        if abs(result.T_server_inlet_C) > 200
            problems{end+1} = sprintf('T_server_inlet_C physically implausible: %g (numerical instability?)', result.T_server_inlet_C);
        end

        % ---- valid thermal margin, internally consistent ----
        if ~isfinite(result.thermal_margin_C)
            problems{end+1} = sprintf('thermal_margin_C non-finite: %g', result.thermal_margin_C);
        end
        expected_margin = P.Thermal.T_safe_C - result.T_server_inlet_C;
        if abs(result.thermal_margin_C - expected_margin) > 1e-6
            problems{end+1} = 'thermal_margin_C inconsistent with T_safe - T_server_inlet_C';
        end

        % ---- cooling effectiveness ----
        if ~isfinite(result.cooling_effectiveness) || result.cooling_effectiveness <= 0 || result.cooling_effectiveness > 1
            problems{end+1} = sprintf('cooling_effectiveness out of (0,1]: %g', result.cooling_effectiveness);
        end

        % ---- RUL: NaN expected for a flat/healthy trend, finite for a
        % genuinely degrading trend ----
        if expect_flat_rul
            if ~isnan(result.RUL_hr)
                problems{end+1} = sprintf('expected RUL=NaN for a flat/healthy trend, got %g', result.RUL_hr);
            end
        else
            if isnan(result.RUL_hr) || ~isfinite(result.RUL_hr)
                problems{end+1} = 'expected a finite RUL for a degrading trend, got NaN/Inf';
            end
        end

        % ---- valid decision ----
        valid_levels = {'NORMAL','MONITOR','WARNING','MAINTENANCE_REQUIRED','CRITICAL'};
        if ~ismember(result.decision.level, valid_levels)
            problems{end+1} = sprintf('decision.level not a valid state: %s', result.decision.level);
        end

        % ---- AI inference completes + returns a valid label ----
        valid_faults = cfg.faults.(equipment);
        if isempty(result.predicted_fault_type) || ~ismember(result.predicted_fault_type, valid_faults)
            problems{end+1} = sprintf('predicted_fault_type not a valid label for %s: %s', ...
                equipment, result.predicted_fault_type);
        end

        % ---- correct signal dimensions ----
        expected_vib_len = SensorConfig.Accelerometer.Fs;   % 1.0 s window
        expected_cur_len = SensorConfig.Current.Fs;
        if numel(result.signals.vib_signal) ~= expected_vib_len || ...
           numel(result.signals.vib_time)   ~= expected_vib_len
            problems{end+1} = sprintf('vibration signal length mismatch: got %d, expected %d', ...
                numel(result.signals.vib_signal), expected_vib_len);
        end
        if numel(result.signals.current_signal) ~= expected_cur_len || ...
           numel(result.signals.current_time)   ~= expected_cur_len
            problems{end+1} = sprintf('current signal length mismatch: got %d, expected %d', ...
                numel(result.signals.current_signal), expected_cur_len);
        end

        % ---- history buffer integrity ----
        n_steps = numel(D_sequence);
        if numel(history.time_hr) ~= n_steps || numel(history.HI) ~= n_steps
            problems{end+1} = sprintf('history length mismatch: expected %d steps', n_steps);
        end
        if ~local_all_finite_vec(history.HI) || ~local_all_finite_vec(history.time_hr)
            problems{end+1} = 'history.HI or history.time_hr contains NaN/Inf';
        end

        if isempty(problems)
            ok = true;
            msg = sprintf('%s: OK (final HI=%.1f, T=%.2fC, margin=%.2fC, decision=%s, AI predicted=%s)', ...
                case_label, result.HI, result.T_server_inlet_C, result.thermal_margin_C, ...
                result.decision.level, result.predicted_fault_type);
        else
            ok = false;
            msg = sprintf('%s: %s', case_label, strjoin(problems, '; '));
        end

    catch ME
        ok = false;
        msg = sprintf('%s: THREW ERROR: %s', case_label, ME.message);
    end
end

% ------------------------------------------------------------------
function tf = local_all_finite_struct(s)
    fields = fieldnames(s);
    tf = true;
    for k = 1:numel(fields)
        v = s.(fields{k});
        if ~isfinite(v)
            tf = false;
            return;
        end
    end
end

% ------------------------------------------------------------------
function tf = local_all_finite_vec(v)
    tf = all(isfinite(v));
end
