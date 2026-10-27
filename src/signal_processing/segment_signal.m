function segments = segment_signal(x, Fs, win_len_s, overlap_frac)
%SEGMENT_SIGNAL Split a conditioned signal into overlapping analysis windows.
%
%   segments = SEGMENT_SIGNAL(x, Fs, win_len_s, overlap_frac) applies a
%   Hann window to each segment (§15 windowing requirement) before
%   returning it, ready for FFT-based feature extraction.
%
%   Inputs:
%     x            - conditioned 1-D signal
%     Fs           - sampling frequency (Hz)
%     win_len_s    - window length in seconds
%     overlap_frac - fraction of overlap between consecutive windows, [0,1)
%
%   Output:
%     segments - cell array, each cell a win_len_s*Fs-sample column vector
%                (already Hann-windowed)

    x = x(:);
    win_len = round(win_len_s * Fs);
    step = max(round(win_len * (1 - overlap_frac)), 1);

    n = numel(x);
    starts = 1:step:(n - win_len + 1);
    if isempty(starts)
        starts = 1;
        win_len = n;   % signal shorter than one window: use it whole
    end

    % Hann window computed manually (base MATLAB) so this does not depend
    % on the Signal Processing Toolbox.
    n_idx = (0:win_len-1)';
    w = 0.5 - 0.5*cos(2*pi*n_idx/(win_len-1));

    segments = cell(numel(starts), 1);
    for k = 1:numel(starts)
        idx = starts(k):(starts(k) + win_len - 1);
        segments{k} = x(idx) .* w;
    end
end
