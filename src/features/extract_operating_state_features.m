function state = extract_operating_state_features(N_rpm, load_frac, ambient_C, cfg)
%EXTRACT_OPERATING_STATE_FEATURES Bucket the operating condition (§19).
%
%   state = EXTRACT_OPERATING_STATE_FEATURES(N_rpm, load_frac, ambient_C,
%   cfg) produces both the raw operating values and discretized bins, so
%   the ML fusion model and the adaptive-threshold system (§20) can
%   distinguish "high vibration because of high load" from "high
%   vibration because of a developing fault".
%
%   Inputs:
%     N_rpm, load_frac, ambient_C - instantaneous operating point
%     cfg - struct from project_config() (uses cfg.operating ranges)
%
%   Output struct 'state':
%     N_rpm, load_frac, ambient_C (raw, passed through)
%     speed_bin, load_bin, ambient_bin (integers 1-3: Low/Med/High)

    state.N_rpm     = N_rpm;
    state.load_frac = load_frac;
    state.ambient_C = ambient_C;

    state.speed_bin   = local_bin(N_rpm,    cfg.operating.speed_rpm_range);
    state.load_bin    = local_bin(load_frac*100, cfg.operating.load_pct_range);
    state.ambient_bin = local_bin(ambient_C, cfg.operating.ambient_C_range);
end

% ------------------------------------------------------------------
function b = local_bin(value, range2)
%LOCAL_BIN Map value into 3 equal-width bins spanning range2 = [lo hi].
    lo = range2(1); hi = range2(2);
    edges = linspace(lo, hi, 4);   % 3 bins => 4 edges
    if value <= edges(2)
        b = 1;       % Low
    elseif value <= edges(3)
        b = 2;       % Medium
    else
        b = 3;       % High
    end
end
