function metrics = run_experiment_05(cfg, P)
%RUN_EXPERIMENT_05 RUL prediction accuracy (§35, Exp. 5).
%
%   metrics = RUN_EXPERIMENT_05(cfg, P) uses the same degradation
%   trajectory mechanism as Experiment 4, but here the trajectory's exact
%   D(t) ramp gives a GROUND-TRUTH time at which D crosses D_critical
%   (by construction of the linear ramp), so the estimated RUL at each
%   time step can be compared against the true remaining time with a
%   real MAE/RMSE (§32) — not just reported without a reference.
%
%   Output:
%     metrics - struct: MAE_hr, RMSE_hr, n_valid_points, saved to
%               results/metrics/exp05_rul_accuracy.mat

    T_thresh = get_maintenance_thresholds();
    equipment = 'Fan';
    fault_type = 'BearingDegradation';
    duration_hr = 500;
    n_steps = 100;
    load_frac = 0.8;

    traj = simulate_degradation_trajectory(equipment, fault_type, duration_hr, n_steps, load_frac, cfg, P, T_thresh);

    % Ground truth: since D(t) is linear in time by construction, the
    % true crossing time of D_critical is known exactly from the ramp.
    D_vec = traj.D;
    time_hr = traj.time_hr;
    crossing_idx = find(D_vec >= P.Health.D_critical, 1, 'first');
    if isempty(crossing_idx)
        error('run_experiment_05:noCrossing', ...
            'Trajectory never reaches D_critical — extend duration_hr or n_steps.');
    end
    % Linear interpolation for the exact crossing time.
    if crossing_idx == 1
        T_true_critical = time_hr(1);
    else
        d0 = D_vec(crossing_idx-1); d1 = D_vec(crossing_idx);
        t0 = time_hr(crossing_idx-1); t1 = time_hr(crossing_idx);
        frac = (P.Health.D_critical - d0) / (d1 - d0);
        T_true_critical = t0 + frac*(t1 - t0);
    end

    true_RUL = T_true_critical - time_hr;
    valid = ~isnan(traj.RUL_hr) & (true_RUL >= 0);   % only score points before the true critical time

    err = traj.RUL_hr(valid) - true_RUL(valid);

    metrics.MAE_hr  = mean(abs(err));
    metrics.RMSE_hr = sqrt(mean(err.^2));
    metrics.n_valid_points = sum(valid);

    if ~isfolder(cfg.paths.results_metrics); mkdir(cfg.paths.results_metrics); end
    save(fullfile(cfg.paths.results_metrics, 'exp05_rul_accuracy.mat'), 'metrics');

    fprintf('Experiment 5 (RUL accuracy): MAE=%.1fh RMSE=%.1fh over %d valid points\n', ...
        metrics.MAE_hr, metrics.RMSE_hr, metrics.n_valid_points);
end
