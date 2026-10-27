function out = pump_model(N_rpm, load_frac, P)
%PUMP_MODEL Reduced-order healthy-pump physics using affinity laws.
%
%   out = PUMP_MODEL(N_rpm, load_frac, P) returns the healthy (fault-free)
%   operating point of the chilled-water pump at shaft speed N_rpm (rpm)
%   and demanded duty-point fraction load_frac (0-1, fraction of the
%   speed-scaled best-efficiency flow actually being drawn by the system).
%
%   Physics (see docs/architecture.md §C, docs/equations.md):
%     Affinity laws:  Q ~ N,  dP ~ N^2,  P_shaft ~ N^3
%     Efficiency: quadratic falloff away from the best-efficiency point
%     (BEP), which by construction occurs at load_frac = 1.
%
%   Inputs:
%     N_rpm     - instantaneous shaft speed (rpm)
%     load_frac - duty-point fraction in [0,1] (1 = operating at the
%                 speed-scaled BEP flow; <1 = throttled/part-load)
%     P         - struct from model_parameters(), field P.Pump used
%
%   Output struct 'out':
%     Q_Lps, dP_kPa, eta, P_shaft_kW, torque_Nm

    if load_frac <= 0
        load_frac = 1e-3;   % avoid divide-by-zero at zero flow
    end

    N_ratio = N_rpm / P.Pump.N_nominal_rpm;

    % Affinity-law-scaled flow and head at this speed, then throttled by
    % load_frac to represent the actual system operating point.
    Q_speed_scaled = P.Pump.Q_nominal_Lps * N_ratio;
    out.Q_Lps      = Q_speed_scaled * load_frac;
    out.dP_kPa     = P.Pump.dP_nominal_kPa * (N_ratio^2) * (0.6 + 0.4*load_frac);

    % Efficiency: quadratic falloff around BEP (load_frac = 1), floored
    % at 30% of nominal so the model never returns non-physical eta<=0.
    bep_falloff_k = 0.30;
    eta_shape = 1 - bep_falloff_k * (load_frac - 1)^2;
    out.eta   = max(P.Pump.eta_nominal * eta_shape, 0.30 * P.Pump.eta_nominal);

    % Shaft power from hydraulic power / efficiency.
    Q_m3ps      = out.Q_Lps / 1000;
    dP_Pa       = out.dP_kPa * 1000;
    hydraulic_kW = (Q_m3ps * dP_Pa) / 1000;
    out.P_shaft_kW = hydraulic_kW / out.eta;

    omega_mech = 2*pi*N_rpm/60;
    if omega_mech > 0
        out.torque_Nm = (out.P_shaft_kW * 1000) / omega_mech;
    else
        out.torque_Nm = 0;
    end
end
