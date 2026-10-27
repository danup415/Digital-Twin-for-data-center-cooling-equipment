function x = generate_vibration_signal(t, f_r, sigparams, bf, AccelCfg)
%GENERATE_VIBRATION_SIGNAL Physically-composed synthetic vibration signal.
%
%   x = GENERATE_VIBRATION_SIGNAL(t, f_r, sigparams, bf, AccelCfg)
%   builds a vibration time series as the superposition (§9):
%     x(t) = fundamental + harmonics
%            + unbalance component (1X, scaled by unbalance_U)
%            + misalignment components (1X+2X, scaled by misalignment_M)
%            + bearing impulse train (scaled by bearing_D, at BPFO)
%            + cavitation broadband noise (scaled by cavitation_C)
%            + sensor noise + bias
%
%   Inputs:
%     t         - time vector (s), uniformly sampled at AccelCfg.Fs
%     f_r       - shaft rotational frequency (Hz)
%     sigparams - struct from apply_pump_fault / apply_fan_fault
%                 (fields not present default to 0 via getfield_default)
%     bf        - struct from bearing_fault_frequencies (needs bf.BPFO)
%     AccelCfg  - SensorConfig.Accelerometer struct
%
%   Output:
%     x - vibration signal in g, same length as t

    U  = getfield_default(sigparams, 'unbalance_U', 0);
    M  = getfield_default(sigparams, 'misalignment_M', 0);
    Db = getfield_default(sigparams, 'bearing_D', 0);
    C  = getfield_default(sigparams, 'cavitation_C', 0);

    % --- Always-present healthy baseline vibration ---
    A_fundamental = 0.05;   % g, baseline 1X amplitude present even when healthy
    x_fundamental = A_fundamental * sin(2*pi*f_r*t);
    x_harmonics   = 0.015*sin(2*pi*2*f_r*t) + 0.008*sin(2*pi*3*f_r*t);

    % --- Unbalance: dominant 1X component, amplitude grows with U ---
    A_unb = 0.6 * U;
    x_unbalance = A_unb * sin(2*pi*f_r*t + pi/6);

    % --- Misalignment: 1X + 2X, 2X often stronger for angular misalignment ---
    A_mis1 = 0.2 * M;
    A_mis2 = 0.35 * M;
    x_misalign = A_mis1*sin(2*pi*f_r*t) + A_mis2*sin(2*pi*2*f_r*t + pi/4);

    % --- Bearing fault: impulse train at BPFO, amplitude/impulsiveness
    %     grows with severity Db ---
    x_bearing = Db * local_impulse_train(t, bf.BPFO, 300);

    % --- Cavitation: broadband high-frequency energy from vapor collapse ---
    if C > 0
        broadband = randn(size(t));
        x_cavitation = 0.4 * C * broadband;
    else
        x_cavitation = zeros(size(t));
    end

    x_clean = x_fundamental + x_harmonics + x_unbalance + x_misalign + ...
              x_bearing + x_cavitation;

    % --- Sensor noise, bias, quantization ---
    noise = AccelCfg.noise_rms_g * randn(size(t));
    x = x_clean + noise + AccelCfg.bias_g;

    if isfield(AccelCfg, 'quant_bits')
        lsb = (2*AccelCfg.range_g) / (2^AccelCfg.quant_bits);
        x = round(x/lsb) * lsb;
    end
end

% ------------------------------------------------------------------
function y = local_impulse_train(t, f_impulse, decay_per_s)
%LOCAL_IMPULSE_TRAIN Repeating exponentially-decaying impulses at f_impulse.
%   Models the repetitive impact excitation of a spalled bearing race.
    if f_impulse <= 0
        y = zeros(size(t));
        return;
    end
    period = 1/f_impulse;
    t_mod = mod(t, period);
    y = exp(-decay_per_s * t_mod) .* (t_mod < 0.6*period);
end

% ------------------------------------------------------------------
function v = getfield_default(s, fname, default_val)
%GETFIELD_DEFAULT Return s.(fname) if present, else default_val.
    if isfield(s, fname)
        v = s.(fname);
    else
        v = default_val;
    end
end
