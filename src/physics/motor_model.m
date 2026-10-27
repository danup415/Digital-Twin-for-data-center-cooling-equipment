function out = motor_model(N_rpm, load_torque_Nm, MotorP)
%MOTOR_MODEL Simplified induction-motor equivalent for a pump/fan drive.
%
%   out = MOTOR_MODEL(N_rpm, load_torque_Nm, MotorP) computes the
%   steady-state electrical operating point needed to deliver
%   load_torque_Nm at shaft speed N_rpm, using a constant assumed motor
%   efficiency and power factor (documented simplification — this is not
%   a full dq-axis induction-motor model, it exists to give MCSA-relevant
%   quantities: slip, line current magnitude, and the rotor mechanical
%   frequency used for sideband placement).
%
%   Inputs:
%     N_rpm           - shaft speed (rpm)
%     load_torque_Nm  - mechanical torque demanded by the driven pump/fan
%     MotorP          - P.Motor sub-struct from model_parameters()
%
%   Output struct 'out':
%     f_line_Hz, f_r_Hz (rotor mechanical frequency), N_sync_rpm, slip,
%     P_mech_kW, P_elec_kW, I_rms_A

    poles = 2 * MotorP.pole_pairs;
    N_sync_rpm = 120 * MotorP.line_freq_Hz / poles;

    out.f_line_Hz  = MotorP.line_freq_Hz;
    out.N_sync_rpm = N_sync_rpm;
    out.f_r_Hz     = N_rpm / 60;                      % rotor mechanical frequency
    out.slip       = max((N_sync_rpm - N_rpm) / N_sync_rpm, 0);

    omega_mech = 2*pi*N_rpm/60;
    out.P_mech_kW = max(load_torque_Nm * omega_mech / 1000, 0);

    % Constant assumed motor efficiency/power-factor simplification.
    motor_eta = 0.90;
    power_factor = 0.85;
    out.P_elec_kW = out.P_mech_kW / motor_eta;

    % Three-phase line current from electrical power.
    S_kVA = out.P_elec_kW / power_factor;
    out.I_rms_A = (S_kVA * 1000) / (sqrt(3) * MotorP.rated_voltage_V);
end
