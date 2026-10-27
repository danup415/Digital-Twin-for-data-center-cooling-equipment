function report = test_ignition_adapter()
%TEST_IGNITION_ADAPTER Offline tests for the Ignition integration (no Gateway needed).
%
%   report = TEST_IGNITION_ADAPTER() runs, in MATLAB only:
%     - command validation (valid accepted; bad fault, severity, rpm, load,
%       types, Healthy-with-severity rejected)
%     - telemetry payload contract (fields, finite, JSON-encodable)
%     - stale-timestamp detection
%     - unreachable-Gateway and missing-key handling in ignition_http
%     - real engine scenarios (Healthy, Fan bearing degradation, Pump
%       cavitation) through run_single_operating_point.m
%     - injected vs predicted labels stay separate
%     - HI / cooling effectiveness / thermal / RUL in the payload equal
%       DIRECT calls to the existing functions on the same history
%     - progressive severity changes real outputs
%     - history reset when the fault scenario changes
%
%   What this does NOT test: anything that needs a running Gateway (see
%   test_ignition_live.m) or Perspective (manual checks in
%   docs/IGNITION_DIGITAL_TWIN_SETUP.md).
%
%   Output: table (test_name, passed, detail), also saved to
%   results/tables/ignition_adapter_test_report.csv

    cfg = project_config();
    icfg = ignition_config();
    names = {}; passed = []; details = {};

    function add(name, ok, detail)
        names{end+1} = name; %#ok<AGROW>
        passed(end+1) = logical(ok); %#ok<AGROW>
        details{end+1} = detail; %#ok<AGROW>
    end

    good = struct('equipment', 'Fan', 'faultType', 'BearingDegradation', 'severity', 0.3, ...
        'rpm', 1450, 'loadFraction', 0.8, 'ambientC', 24, 'itLoadKW', 40, 'run', true, 'resetSeq', 0);

    % ---------------- 1. validation ----------------
    [ok, clean, reason] = validate_ignition_command(good, cfg, icfg);
    add('1_valid_command_accepted', ok && strcmp(clean.faultType, 'BearingDegradation') && islogical(clean.run), reason);

    bad = good; bad.faultType = 'Bogus';
    [ok, ~, reason] = validate_ignition_command(bad, cfg, icfg);
    add('2a_invalid_fault_name_rejected', ~ok && contains(reason, 'faultType'), reason);

    bad = good; bad.equipment = 'Pump'; bad.faultType = 'EfficiencyDegradation';
    [ok, ~, reason] = validate_ignition_command(bad, cfg, icfg);
    add('2b_fan_only_fault_rejected_for_pump', ~ok, reason);

    bad = good; bad.faultType = 'bearingdegradation';
    [ok, ~, reason] = validate_ignition_command(bad, cfg, icfg);
    add('2c_fault_label_is_case_sensitive', ~ok, reason);

    sev_cases = {-0.1, 1.5, NaN, Inf, '0.3', [0.1 0.2], true};
    all_rejected = true; msg = '';
    for k = 1:numel(sev_cases)
        bad = good; bad.severity = sev_cases{k};
        [ok, ~, r] = validate_ignition_command(bad, cfg, icfg);
        if ok
            all_rejected = false; msg = sprintf('severity case %d was accepted', k);
        end
        if k == 1, reason = r; end %#ok<NASGU>
    end
    add('3_severity_outside_0_1_or_wrong_type_rejected', all_rejected, msg);

    bad = good; bad.faultType = 'Healthy'; bad.severity = 0.4;
    [ok, ~, reason] = validate_ignition_command(bad, cfg, icfg);
    add('3b_healthy_with_nonzero_severity_rejected', ~ok && contains(reason, 'Healthy'), reason);

    r = cfg.operating.speed_rpm_range; lr = cfg.operating.load_pct_range / 100;
    ar = cfg.operating.ambient_C_range;
    rejected = true; msg = '';
    probes = {'rpm', r(1)-1; 'rpm', r(2)+1; 'rpm', NaN; 'loadFraction', lr(1)-0.01; ...
        'loadFraction', lr(2)+0.01; 'ambientC', ar(1)-1; 'ambientC', ar(2)+1; ...
        'itLoadKW', icfg.it_load_range_kW(1)-1; 'itLoadKW', icfg.it_load_range_kW(2)+1};
    for k = 1:size(probes, 1)
        bad = good; bad.(probes{k,1}) = probes{k,2};
        [ok, ~, ~] = validate_ignition_command(bad, cfg, icfg);
        if ok
            rejected = false; msg = sprintf('%s=%g accepted', probes{k,1}, probes{k,2});
        end
    end
    add('4_invalid_rpm_load_ambient_itload_rejected', rejected, msg);

    bad = rmfield(good, 'rpm');
    [ok, ~, reason] = validate_ignition_command(bad, cfg, icfg);
    add('4b_missing_field_rejected', ~ok && contains(reason, 'rpm'), reason);

    [ok, ~, ~] = validate_ignition_command('not a struct', cfg, icfg);
    add('4c_non_struct_rejected', ~ok, '');

    % ---------------- 5. payload contract ----------------
    [state, ctx] = ignition_engine_init(icfg);
    [payload, state1, result] = ignition_engine_step(good, state, ctx);
    fields_m = [{'kind','schema','tsUtc'}, {'connection','commandResult','heartbeat'}, ...
        {'injectedEquipment','injectedFault','predictedFault','severity','vibrationRMS', ...
         'currentRMS','healthIndex','rulValid','rulHours','rulHistoryPoints', ...
         'coolingEffectiveness','serverTemperatureC','thermalMarginC','maintenanceState', ...
         'maintenanceReason','simTimeHours'}];
    has_all = all(isfield(payload, fields_m));
    can_encode = true;
    try, jsonencode(payload); catch, can_encode = false; end
    num_ok = true;
    for f = {'severity','vibrationRMS','currentRMS','healthIndex','rulHours','coolingEffectiveness', ...
            'serverTemperatureC','thermalMarginC','simTimeHours'}
        v = payload.(f{1});
        num_ok = num_ok && isnumeric(v) && isscalar(v) && isfinite(v);
    end
    add('5_telemetry_payload_has_expected_fields', has_all && can_encode && num_ok, ...
        sprintf('fields=%d encodable=%d finite=%d', has_all, can_encode, num_ok));

    hb = build_telemetry_payload('heartbeat', [], [], 5, 'OK', icfg);
    add('5b_heartbeat_payload_minimal', all(isfield(hb, {'connection','commandResult','heartbeat'})) ...
        && ~isfield(hb, 'healthIndex'), '');

    nan_result = result; nan_result.HI = NaN;
    threw = false;
    try, build_telemetry_payload('telemetry', nan_result, state1.history, 1, 'OK', icfg); catch, threw = true; end
    add('5c_nonfinite_result_refused', threw, '');

    % ---------------- 6/7. disconnected + stale ----------------
    bad_cfg = icfg; bad_cfg.api_key = 'x'; bad_cfg.http_timeout_s = 1;
    bad_cfg.webdev_root = 'http://localhost:9/system/webdev/CoolingDigitalTwin/';
    t0 = tic;
    [ok, ~, err] = ignition_http('GET', 'commands', [], bad_cfg);
    add('6_unreachable_gateway_reported_not_thrown', ~ok && ~isempty(err) && toc(t0) < 10, err);

    nokey = icfg; nokey.api_key = '';
    [ok, ~, err] = ignition_http('GET', 'commands', [], nokey);
    add('6b_missing_api_key_refused', ~ok && contains(err, 'API key'), err);

    now_utc = datetime(2026, 1, 1, 12, 0, 0, 'TimeZone', 'UTC');
    add('7_fresh_timestamp_not_stale', ~ignition_is_stale('2026-01-01T11:59:55.000Z', 10, now_utc), '');
    add('7b_old_timestamp_is_stale', ignition_is_stale('2026-01-01T11:59:40.000Z', 10, now_utc), '');
    add('7c_garbage_or_empty_timestamp_is_stale', ...
        ignition_is_stale('garbage', 10, now_utc) && ignition_is_stale('', 10, now_utc), '');

    % ---------------- 8-10. scenarios ----------------
    scenarios = { ...
        '8_healthy_scenario', 'Fan', 'Healthy', [0 0 0]; ...
        '9_bearing_degradation_scenario', 'Fan', 'BearingDegradation', [0.1 0.3 0.5]; ...
        '10_pump_cavitation_scenario', 'Pump', 'Cavitation', [0.1 0.3 0.5]};
    for k = 1:size(scenarios, 1)
        st = state;
        ok_all = true; msg = '';
        try
            for D = scenarios{k,4}
                c = good; c.equipment = scenarios{k,2}; c.faultType = scenarios{k,3}; c.severity = D;
                [pl, st, ~] = ignition_engine_step(c, st, ctx);
                ok_all = ok_all && strcmp(pl.injectedFault, scenarios{k,3}) && isfinite(pl.healthIndex);
            end
            msg = sprintf('final HI=%.1f state=%s predicted=%s', pl.healthIndex, pl.maintenanceState, pl.predictedFault);
        catch ME
            ok_all = false; msg = ME.message;
        end
        add(scenarios{k,1}, ok_all, msg);
    end

    % ---------------- 11. injected vs predicted separate ----------------
    c = good; c.faultType = 'Unbalance'; c.severity = 0.4;
    [pl, ~, ~] = ignition_engine_step(c, state, ctx);
    add('11_injected_and_predicted_are_separate_fields', ...
        isfield(pl, 'injectedFault') && isfield(pl, 'predictedFault') && strcmp(pl.injectedFault, 'Unbalance'), ...
        sprintf('injected=%s predicted=%s', pl.injectedFault, pl.predictedFault));

    % ---------------- 12. values come from the existing functions ----------------
    st = state;
    for D = [0.2 0.4 0.6]
        c = good; c.faultType = 'BearingDegradation'; c.severity = D;
        [pl, st, ~] = ignition_engine_step(c, st, ctx);
    end
    P = ctx.P; h = st.history;
    hi_direct = compute_health_index(0.6, P.Health);
    eff_direct = cooling_effectiveness_from_degradation('Fan', 'BearingDegradation', 0.6);
    traj = thermal_digital_twin(h.time_hr * 3600, h.IT_load_kW, h.ambient_C, h.effectiveness, P.Thermal);
    rul = estimate_rul(h.time_hr, h.HI, P.Health);
    same_hi = abs(pl.healthIndex - hi_direct) < 1e-9;
    same_eff = abs(pl.coolingEffectiveness - eff_direct) < 1e-9;
    same_t = abs(pl.serverTemperatureC - traj.T_server_inlet_C(end)) < 1e-9 && ...
             abs(pl.thermalMarginC - traj.thermal_margin_C(end)) < 1e-9;
    if isfinite(rul.RUL)
        same_rul = pl.rulValid && abs(pl.rulHours - rul.RUL) < 1e-9;
    else
        same_rul = ~pl.rulValid;
    end
    add('12_values_match_direct_calls_to_existing_functions', same_hi && same_eff && same_t && same_rul, ...
        sprintf('HI=%d eff=%d thermal=%d rul=%d', same_hi, same_eff, same_t, same_rul));

    % ---------------- 13. progressive severity changes real outputs ----------------
    st = state; hi_seq = []; vib_seq = []; eff_seq = []; t_seq = [];
    for D = [0 0.2 0.5 0.8 1.0]
        c = good; c.faultType = 'BearingDegradation'; c.severity = D;
        if D == 0, c.faultType = 'Healthy'; end
        [~, st, r] = ignition_engine_step(c, st, ctx);
        hi_seq(end+1) = r.HI; vib_seq(end+1) = r.vib_features.rms; %#ok<AGROW>
    end
    % compute_health_index clamps at 0 once D reaches D_critical (0.6), so the
    % sequence is non-increasing (not strictly decreasing) and must end lower.
    add('13a_bearing_progression_lowers_health_index', all(diff(hi_seq) <= 0) && hi_seq(end) < hi_seq(1), mat2str(round(hi_seq, 1)));
    add('13b_bearing_progression_changes_vibration', abs(vib_seq(end) - vib_seq(1)) > 1e-6, mat2str(round(vib_seq, 4)));

    st = state;
    for D = [0 0.25 0.5 0.75 1.0]
        c = good; c.faultType = 'EfficiencyDegradation'; c.severity = D;
        if D == 0, c.faultType = 'Healthy'; end
        [~, st, r] = ignition_engine_step(c, st, ctx);
        eff_seq(end+1) = r.cooling_effectiveness; t_seq(end+1) = r.T_server_inlet_C; %#ok<AGROW>
    end
    % The first (Healthy) step starts a new trajectory when the label changes at step 2,
    % so compare only the EfficiencyDegradation steps.
    add('13c_efficiency_degradation_lowers_cooling_and_raises_temperature', ...
        eff_seq(end) < eff_seq(2) && t_seq(end) > t_seq(2), ...
        sprintf('eff %s | T %s', mat2str(round(eff_seq, 3)), mat2str(round(t_seq, 2))));

    % ---------------- 14. history reset on scenario change ----------------
    st = state;
    c = good; c.faultType = 'BearingDegradation';
    for D = [0.1 0.2 0.3]
        c.severity = D; [~, st, ~] = ignition_engine_step(c, st, ctx);
    end
    c.equipment = 'Pump'; c.faultType = 'Cavitation'; c.severity = 0.2;
    [pl, ~, ~] = ignition_engine_step(c, st, ctx);
    add('14_history_resets_when_fault_scenario_changes', pl.rulHistoryPoints == 1, ...
        sprintf('history points after switch = %d', pl.rulHistoryPoints));

    % ---------------- report ----------------
    report = table(names', logical(passed'), details', 'VariableNames', {'test_name','passed','detail'});
    if ~isfolder(cfg.paths.results_tables), mkdir(cfg.paths.results_tables); end
    writetable(report, fullfile(cfg.paths.results_tables, 'ignition_adapter_test_report.csv'));
    if all(report.passed)
        fprintf('IGNITION ADAPTER: all %d tests PASSED.\n', height(report));
    else
        fprintf('IGNITION ADAPTER: %d of %d tests FAILED.\n', sum(~report.passed), height(report));
    end
    disp(report);
end
