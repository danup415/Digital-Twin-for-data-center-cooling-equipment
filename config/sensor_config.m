function SensorConfig = sensor_config()
%SENSOR_CONFIG Virtual sensor specifications for every measurement channel.
%
%   SensorConfig = SENSOR_CONFIG() returns a struct-of-structs, one field
%   per sensor channel, each with sampling frequency, measurement range,
%   noise statistics, bias, and (where meaningful) drift/quantization.
%   These parameters are consumed by src/sensors/*.m (Phase 4) to turn a
%   clean physics-model signal into a realistic virtual-sensor reading.
%
%   Rationale for each Fs choice is documented inline below (§14 of
%   docs/architecture.md requires every sensor parameter to be justified).

    % ---------------------------------------------------------------
    % Accelerometer (vibration channel)
    % Fs = 10 kHz: comfortably captures bearing fault frequencies
    % (BPFO/BPFI/BSF are typically < 1 kHz for this shaft-speed range)
    % and several vibration harmonics with margin below Nyquist.
    % ---------------------------------------------------------------
    SensorConfig.Accelerometer.Fs          = 10000;   % Hz
    SensorConfig.Accelerometer.range_g     = 50;       % +/- g
    SensorConfig.Accelerometer.noise_rms_g = 0.01;     % white-noise floor
    SensorConfig.Accelerometer.bias_g      = 0.002;    % fixed DC bias
    SensorConfig.Accelerometer.quant_bits  = 16;        % ADC resolution

    % ---------------------------------------------------------------
    % Current sensor (MCSA channel)
    % Fs = 5 kHz: fundamental line frequency (50/60 Hz) plus sidebands
    % up to a few hundred Hz needs far less bandwidth than vibration;
    % 5 kHz keeps ample margin while limiting data volume.
    % ---------------------------------------------------------------
    SensorConfig.Current.Fs          = 5000;    % Hz
    SensorConfig.Current.range_A     = 50;       % +/- A
    SensorConfig.Current.noise_rms_A = 0.05;
    SensorConfig.Current.bias_A      = 0.01;
    SensorConfig.Current.quant_bits  = 16;

    % ---------------------------------------------------------------
    % Process sensors — slow thermal/hydraulic states, sampled far
    % below the vibration/current channels since their physical time
    % constants are seconds, not milliseconds.
    % ---------------------------------------------------------------
    SensorConfig.Temperature.Fs        = 1;      % Hz
    SensorConfig.Temperature.noise_rms_C = 0.1;
    SensorConfig.Temperature.bias_C    = 0.05;
    SensorConfig.Temperature.drift_C_per_hr = 0.02;

    SensorConfig.Pressure.Fs        = 10;    % Hz
    SensorConfig.Pressure.noise_rms_kPa = 0.5;
    SensorConfig.Pressure.bias_kPa  = 0.1;

    SensorConfig.Flow.Fs        = 10;    % Hz
    SensorConfig.Flow.noise_rms_Lps = 0.05;
    SensorConfig.Flow.bias_Lps  = 0.01;

    SensorConfig.Speed.Fs        = 100;   % Hz  (tachometer-class channel)
    SensorConfig.Speed.noise_rms_rpm = 1.0;

    SensorConfig.Power.Fs        = 10;    % Hz
    SensorConfig.Power.noise_rms_kW = 0.02;
    SensorConfig.Power.bias_kW  = 0.005;
end
