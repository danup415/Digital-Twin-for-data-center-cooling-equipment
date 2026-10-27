function results = run_experiment_09(cfg, P)
%RUN_EXPERIMENT_09 Reactive vs predictive maintenance comparison (§35 Exp. 9, §30).
%
%   results = RUN_EXPERIMENT_09(cfg, P) runs the same fan-bearing
%   degradation trajectory as Experiment 4/the integration demo, then
%   simulates two intervention policies on top of the SAME underlying
%   thermal-twin physics (§30):
%
%     MODE A - Reactive:  cooling effectiveness is only restored to 1.0
%                         (maintenance performed) at the first time step
%                         where the thermal margin is actually violated
%                         (thermal_margin_C <= 0).
%     MODE B - Predictive: cooling effectiveness is restored at the first
%                         time step where the maintenance decision engine
%                         reaches WARNING or worse — i.e., BEFORE the
%                         thermal threshold is crossed.
%
%   Compared metrics (§30): peak server-inlet temperature, whether the
%   safety threshold was ever violated, and the warning lead time.
%
%   Output:
%     results - table with one row per mode, saved to
%               results/tables/exp09_reactive_vs_predictive.csv

    T_thresh = get_maintenance_thresholds();
    equipment = 'Fan';
    fault_type = 'EfficiencyDegradation';   % primary fan->thermal path (§28) —
    % BearingDegradation is a deliberately "quiet"/thermally-mild fault by
    % design (see docs/architecture.md §D), so it never threatens the
    % thermal threshold; EfficiencyDegradation is the fault this
    % experiment needs to actually demonstrate a reactive-vs-predictive
    % thermal consequence.
    duration_hr = 500;
    n_steps = 100;

    time_hr = linspace(0, duration_hr, n_steps)';
    % Ramp to D=1 (true failure) — see the rationale comment in
    % src/thermal/simulate_degradation_trajectory.m.
    D_vec = linspace(0, 1, n_steps)';
    HI_vec = compute_health_index(D_vec, P.Health);

    ambient_C = P.Thermal.ambient_C_nominal;
    IT_load_kW_vec = P.Thermal.IT_load_kW_nominal * ones(n_steps, 1);
    ambient_C_vec  = ambient_C * ones(n_steps, 1);

    effectiveness_baseline = zeros(n_steps, 1);
    for k = 1:n_steps
        effectiveness_baseline(k) = cooling_effectiveness_from_degradation(equipment, fault_type, D_vec(k));
    end

    time_s = time_hr * 3600;

    % ---- No-intervention baseline run, to find the decision/violation timing ----
    baseline_traj = thermal_digital_twin(time_s, IT_load_kW_vec, ambient_C_vec, effectiveness_baseline, P.Thermal);

    RUL_vec = nan(n_steps, 1);
    decision_level = strings(n_steps, 1);
    rul_window = 5;
    for k = 1:n_steps
        w_start = max(1, k - rul_window + 1);
        rul_out = estimate_rul(time_hr(w_start:k), HI_vec(w_start:k), P.Health);
        RUL_vec(k) = rul_out.RUL;
        d = maintenance_decision_engine(NaN, D_vec(k), HI_vec(k), RUL_vec(k), ...
            baseline_traj.thermal_margin_C(k), T_thresh);
        decision_level(k) = string(d.level);
    end

    reactive_idx   = find(baseline_traj.thermal_margin_C <= 0, 1, 'first');
    predictive_idx = find(decision_level ~= "NORMAL" & decision_level ~= "MONITOR", 1, 'first');

    % ---- Simulate each mode: effectiveness snaps back to 1.0 from the
    % intervention index onward ----
    reactive_eff = local_apply_intervention(effectiveness_baseline, reactive_idx);
    predictive_eff = local_apply_intervention(effectiveness_baseline, predictive_idx);

    reactive_traj   = thermal_digital_twin(time_s, IT_load_kW_vec, ambient_C_vec, reactive_eff, P.Thermal);
    predictive_traj = thermal_digital_twin(time_s, IT_load_kW_vec, ambient_C_vec, predictive_eff, P.Thermal);

    mode = ["No intervention"; "Reactive"; "Predictive"];
    peak_T = [max(baseline_traj.T_server_inlet_C); max(reactive_traj.T_server_inlet_C); max(predictive_traj.T_server_inlet_C)];
    threshold_violated = peak_T > P.Thermal.T_safe_C;
    intervention_time_hr = [NaN; local_time_or_nan(time_hr, reactive_idx); local_time_or_nan(time_hr, predictive_idx)];

    if ~isempty(reactive_idx) && ~isempty(predictive_idx)
        lead_time_hr = time_hr(reactive_idx) - time_hr(predictive_idx);
    else
        lead_time_hr = NaN;
    end

    results = table(mode, peak_T, threshold_violated, intervention_time_hr, ...
        'VariableNames', {'mode','peak_server_inlet_C','threshold_violated','intervention_time_hr'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(results, fullfile(cfg.paths.results_tables, 'exp09_reactive_vs_predictive.csv'));

    fprintf('Experiment 9 (Reactive vs Predictive): predictive lead time = %.1f h\n', lead_time_hr);
    disp(results);
end

% ------------------------------------------------------------------
function eff = local_apply_intervention(eff_baseline, intervention_idx)
    eff = eff_baseline;
    if ~isempty(intervention_idx)
        eff(intervention_idx:end) = 1.0;
    end
end

% ------------------------------------------------------------------
function t = local_time_or_nan(time_hr, idx)
    if isempty(idx)
        t = NaN;
    else
        t = time_hr(idx);
    end
end
