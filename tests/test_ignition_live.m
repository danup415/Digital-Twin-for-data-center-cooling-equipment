function report = test_ignition_live()
%TEST_IGNITION_LIVE End-to-end checks against a RUNNING Ignition Gateway.
%
%   report = TEST_IGNITION_LIVE() requires (see docs/IGNITION_DIGITAL_TWIN_SETUP.md):
%     - tags imported, Web Dev resources 'commands' and 'telemetry' saved,
%     - the same API key set in both scripts and in MATLAB.
%   It does NOT need the adapter loop to be running, and it WRITES to the
%   Status/Meta tags (it posts a heartbeat, one real engine step and a
%   disconnect), so run it before a demo, not during one.
%
%   Checks:
%     1  GET /commands succeeds and its command values pass validation
%     2  heartbeat POST round-trips: the Heartbeat value read back through
%        /commands equals the value posted, and LastUpdate is recent
%     3  a real engine step (run_single_operating_point) is accepted
%     4  a payload with an unknown fault label is REJECTED by the Gateway
%     5  a payload with severity > 1 is REJECTED by the Gateway
%     6  a disconnect POST is accepted
%
%   What this still cannot check: what Perspective displays. Those are the
%   manual checks in the setup guide.

    cfg = project_config();
    icfg = ignition_config();
    names = {}; passed = []; details = {};

    function add(name, ok, detail)
        names{end+1} = name; %#ok<AGROW>
        passed(end+1) = logical(ok); %#ok<AGROW>
        details{end+1} = detail; %#ok<AGROW>
    end

    % 1 -------------------------------------------------------------
    [ok, resp, err] = ignition_http('GET', 'commands', [], icfg);
    if ok
        [cmd_ok, ~, reason] = validate_ignition_command(resp, cfg, icfg);
        add('1_commands_endpoint_reachable_and_valid', cmd_ok, reason);
    else
        add('1_commands_endpoint_reachable_and_valid', false, err);
        finish(); return;
    end

    % 2 -------------------------------------------------------------
    hb_value = randi([1000, 900000]);
    hb = build_telemetry_payload('heartbeat', [], [], hb_value, 'LIVE TEST', icfg);
    [ok_post, ~, err_post] = ignition_http('POST', 'telemetry', hb, icfg);
    [ok_get, resp2, err_get] = ignition_http('GET', 'commands', [], icfg);
    round_trip = ok_post && ok_get && isfield(resp2, 'heartbeat') && resp2.heartbeat == hb_value;
    recent = false;
    if ok_get && isfield(resp2, 'lastUpdateMs') && ~isempty(resp2.lastUpdateMs)
        age_s = posixtime(datetime('now', 'TimeZone', 'UTC')) - resp2.lastUpdateMs / 1000;
        recent = abs(age_s) < 60;
    end
    add('2_heartbeat_round_trip_and_lastupdate_recent', round_trip && recent, ...
        sprintf('post=%d(%s) get=%d(%s) roundtrip=%d recent=%d', ok_post, err_post, ok_get, err_get, round_trip, recent));

    % 3 -------------------------------------------------------------
    [state, ctx] = ignition_engine_init(icfg);
    cmd = struct('equipment', 'Fan', 'faultType', 'BearingDegradation', 'severity', 0.3, ...
        'rpm', 1450, 'loadFraction', 0.8, 'ambientC', 24, 'itLoadKW', 40, 'run', true, 'resetSeq', 0);
    [payload, ~, ~] = ignition_engine_step(cmd, state, ctx);
    payload.commandResult = 'LIVE TEST';
    [ok3, ~, err3] = ignition_http('POST', 'telemetry', payload, icfg);
    add('3_real_engine_step_accepted_by_gateway', ok3, err3);

    % 4 -------------------------------------------------------------
    bad = payload; bad.injectedFault = 'Bogus';
    [ok4, ~, err4] = ignition_http('POST', 'telemetry', bad, icfg);
    add('4_unknown_fault_label_rejected_by_gateway', ~ok4 && contains(err4, 'rejected'), err4);

    % 5 -------------------------------------------------------------
    bad = payload; bad.severity = 1.5;
    [ok5, ~, err5] = ignition_http('POST', 'telemetry', bad, icfg);
    add('5_severity_above_1_rejected_by_gateway', ~ok5 && contains(err5, 'rejected'), err5);

    % 6 -------------------------------------------------------------
    dc = build_telemetry_payload('disconnect', [], [], 0, 'LIVE TEST DONE', icfg);
    [ok6, ~, err6] = ignition_http('POST', 'telemetry', dc, icfg);
    add('6_disconnect_accepted', ok6, err6);

    finish();

    function finish()
        report = table(names', logical(passed'), details', ...
            'VariableNames', {'test_name','passed','detail'});
        if ~isfolder(cfg.paths.results_tables), mkdir(cfg.paths.results_tables); end
        writetable(report, fullfile(cfg.paths.results_tables, 'ignition_live_test_report.csv'));
        if all(report.passed)
            fprintf('IGNITION LIVE: all %d checks PASSED.\n', height(report));
        else
            fprintf('IGNITION LIVE: %d of %d checks FAILED.\n', sum(~report.passed), height(report));
        end
        disp(report);
    end
end
