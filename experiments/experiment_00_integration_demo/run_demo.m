function traj_results = run_demo()
%RUN_DEMO Phase 2-11 integration demonstration on a degradation trajectory.
%
%   traj_results = RUN_DEMO() is NOT the final §50 "Final Demonstration
%   Scenario" (that belongs to Phase 15/Experiments, with a full
%   reactive-vs-predictive comparison). It is a smaller integration
%   smoke-test proving that the Phase 2-11 building blocks actually chain
%   together: CRAC-fan bearing degradation ramps from Healthy to Critical
%   over a simulated 500-hour run, and at each time step this script
%   exercises the fault model, Health Index, RUL estimator, thermal
%   digital twin, and maintenance decision engine on the SAME trajectory.
%
%   Output:
%     traj_results - table with columns: time_hr, D, HI, RUL_hr,
%                    T_server_inlet_C, thermal_margin_C, decision_level
%     Also saves this table to results/tables/integration_demo.csv and a
%     Health-Index/thermal-margin plot to results/figures/integration_demo.png

    addpath(genpath(fileparts(mfilename('fullpath'))));
    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(genpath(project_root));

    cfg = project_config();
    P   = model_parameters();
    T_thresh = get_maintenance_thresholds();

    equipment  = 'Fan';
    fault_type = 'BearingDegradation';

    n_steps = 50;
    time_hr = linspace(0, 500, n_steps)';

    % Degradation ramps linearly from Healthy (0) to just past the
    % critical threshold, so the demo actually crosses every decision level.
    % Ramp to D=1 (true failure) — see the rationale comment in
    % src/thermal/simulate_degradation_trajectory.m.
    D_vec = linspace(0, 1, n_steps)';
    D_vec = min(D_vec, 1);

    HI_vec = compute_health_index(D_vec, P.Health);

    N_rpm = P.Fan.N_nominal_rpm;
    load_frac = 0.8;
    ambient_C = P.Thermal.ambient_C_nominal;
    IT_load_kW_vec = P.Thermal.IT_load_kW_nominal * ones(n_steps, 1);
    ambient_C_vec  = ambient_C * ones(n_steps, 1);

    effectiveness_vec = zeros(n_steps, 1);
    for k = 1:n_steps
        effectiveness_vec(k) = cooling_effectiveness_from_degradation(equipment, fault_type, D_vec(k));
    end

    time_s = time_hr * 3600;   % thermal twin integrates in seconds
    thermal_traj = thermal_digital_twin(time_s, IT_load_kW_vec, ambient_C_vec, effectiveness_vec, P.Thermal);

    RUL_vec = nan(n_steps, 1);
    decision_level = cell(n_steps, 1);

    rul_window = 5;   % use the last 5 samples' HI trend to extrapolate RUL
    for k = 1:n_steps
        w_start = max(1, k - rul_window + 1);
        rul_out = estimate_rul(time_hr(w_start:k), HI_vec(w_start:k), P.Health);
        RUL_vec(k) = rul_out.RUL;

        decision = maintenance_decision_engine(NaN, D_vec(k), HI_vec(k), RUL_vec(k), ...
            thermal_traj.thermal_margin_C(k), T_thresh);
        decision_level{k} = decision.level;
    end

    traj_results = table(time_hr, D_vec, HI_vec, RUL_vec, ...
        thermal_traj.T_server_inlet_C, thermal_traj.thermal_margin_C, string(decision_level), ...
        'VariableNames', {'time_hr','D','HI','RUL_hr','T_server_inlet_C','thermal_margin_C','decision_level'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    if ~isfolder(cfg.paths.results_figures); mkdir(cfg.paths.results_figures); end

    writetable(traj_results, fullfile(cfg.paths.results_tables, 'integration_demo.csv'));

    fig = figure('Visible', 'off');
    subplot(2,1,1);
    plot(time_hr, HI_vec, '-o'); hold on;
    yline(T_thresh.HI_warning, '--', 'Warning');
    yline(T_thresh.HI_maintenance, '--', 'Maintenance');
    yline(T_thresh.HI_critical, '--', 'Critical');
    xlabel('Time (hr)'); ylabel('Health Index'); title('Health Index vs Time');

    subplot(2,1,2);
    plot(time_hr, thermal_traj.thermal_margin_C, '-o'); hold on;
    yline(T_thresh.thermal_margin_warning_C, '--', 'Warning');
    yline(T_thresh.thermal_margin_critical_C, '--', 'Critical');
    xlabel('Time (hr)'); ylabel('Thermal margin (C)'); title('Thermal Margin vs Time');

    saveas(fig, fullfile(cfg.paths.results_figures, 'integration_demo.png'));
    close(fig);
end
