function x_cond = condition_vibration_signal(x, Fs, cfg)
%CONDITION_VIBRATION_SIGNAL Detrend + bandpass-filter a raw vibration signal.
%
%   x_cond = CONDITION_VIBRATION_SIGNAL(x, Fs, cfg) applies (§15):
%     1. DC removal / detrend
%     2. Bandpass filtering to the diagnostically useful band (removes
%        sub-1-Hz mounting drift and anti-aliases above the Nyquist-safe
%        analysis band) — WITHOUT removing the fault signature, so the
%        band is kept wide (default 2 Hz to 0.45*Fs).
%
%   If the Signal Processing Toolbox is available, a proper Butterworth
%   bandpass with zero-phase filtfilt is used; otherwise a fallback
%   moving-average high-pass + simple low-pass (§M fallback) is applied.
%
%   Inputs:
%     x   - raw vibration signal
%     Fs  - sampling frequency (Hz)
%     cfg - struct from project_config() (uses cfg.toolbox.signal_processing);
%           optional, if omitted the toolbox is auto-detected.
%
%   Output:
%     x_cond - conditioned signal, same length as x

    if nargin < 3 || isempty(cfg)
        have_signal_toolbox = ~isempty(ver('signal'));
    else
        have_signal_toolbox = cfg.toolbox.signal_processing;
    end

    x = x - mean(x);                 % DC removal
    x = detrend(x, 'linear');        % remove slow drift

    f_low  = 2;                      % Hz
    f_high = 0.45 * Fs;              % keep clear of Nyquist

    if have_signal_toolbox
        [b, a] = butter(4, [f_low f_high]/(Fs/2), 'bandpass');
        x_cond = filtfilt(b, a, x);
    else
        % Fallback: simple high-pass via subtracting a long moving average,
        % then a short moving-average low-pass (base MATLAB only).
        win_hp = max(round(Fs / f_low), 3);
        x_hp = x - movmean(x, win_hp);
        win_lp = max(round(Fs / f_high), 1);
        x_cond = movmean(x_hp, win_lp);
    end
end
