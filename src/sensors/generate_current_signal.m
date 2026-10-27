function i_sig = generate_current_signal(t, MotorOut, sigparams, CurrentCfg)
%GENERATE_CURRENT_SIGNAL Physically-composed synthetic MCSA current signal.
%
%   i_sig = GENERATE_CURRENT_SIGNAL(t, MotorOut, sigparams, CurrentCfg)
%   builds a stator current time series (§8):
%     i(t) = fundamental at f_line
%            + low-order harmonics (supply/converter non-idealities)
%            + fault-dependent sidebands at f_line +/- k*f_r
%              (mechanical-fault load modulation, k = 1, 2)
%            + sensor noise + bias
%
%   The sideband mechanism used here is the standard MCSA principle that
%   a periodic mechanical load disturbance (unbalance, a bearing defect,
%   misalignment) modulates the motor's torque/slip at the mechanical
%   fault frequency, which appears as amplitude modulation sidebands on
%   the fundamental stator current.
%
%   Inputs:
%     t          - time vector (s), sampled at CurrentCfg.Fs
%     MotorOut   - struct from motor_model (needs f_line_Hz, f_r_Hz, I_rms_A)
%     sigparams  - struct from apply_pump_fault / apply_fan_fault
%     CurrentCfg - SensorConfig.Current struct
%
%   Output:
%     i_sig - current signal in A, same length as t

    U  = local_getfield(sigparams, 'unbalance_U', 0);
    M  = local_getfield(sigparams, 'misalignment_M', 0);
    Db = local_getfield(sigparams, 'bearing_D', 0);

    f_line = MotorOut.f_line_Hz;
    f_r    = MotorOut.f_r_Hz;
    I0     = MotorOut.I_rms_A * sqrt(2);   % peak of fundamental

    i_fundamental = I0 * sin(2*pi*f_line*t);
    i_harmonics   = 0.03*I0*sin(2*pi*3*f_line*t) + 0.015*I0*sin(2*pi*5*f_line*t);

    % Combined mechanical-fault severity drives sideband depth.
    fault_severity_total = U + M + Db;
    if fault_severity_total > 0
        modulation_depth = min(0.25 * fault_severity_total, 0.9);
        modulator = 1 + modulation_depth * sin(2*pi*f_r*t);
        i_sidebands = (i_fundamental .* modulator) - i_fundamental;  % isolate sideband energy
    else
        i_sidebands = zeros(size(t));
    end

    i_clean = i_fundamental + i_harmonics + i_sidebands;

    noise = CurrentCfg.noise_rms_A * randn(size(t));
    i_sig = i_clean + noise + CurrentCfg.bias_A;

    if isfield(CurrentCfg, 'quant_bits')
        lsb = (2*CurrentCfg.range_A) / (2^CurrentCfg.quant_bits);
        i_sig = round(i_sig/lsb) * lsb;
    end
end

% ------------------------------------------------------------------
function v = local_getfield(s, fname, default_val)
    if isfield(s, fname)
        v = s.(fname);
    else
        v = default_val;
    end
end
