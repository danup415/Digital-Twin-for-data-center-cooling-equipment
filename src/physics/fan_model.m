function out = fan_model(N_rpm, load_frac, P)
%FAN_MODEL Reduced-order healthy-fan physics using fan affinity laws.
%
%   out = FAN_MODEL(N_rpm, load_frac, P) mirrors PUMP_MODEL but for the
%   CRAC fan: Q ~ N, dP ~ N^2, P_shaft ~ N^3 (§7), with the same
%   quadratic-BEP efficiency shape.
%
%   Inputs:
%     N_rpm     - instantaneous fan speed (rpm)
%     load_frac - duty-point fraction in [0,1]
%     P         - struct from model_parameters(), field P.Fan used
%
%   Output struct 'out': Q_m3ps, dP_Pa, eta, P_shaft_kW, torque_Nm

    if load_frac <= 0
        load_frac = 1e-3;
    end

    N_ratio = N_rpm / P.Fan.N_nominal_rpm;

    Q_speed_scaled = P.Fan.Q_nominal_m3ps * N_ratio;
    out.Q_m3ps     = Q_speed_scaled * load_frac;
    out.dP_Pa      = P.Fan.dP_nominal_Pa * (N_ratio^2) * (0.6 + 0.4*load_frac);

    bep_falloff_k = 0.30;
    eta_shape = 1 - bep_falloff_k * (load_frac - 1)^2;
    out.eta   = max(P.Fan.eta_nominal * eta_shape, 0.30 * P.Fan.eta_nominal);

    hydraulic_kW   = (out.Q_m3ps * out.dP_Pa) / 1000;
    out.P_shaft_kW = hydraulic_kW / out.eta;

    omega_mech = 2*pi*N_rpm/60;
    if omega_mech > 0
        out.torque_Nm = (out.P_shaft_kW * 1000) / omega_mech;
    else
        out.torque_Nm = 0;
    end
end
