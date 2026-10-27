function run_ignition_adapter(varargin)
%RUN_IGNITION_ADAPTER Connect the MATLAB engine to the Ignition Gateway.
%
%   RUN_IGNITION_ADAPTER()
%   RUN_IGNITION_ADAPTER('MaxRuntimeS', 600)
%
%   Loop (every icfg.poll_interval_s, never faster than 0.25 s):
%     1. GET  /commands   -> operator commands from the Commands/* tags
%     2. validate_ignition_command -> reject anything not allowed
%     3. if Run is true and a tick interval has elapsed:
%          ignition_engine_step -> run_single_operating_point (real model)
%     4. POST /telemetry  -> full results (after a step) or a heartbeat
%
%   HOW TO STOP (this never runs forever):
%     - press Ctrl+C in the MATLAB command window, or
%     - create the file src/ignition/STOP_ADAPTER (from another MATLAB
%       session or Explorer), or
%     - wait for MaxRuntimeS (default icfg.max_runtime_s = 1800 s).
%   On ANY exit a 'disconnect' payload is posted, so Perspective shows
%   BACKEND DISCONNECTED instead of leaving old numbers looking live.
%
%   Commands that fail validation are NOT executed; the reason is published
%   in Meta/LastCommandResult. If the Gateway is unreachable the loop keeps
%   retrying with a back-off and prints one line per state change.
%
%   Everything published is simulation output from the existing project
%   functions; nothing here controls physical equipment.

    icfg = ignition_config();
    p = inputParser;
    addParameter(p, 'MaxRuntimeS', icfg.max_runtime_s, @(x) isnumeric(x) && isscalar(x) && x > 0);
    parse(p, varargin{:});
    icfg.max_runtime_s = p.Results.MaxRuntimeS;
    poll_s = max(icfg.poll_interval_s, 0.25);

    if isempty(icfg.api_key)
        error('run_ignition_adapter:noKey', ...
            ['API key not set. Set environment variable COOLING_TWIN_API_KEY or create ', ...
             'src/ignition/ignition_secret.txt (see ignition_config.m).']);
    end

    fprintf('Loading engine (classifier is loaded once, never retrained)...\n');
    [state, ctx] = ignition_engine_init(icfg);
    cfg = ctx.cfg;

    if isfile(icfg.stop_file)
        delete(icfg.stop_file);   % clear a stale stop flag from a previous run
    end
    cleanup = onCleanup(@() local_post_disconnect(icfg)); %#ok<NASGU>

    fprintf(['Adapter running against %s (max %d s). Stop: Ctrl+C or create %s\n'], ...
        icfg.webdev_root, round(icfg.max_runtime_s), icfg.stop_file);

    t_start = tic;
    t_last_tick = -inf;
    last_reset = [];
    was_connected = [];
    was_running = [];
    consecutive_failures = 0;

    while toc(t_start) < icfg.max_runtime_s
        if isfile(icfg.stop_file)
            fprintf('Stop file found: stopping.\n');
            break;
        end
        loop_timer = tic;

        [ok_get, raw, err] = ignition_http('GET', 'commands', [], icfg);
        if ~ok_get
            consecutive_failures = consecutive_failures + 1;
            if isempty(was_connected) || was_connected
                fprintf('Gateway not reachable / rejected: %s (retrying)\n', err);
            end
            was_connected = false;
            pause(min(0.5 * consecutive_failures, 5));
            continue;
        end
        if isempty(was_connected) || ~was_connected
            fprintf('Connected to Gateway.\n');
        end
        was_connected = true;
        consecutive_failures = 0;

        state.heartbeat = state.heartbeat + 1;
        command_result = 'OK';
        payload = [];

        [ok_cmd, cmd, reason] = validate_ignition_command(raw, cfg, icfg);
        if ~ok_cmd
            command_result = ['REJECTED: ' reason];
        else
            if isempty(last_reset) || cmd.resetSeq ~= last_reset
                state.history = [];
                state.steps = 0;
                last_reset = cmd.resetSeq;
                fprintf('Simulation history reset.\n');
            end
            if isempty(was_running) || was_running ~= cmd.run
                fprintf('Run = %d\n', cmd.run);
                was_running = cmd.run;
            end
            if cmd.run && (toc(t_start) - t_last_tick) >= icfg.tick_interval_s
                try
                    [payload, state, result] = ignition_engine_step(cmd, state, ctx);
                    t_last_tick = toc(t_start);
                    fprintf('t=%6.1f sim-h | %-4s %-20s D=%.2f | HI=%5.1f | AI=%-20s | %s\n', ...
                        result.time_hr, cmd.equipment, cmd.faultType, cmd.severity, ...
                        result.HI, result.predicted_fault_type, result.decision.level);
                catch ME
                    payload = [];
                    command_result = ['ENGINE ERROR: ' regexprep(ME.message, '\s+', ' ')];
                    fprintf(2, '%s\n', command_result);
                end
            end
        end

        if isempty(payload)
            payload = build_telemetry_payload('heartbeat', [], [], state.heartbeat, command_result, icfg);
        else
            payload.commandResult = command_result;
        end

        [ok_post, ~, err_post] = ignition_http('POST', 'telemetry', payload, icfg);
        if ~ok_post
            fprintf(2, 'Telemetry post failed: %s\n', err_post);
        end

        pause(max(poll_s - toc(loop_timer), 0.05));
    end

    if toc(t_start) >= icfg.max_runtime_s
        fprintf('Maximum runtime reached: stopping.\n');
    end
end

% ------------------------------------------------------------------
function local_post_disconnect(icfg)
%LOCAL_POST_DISCONNECT Best-effort disconnect notice on any exit path.
    try
        payload = build_telemetry_payload('disconnect', [], [], 0, 'ADAPTER STOPPED', icfg);
        ignition_http('POST', 'telemetry', payload, icfg);
        fprintf('Disconnect posted; adapter stopped.\n');
    catch
        % Nothing more can be done if the Gateway is already unreachable;
        % the Perspective stale-data indicator covers that case.
    end
end
