function traj = simulate_degradation_trajectory(equipment, fault_type, duration_hr, n_steps, load_frac, cfg, P, T_thresh)
%SIMULATE_DEGRADATION_TRAJECTORY Shared trajectory simulator for Experiments 4/5/9.
%
%   traj = SIMULATE_DEGRADATION_TRAJECTORY(equipment, fault_type,
%   duration_hr, n_steps, load_frac, cfg, P, T_thresh) ramps severity D
%   linearly from 0 to 1.2*D_critical over duration_hr, and at each step
%   computes Health Index, a trend-extrapolated RUL, the thermal-twin
%   server-inlet temperature/margin, and the maintenance decision level —
%   the same chain used in experiments/experiment_00_integration_demo,
%   factored out so Experiments 4/5/9 don't each re-implement it.
%
%   Inputs:
%     equipment, fault_type - as in cfg.faults.(equipment)
%     duration_hr - total simulated duration (hours)
%     n_steps      - number of samples along the trajectory
%     load_frac    - constant duty-point fraction for this run
%     cfg, P, T_thresh - project_config()/model_parameters()/get_maintenance_thresholds()
%
%   Output:
%     traj - table: time_hr, D, HI, RUL_hr, T_server_inlet_C,
%            thermal_margin_C, decision_level

    time_hr = linspace(0, duration_hr, n_steps)';
    % Ramp all the way to D=1 (true equipment failure), not just past the
    % Health-Index "critical" boundary — a primary-path fault needs to
    % reach genuine failure severity before it can threaten the thermal
    % safety threshold with the calibrated coefficients in
    % cooling_effectiveness_from_degradation.m, and this is the
    % "run it to failure" demonstration §50 of the original brief asks for.
    D_vec = linspace(0, 1, n_steps)';

    HI_vec = compute_health_index(D_vec, P.Health);

    ambient_C = P.Thermal.ambient_C_nominal;
    IT_load_kW_vec = P.Thermal.IT_load_kW_nominal * ones(n_steps, 1);
    ambient_C_vec  = ambient_C * ones(n_steps, 1);

    effectiveness_vec = zeros(n_steps, 1);
    for k = 1:n_steps
        effectiveness_vec(k) = cooling_effectiveness_from_degradation(equipment, fault_type, D_vec(k));
    end

    time_s = time_hr * 3600;
    thermal_traj = thermal_digital_twin(time_s, IT_load_kW_vec, ambient_C_vec, effectiveness_vec, P.Thermal);

    RUL_vec = nan(n_steps, 1);
    decision_level = cell(n_steps, 1);
    rul_window = 5;

    for k = 1:n_steps
        w_start = max(1, k - rul_window + 1);
        rul_out = estimate_rul(time_hr(w_start:k), HI_vec(w_start:k), P.Health);
        RUL_vec(k) = rul_out.RUL;

        decision = maintenance_decision_engine(NaN, D_vec(k), HI_vec(k), RUL_vec(k), ...
            thermal_traj.thermal_margin_C(k), T_thresh);
        decision_level{k} = decision.level;
    end

    traj = table(time_hr, D_vec, HI_vec, RUL_vec, thermal_traj.T_server_inlet_C, ...
        thermal_traj.thermal_margin_C, string(decision_level), ...
        'VariableNames', {'time_hr','D','HI','RUL_hr','T_server_inlet_C','thermal_margin_C','decision_level'});
end
