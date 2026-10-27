function [ok, resp, errmsg] = ignition_http(method, endpoint, payload, icfg)
%IGNITION_HTTP Call a Gateway Web Dev endpoint; never throws.
%
%   [ok, resp, errmsg] = IGNITION_HTTP(method, endpoint, payload, icfg)
%
%   method   - 'GET' or 'POST'
%   endpoint - Web Dev resource name, 'commands' or 'telemetry'
%   payload  - struct to send as JSON (POST only; pass [] for GET)
%   icfg     - from ignition_config
%
%   Uses base MATLAB webread/webwrite (no toolbox) with a timeout and the
%   X-Twin-Key header. The Gateway endpoints answer HTTP 200 with
%   {"ok": true/false, "error": ...}; this function converts that into
%   ok / errmsg so callers never parse HTTP details.
%
%   Outputs:
%     ok     - true only if the request completed AND the Gateway said ok
%     resp   - decoded JSON response (struct) when one was received, else []
%     errmsg - '' on success, otherwise a one-line reason (network error,
%              missing API key, or the Gateway's own rejection reason)

    ok = false;
    resp = [];
    errmsg = '';

    if isempty(icfg.api_key)
        errmsg = ['API key not set (environment variable COOLING_TWIN_API_KEY ', ...
                  'or src/ignition/ignition_secret.txt)'];
        return;
    end
    if ~any(strcmpi(method, {'GET', 'POST'}))
        errmsg = ['unsupported method: ' method];
        return;
    end

    url = [icfg.webdev_root endpoint];
    opts = weboptions('Timeout', icfg.http_timeout_s, ...
        'HeaderFields', {icfg.api_key_header, icfg.api_key});

    try
        if strcmpi(method, 'GET')
            resp = webread(url, opts);
        else
            opts.MediaType = 'application/json';
            resp = webwrite(url, payload, opts);
        end
    catch ME
        errmsg = regexprep(ME.message, '\s+', ' ');
        resp = [];
        return;
    end

    if isstruct(resp) && isfield(resp, 'ok')
        ok = logical(resp.ok);
        if ~ok
            if isfield(resp, 'error')
                errmsg = ['Gateway rejected request: ' char(string(resp.error))];
            else
                errmsg = 'Gateway rejected request';
            end
        end
    else
        errmsg = 'unexpected response from Gateway (not a JSON object with an ok field)';
    end
end
