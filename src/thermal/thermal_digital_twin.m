function traj = thermal_digital_twin(time_vec, IT_load_kW_vec, ambient_C_vec, effectiveness_vec, ThermalP)
%THERMAL_DIGITAL_TWIN Lumped RC thermal-zone model of a data-hall (§26-27).
%
%   traj = THERMAL_DIGITAL_TWIN(time_vec, IT_load_kW_vec, ambient_C_vec,
%   effectiveness_vec, ThermalP) integrates a first-order energy balance:
%
%     C_th * dT/dt = Q_IT - Q_cooling_effective
%     Q_cooling_effective = effectiveness(t) * Q_cooling_nominal(t)
%     Q_cooling_nominal(t) ~ proportional to (T(t) - T_setpoint) / tau
%
%   i.e. a first-order RC network (C_th = thermal_mass_kJ_per_C, tau =
%   cooling_time_constant_s) whose effective cooling gain is scaled down
%   by the equipment-degradation-driven 'effectiveness' factor — this is
%   the mechanism that lets a mechanical fault produce a predictable rise
%   in server-inlet temperature (§28).
%
%   INTEGRATION METHOD: this ODE is linear and time-invariant within each
%   interval (Q_IT, ambient, effectiveness held constant over the
%   interval), so it is integrated with its EXACT closed-form solution
%   rather than forward Euler:
%       T(t) = T_ss + (T0 - T_ss)*exp(-rate*dt),  rate = effectiveness/tau
%       T_ss = ambient + Q_IT*tau / (effectiveness*C_th)   (steady state)
%   Forward Euler was tried first and is numerically UNSTABLE here: the
%   trajectories this project simulates use timesteps (hours) many times
%   longer than tau (seconds), so Euler's stability condition
%   (rate*dt < 2) is badly violated and the temperature blows up to
%   astronomical, oscillating-sign values within a few steps. The exact
%   exponential update is unconditionally stable for any dt >= 0 and is
%   the standard correct approach for a linear first-order system,
%   independent of how coarse the caller's timestep is.
%
%   Inputs:
%     time_vec          - time stamps (s), uniform step assumed
%     IT_load_kW_vec     - IT heat load at each time stamp (kW)
%     ambient_C_vec      - ambient/return-air reference temperature (C)
%     effectiveness_vec  - cooling-effectiveness multiplier at each time
%                           stamp, in (0,1] (from
%                           cooling_effectiveness_from_degradation)
%     ThermalP            - P.Thermal sub-struct from model_parameters()
%
%   Output struct 'traj':
%     time, T_server_inlet_C, thermal_margin_C (T_safe - T_server_inlet)

    n = numel(time_vec);
    T = zeros(n, 1);
    T(1) = ambient_C_vec(1);   % start at ambient (steady, healthy assumption)

    C_th = ThermalP.thermal_mass_kJ_per_C;
    tau  = ThermalP.cooling_time_constant_s;

    for k = 2:n
        dt = time_vec(k) - time_vec(k-1);

        Q_IT_kW = IT_load_kW_vec(k-1);
        eff     = max(effectiveness_vec(k-1), 1e-3);   % guard against div-by-zero
        Tamb    = ambient_C_vec(k-1);

        rate = eff / tau;                              % 1/s
        T_ss = Tamb + (Q_IT_kW * tau) / (eff * C_th);   % steady-state temperature

        T(k) = T_ss + (T(k-1) - T_ss) * exp(-rate * dt);
    end

    traj.time = time_vec(:);
    traj.T_server_inlet_C = T;
    traj.thermal_margin_C = ThermalP.T_safe_C - T;
end
