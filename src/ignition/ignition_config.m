function icfg = ignition_config()
%IGNITION_CONFIG Settings for the MATLAB <-> Ignition adapter.
%
%   icfg = IGNITION_CONFIG() returns a struct with the Gateway endpoints,
%   API key, pacing limits and stop-file location. It never errors if the
%   API key is missing (offline unit tests must still work); ignition_http
%   refuses to talk to the Gateway without a key instead.
%
%   API KEY: set ONE of
%     - environment variable COOLING_TWIN_API_KEY (setenv in MATLAB, or a
%       Windows user variable), or
%     - a one-line text file src/ignition/ignition_secret.txt
%   It must equal API_KEY inside ignition_project/webdev/commands.py and
%   telemetry.py. Never commit or share the key.
%
%   Time: a "tick" advances the simulation by elapsed_hr_per_tick SIMULATED
%   hours and happens at most once per tick_interval_s of WALL-CLOCK time.
%
%   Output fields: base_url, project, webdev_root, api_key_header, api_key,
%   http_timeout_s, poll_interval_s (>= 0.25), tick_interval_s,
%   elapsed_hr_per_tick, stale_after_s, max_runtime_s, stop_file,
%   it_load_range_kW, feature_set, schema_version

    cfg = project_config();

    icfg.base_url = 'http://localhost:8088';
    icfg.project = 'CoolingDigitalTwin';
    icfg.webdev_root = [icfg.base_url '/system/webdev/' icfg.project '/'];
    icfg.api_key_header = 'X-Twin-Key';
    icfg.api_key = local_read_key(cfg.root_dir);

    icfg.http_timeout_s = 5;
    icfg.poll_interval_s = 0.5;                  % run_ignition_adapter clamps this to >= 0.25 s
    icfg.tick_interval_s = 2;                    % wall-clock seconds between simulation ticks
    icfg.elapsed_hr_per_tick = 1;                % simulated hours advanced per tick
    icfg.stale_after_s = 10;
    icfg.max_runtime_s = 1800;                   % adapter stops itself after 30 min
    icfg.stop_file = fullfile(cfg.root_dir, 'src', 'ignition', 'STOP_ADAPTER');

    % Design bound for the IT-load control (project config only defines a
    % nominal value, P.Thermal.IT_load_kW_nominal).
    icfg.it_load_range_kW = [10, 100];
    icfg.feature_set = 'fusion_state';
    icfg.schema_version = 1;
end

% ------------------------------------------------------------------
function key = local_read_key(root_dir)
    key = strtrim(getenv('COOLING_TWIN_API_KEY'));
    if ~isempty(key)
        return;
    end
    key_file = fullfile(root_dir, 'src', 'ignition', 'ignition_secret.txt');
    if isfile(key_file)
        key = strtrim(fileread(key_file));
    else
        key = '';
    end
end
