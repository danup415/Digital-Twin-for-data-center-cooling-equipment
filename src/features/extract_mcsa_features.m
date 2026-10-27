function feat = extract_mcsa_features(i_sig, Fs, f_line, f_r)
%EXTRACT_MCSA_FEATURES Motor-current-signature-analysis feature set (§17).
%
%   feat = EXTRACT_MCSA_FEATURES(i_sig, Fs, f_line, f_r) computes:
%     rms, peak, crest
%     fundamental_amp (at f_line)
%     harmonic3_amp, harmonic5_amp
%     THD  = sqrt(sum(harmonics^2)) / fundamental
%     sideband_amp (at f_line +/- f_r, averaged)
%     spectral_energy
%
%   Physical interpretation: the fundamental carries the supply
%   frequency; harmonics reflect supply/converter non-idealities;
%   sidebands at f_line +/- k*f_r are the MCSA signature of a periodic
%   mechanical fault (unbalance, bearing defect, misalignment) modulating
%   motor torque/slip at the mechanical fault frequency.
%
%   Inputs:
%     i_sig  - conditioned, windowed current segment
%     Fs     - sampling frequency (Hz)
%     f_line - supply/line frequency (Hz)
%     f_r    - rotor mechanical frequency (Hz)
%
%   Output struct 'feat'

    i_sig = i_sig(:);
    n = numel(i_sig);

    feat.rms   = sqrt(mean(i_sig.^2));
    feat.peak  = max(abs(i_sig));
    feat.crest = feat.peak / max(feat.rms, eps);

    X = abs(fft(i_sig));
    X = X(1:floor(n/2)+1);
    f = (0:floor(n/2))' * (Fs/n);

    feat.fundamental_amp = local_amp_near(f, X, f_line, 2);
    feat.harmonic3_amp   = local_amp_near(f, X, 3*f_line, 2);
    feat.harmonic5_amp   = local_amp_near(f, X, 5*f_line, 2);

    harmonics_energy = feat.harmonic3_amp^2 + feat.harmonic5_amp^2;
    feat.THD = sqrt(harmonics_energy) / max(feat.fundamental_amp, eps);

    sb_lower = local_amp_near(f, X, f_line - f_r, 1);
    sb_upper = local_amp_near(f, X, f_line + f_r, 1);
    feat.sideband_amp = mean([sb_lower, sb_upper]);

    feat.spectral_energy = sum(X.^2);
end

% ------------------------------------------------------------------
function a = local_amp_near(f, X, target_Hz, half_width_Hz)
    if target_Hz <= 0
        a = 0;
        return;
    end
    band = (f >= target_Hz - half_width_Hz) & (f <= target_Hz + half_width_Hz);
    if any(band)
        a = max(X(band));
    else
        a = 0;
    end
end
