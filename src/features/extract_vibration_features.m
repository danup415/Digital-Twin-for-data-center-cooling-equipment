function feat = extract_vibration_features(x, Fs, bf)
%EXTRACT_VIBRATION_FEATURES Time/frequency/bearing-specific vibration features.
%
%   feat = EXTRACT_VIBRATION_FEATURES(x, Fs, bf) computes the feature set
%   required by §16 of docs/architecture.md, on a single conditioned,
%   windowed vibration segment.
%
%   Inputs:
%     x  - conditioned, windowed vibration segment (column vector)
%     Fs - sampling frequency (Hz)
%     bf - struct from bearing_fault_frequencies (BPFO, BPFI, BSF)
%
%   Output struct 'feat' (all scalar, fixed field set regardless of fault):
%     Time-domain:  rms, mean_abs, std, peak, p2p, crest, kurtosis,
%                   skewness, shape_factor, impulse_factor
%     Frequency-domain: dom_freq_Hz, dom_amp, spectral_centroid_Hz,
%                   spectral_bandwidth_Hz, spectral_energy
%     Bearing-specific: bpfo_energy, bpfi_energy, bsf_energy

    x = x(:);
    n = numel(x);

    % ---------------- Time domain ----------------
    feat.rms      = sqrt(mean(x.^2));
    feat.mean_abs = mean(abs(x));
    feat.std      = std(x);
    feat.peak     = max(abs(x));
    feat.p2p      = max(x) - min(x);
    feat.crest    = feat.peak / max(feat.rms, eps);
    feat.kurtosis = local_kurtosis(x);
    feat.skewness = local_skewness(x);
    feat.shape_factor   = feat.rms / max(feat.mean_abs, eps);
    feat.impulse_factor = feat.peak / max(feat.mean_abs, eps);

    % ---------------- Frequency domain ----------------
    X = abs(fft(x));
    X = X(1:floor(n/2)+1);
    f = (0:floor(n/2))' * (Fs/n);

    [feat.dom_amp, idx] = max(X(2:end));   % skip DC bin
    feat.dom_freq_Hz = f(idx+1);

    P = X.^2;
    P_sum = sum(P) + eps;
    feat.spectral_centroid_Hz  = sum(f .* P) / P_sum;
    feat.spectral_bandwidth_Hz = sqrt(sum(((f - feat.spectral_centroid_Hz).^2) .* P) / P_sum);
    feat.spectral_energy       = sum(P);

    % ---------------- Bearing-specific band energy ----------------
    feat.bpfo_energy = local_band_energy(f, P, bf.BPFO, 0.05*bf.BPFO + 1);
    feat.bpfi_energy = local_band_energy(f, P, bf.BPFI, 0.05*bf.BPFI + 1);
    feat.bsf_energy  = local_band_energy(f, P, bf.BSF,  0.05*bf.BSF  + 1);
end

% ------------------------------------------------------------------
function e = local_band_energy(f, P, center_Hz, half_width_Hz)
    if center_Hz <= 0
        e = 0;
        return;
    end
    band = (f >= center_Hz - half_width_Hz) & (f <= center_Hz + half_width_Hz);
    e = sum(P(band));
end

% ------------------------------------------------------------------
function k = local_kurtosis(x)
    mu = mean(x); s = std(x);
    if s < eps
        k = 0;
    else
        k = mean((x-mu).^4) / (s^4);
    end
end

% ------------------------------------------------------------------
function sk = local_skewness(x)
    mu = mean(x); s = std(x);
    if s < eps
        sk = 0;
    else
        sk = mean((x-mu).^3) / (s^3);
    end
end
