function stale = ignition_is_stale(ts_utc, stale_after_s, now_utc)
%IGNITION_IS_STALE True if a telemetry timestamp is too old to be live data.
%
%   stale = IGNITION_IS_STALE(ts_utc, stale_after_s)
%   stale = IGNITION_IS_STALE(ts_utc, stale_after_s, now_utc)
%
%   ts_utc        - 'yyyy-MM-ddTHH:mm:ss.SSSZ' text, as written into
%                   payload.tsUtc by build_telemetry_payload.m
%   stale_after_s - maximum acceptable age in seconds
%   now_utc       - optional datetime (UTC) to compare against; defaults to
%                   the current UTC time (the argument exists so tests can
%                   be deterministic)
%
%   A missing, empty or unparseable timestamp counts as STALE: when in
%   doubt, data is never presented as live.
%
%   Note: the Perspective side performs the equivalent check with an
%   expression on Meta/LastUpdate (see docs/IGNITION_DIGITAL_TWIN_SETUP.md);
%   this function is the MATLAB-side counterpart used by the adapter tests.

    if nargin < 3
        now_utc = datetime('now', 'TimeZone', 'UTC');
    end

    stale = true;
    if ~(ischar(ts_utc) || (isstring(ts_utc) && isscalar(ts_utc))) || strlength(string(ts_utc)) == 0
        return;
    end
    try
        t = datetime(char(ts_utc), 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', ...
            'TimeZone', 'UTC');
    catch
        return;
    end
    if isnat(t)
        return;
    end
    age_s = seconds(now_utc - t);
    stale = age_s > stale_after_s || age_s < -stale_after_s;   % far-future stamps are suspect too
end
