function i_cond = condition_current_signal(i_sig, Fs, cfg)
%CONDITION_CURRENT_SIGNAL Detrend + low-pass-filter a raw MCSA current signal.
%
%   i_cond = CONDITION_CURRENT_SIGNAL(i_sig, Fs, cfg) applies (§15):
%     1. DC removal
%     2. Low-pass filtering below the anti-aliasing limit, wide enough to
%        preserve harmonics and sidebands used by MCSA feature extraction.
%
%   Same toolbox-availability fallback pattern as CONDITION_VIBRATION_SIGNAL.
%
%   Inputs:  i_sig, Fs, cfg (optional, struct from project_config())
%   Output:  i_cond - conditioned signal, same length as i_sig

    if nargin < 3 || isempty(cfg)
        have_signal_toolbox = ~isempty(ver('signal'));
    else
        have_signal_toolbox = cfg.toolbox.signal_processing;
    end

    i_sig = i_sig - mean(i_sig);

    f_cut = 0.45 * Fs;

    if have_signal_toolbox
        [b, a] = butter(4, f_cut/(Fs/2), 'low');
        i_cond = filtfilt(b, a, i_sig);
    else
        win_lp = max(round(Fs / f_cut), 1);
        i_cond = movmean(i_sig, win_lp);
    end
end
