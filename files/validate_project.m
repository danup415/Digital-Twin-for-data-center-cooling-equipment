function report = validate_project()
%VALIDATE_PROJECT Automated validation suite (§44).
%
%   report = VALIDATE_PROJECT() runs every check listed in §44 of the
%   original brief that is meaningful given what's built so far (Phases
%   1-12), and returns/saves a pass/fail report. Nothing here is a
%   soft warning dressed up as a pass — any failed check is reported as
%   FAIL with a reason, per §51 ("do not manipulate results").
%
%   Checks performed:
%     1. Parameter sanity        (model_parameters ranges physically valid)
%     2. Signal sanity           (NaN/Inf check on generated signals)
%     3. Fault injection check   (severity monotonicity: higher D -> lower eta)
%     4. Data-leakage audit      (no scenario_id split across Train/Val/Test)
%     5. Reproducibility check   (same seed -> identical dataset)
%     6. Simulink compile check  (model loads/compiles if Simulink present)
%
%   Output:
%     report - table with columns: check_name, passed, detail
%     Also saved to results/tables/validation_report.csv

    cfg = project_config();
    P   = model_parameters();
    SensorConfig = sensor_config();

    check_name = {};
    passed = [];
    detail = {};

    % ---------------- 1. Parameter sanity ----------------
    ok = true; msg = {};
    if ~(P.Pump.eta_nominal > 0 && P.Pump.eta_nominal <= 1)
        ok = false; msg{end+1} = 'Pump.eta_nominal out of (0,1]'; %#ok<AGROW>
    end
    if ~(P.Fan.eta_nominal > 0 && P.Fan.eta_nominal <= 1)
        ok = false; msg{end+1} = 'Fan.eta_nominal out of (0,1]';
    end
    if ~(P.Health.D_critical > 0 && P.Health.D_critical <= 1)
        ok = false; msg{end+1} = 'Health.D_critical out of (0,1]';
    end
    if P.Pump.NPSH_available_nominal_m <= P.Pump.NPSH_required_m
        ok = false; msg{end+1} = 'Nominal NPSH margin is non-positive';
    end
    check_name{end+1} = 'parameter_sanity'; passed(end+1) = ok; %#ok<AGROW>
    detail{end+1} = local_join(msg, 'all parameters within physical ranges');

    % ---------------- 2. Signal sanity ----------------
    ok = true; msg = {};
    t = (0:1/SensorConfig.Accelerometer.Fs:0.5)';
    bf_test = bearing_fault_frequencies(P.Pump.N_nominal_rpm, P.Bearing);
    sigparams_test = struct('cavitation_C',0.3,'unbalance_U',0.3,'bearing_D',0.3,'misalignment_M',0.3);
    x = generate_vibration_signal(t, bf_test.f_r, sigparams_test, bf_test, SensorConfig.Accelerometer);
    if any(isnan(x)) || any(isinf(x))
        ok = false; msg{end+1} = 'Vibration signal contains NaN/Inf';
    end
    MotorOut_test = motor_model(P.Pump.N_nominal_rpm, 50, P.Motor);
    t_cur = (0:1/SensorConfig.Current.Fs:0.5)';
    i_sig = generate_current_signal(t_cur, MotorOut_test, sigparams_test, SensorConfig.Current);
    if any(isnan(i_sig)) || any(isinf(i_sig))
        ok = false; msg{end+1} = 'Current signal contains NaN/Inf';
    end
    check_name{end+1} = 'signal_sanity'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'no NaN/Inf in generated vibration or current signals');

    % ---------------- 3. Fault injection monotonicity ----------------
    ok = true; msg = {};
    baseline = pump_model(P.Pump.N_nominal_rpm, 0.8, P);
    D_values = [0, 0.05, 0.15, 0.30, 0.50];
    eta_values = zeros(size(D_values));
    for k = 1:numel(D_values)
        [deg, ~] = apply_pump_fault('Cavitation', D_values(k), baseline, P);
        eta_values(k) = deg.eta;
    end
    if any(diff(eta_values) > 1e-9)
        ok = false; msg{end+1} = 'Cavitation eta is not monotonically non-increasing with D';
    end
    check_name{end+1} = 'fault_injection_monotonicity'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'efficiency decreases monotonically with cavitation severity D');

    % ---------------- 4. Data-leakage audit ----------------
    ok = true; msg = {};
    scenarios = generate_scenarios(cfg, 6);
    [~, ~, ic] = unique(scenarios.scenario_id);
    splits_per_scenario = splitapply(@(s) numel(unique(s)), scenarios.split, ic);
    if any(splits_per_scenario > 1)
        ok = false; msg{end+1} = 'Some scenario_id appears in more than one split';
    end
    check_name{end+1} = 'data_leakage_audit'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'every scenario_id maps to exactly one split');

    % ---------------- 5. Reproducibility check ----------------
    ok = true; msg = {};
    s1 = generate_scenarios(cfg, 3);
    s2 = generate_scenarios(cfg, 3);
    if ~isequal(s1.N_rpm, s2.N_rpm) || ~isequal(s1.load_frac, s2.load_frac)
        ok = false; msg{end+1} = 'generate_scenarios is not reproducible under a fixed seed';
    end
    check_name{end+1} = 'reproducibility_check'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'fixed seed (rng(42)) reproduces identical scenario tables');

    % ---------------- 6. Simulink compile check ----------------
    ok = true; msg = {};
    if isempty(ver('simulink'))
        ok = true;   % not a failure — toolbox absence is a documented fallback (§M)
        msg{end+1} = 'Simulink not installed in this environment — skipped, not failed';
    else
        try
            mdl_path = build_simulink_model(cfg);
            load_system(mdl_path);
            eval_result = evalc('sim(bdroot, ''StopTime'', ''0'');'); %#ok<NASGU>
            close_system(bdroot, 0);
        catch ME
            ok = false;
            msg{end+1} = ['Simulink model failed to build/compile: ' ME.message];
        end
    end
    check_name{end+1} = 'simulink_compile_check'; passed(end+1) = ok;
    detail{end+1} = local_join(msg, 'model builds and compiles for a zero-time run');

    % ---------------- Assemble + save ----------------
    report = table(check_name', logical(passed'), detail', ...
        'VariableNames', {'check_name','passed','detail'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(report, fullfile(cfg.paths.results_tables, 'validation_report.csv'));

    if all(report.passed)
        fprintf('VALIDATION: all %d checks passed.\n', height(report));
    else
        n_fail = sum(~report.passed);
        fprintf('VALIDATION: %d of %d checks FAILED. See validation_report.csv.\n', n_fail, height(report));
    end
end

% ------------------------------------------------------------------
function s = local_join(msg_cell, ok_message)
    if isempty(msg_cell)
        s = ok_message;
    else
        s = strjoin(msg_cell, '; ');
    end
end
