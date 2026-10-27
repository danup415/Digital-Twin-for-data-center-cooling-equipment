function proc = generate_process_sensor_readings(degraded, N_rpm, ambient_C, equipment, SensorConfig)
%GENERATE_PROCESS_SENSOR_READINGS Slow process-channel virtual sensors.
%
%   proc = GENERATE_PROCESS_SENSOR_READINGS(degraded, N_rpm, ambient_C,
%   equipment, SensorConfig) applies per-channel noise/bias (§14) to the
%   clean physics/fault state to produce the process-sensor readings used
%   alongside vibration/MCSA for feature fusion and the thermal twin.
%
%   Inputs:
%     degraded  - struct from apply_pump_fault / apply_fan_fault (has
%                 Q_Lps or Q_m3ps, dP_kPa or dP_Pa, P_shaft_kW)
%     N_rpm     - instantaneous shaft speed
%     ambient_C - ambient temperature (C)
%     equipment - 'Pump' or 'Fan' (selects the correct field names)
%     SensorConfig - struct from sensor_config()
%
%   Output struct 'proc': temperature_C, pressure, flow, speed_rpm, power_kW
%   (pressure/flow units follow the equipment: kPa/Lps for Pump, Pa/m3ps for Fan)

    if strcmp(equipment, 'Pump')
        flow_clean = degraded.Q_Lps;
        press_clean = degraded.dP_kPa;
    elseif strcmp(equipment, 'Fan')
        flow_clean = degraded.Q_m3ps;
        press_clean = degraded.dP_Pa;
    else
        error('generate_process_sensor_readings:unknownEquipment', ...
              'equipment must be ''Pump'' or ''Fan''');
    end

    % Casing/bearing temperature rises modestly with shaft power as a
    % simple proxy for frictional/electrical losses becoming heat.
    temp_rise_per_kW = 0.8;
    proc.temperature_C = ambient_C + temp_rise_per_kW * degraded.P_shaft_kW ...
        + SensorConfig.Temperature.noise_rms_C * randn() + SensorConfig.Temperature.bias_C;

    proc.pressure = press_clean + SensorConfig.Pressure.noise_rms_kPa * randn() ...
        + SensorConfig.Pressure.bias_kPa;

    proc.flow = flow_clean + SensorConfig.Flow.noise_rms_Lps * randn() ...
        + SensorConfig.Flow.bias_Lps;

    proc.speed_rpm = N_rpm + SensorConfig.Speed.noise_rms_rpm * randn();

    proc.power_kW = degraded.P_shaft_kW + SensorConfig.Power.noise_rms_kW * randn() ...
        + SensorConfig.Power.bias_kW;
end
