function results = run_experiment_04(cfg, P)
%RUN_EXPERIMENT_04 Early-warning detection lead time (§35 Exp. 4, §31).
%
%   results = RUN_EXPERIMENT_04(cfg, P) runs SIMULATE_DEGRADATION_TRAJECTORY
%   for every non-Healthy fault on both equipment types, and for each
%   trajectory computes:
%     T_detection - first time the decision engine reaches WARNING or worse
%     T_critical  - first time the thermal margin is violated (<=0)
%     lead_time_hr = T_critical - T_detection  (positive = warned in advance)
%
%   Then reports mean/median/min/max lead time and the percentage of
%   trajectories where a warning preceded the thermal violation (§31) —
%   computed directly from the simulated trajectories, not asserted.
%
%   Output:
%     results - table, one row per (equipment, fault_type) trajectory,
%               plus a printed summary; saved to
%               results/tables/exp04_early_warning.csv

    T_thresh = get_maintenance_thresholds();
    duration_hr = 500;
    n_steps = 100;
    load_frac = 0.8;

    rows = {};
    equipment_list = cfg.equipment;

    for e = 1:numel(equipment_list)
        equipment = equipment_list{e};
        fault_list = cfg.faults.(equipment);
        for f = 1:numel(fault_list)
            fault_type = fault_list{f};
            if strcmp(fault_type, 'Healthy')
                continue;
            end

            traj = simulate_degradation_trajectory(equipment, fault_type, duration_hr, n_steps, load_frac, cfg, P, T_thresh);

            warned_idx = find(traj.decision_level ~= "NORMAL" & traj.decision_level ~= "MONITOR", 1, 'first');
            critical_idx = find(traj.thermal_margin_C <= 0, 1, 'first');

            if isempty(warned_idx)
                T_detection = NaN;
            else
                T_detection = traj.time_hr(warned_idx);
            end
            if isempty(critical_idx)
                T_critical = NaN;
            else
                T_critical = traj.time_hr(critical_idx);
            end

            if ~isnan(T_detection) && ~isnan(T_critical)
                lead_time_hr = T_critical - T_detection;
            else
                lead_time_hr = NaN;
            end

            rows(end+1, :) = {string(equipment), string(fault_type), T_detection, T_critical, lead_time_hr}; %#ok<AGROW>
        end
    end

    results = cell2table(rows, 'VariableNames', ...
        {'equipment','fault_type','T_detection_hr','T_critical_hr','lead_time_hr'});

    valid_lead = results.lead_time_hr(~isnan(results.lead_time_hr));
    n_with_threshold_hit = sum(~isnan(results.T_critical_hr));
    n_detected_before = sum(valid_lead > 0);

    fprintf('Experiment 4 (Early Warning): mean lead=%.1fh median=%.1fh min=%.1fh max=%.1fh\n', ...
        mean(valid_lead), median(valid_lead), min(valid_lead), max(valid_lead));
    if n_with_threshold_hit > 0
        fprintf('  Detected before thermal threshold: %.0f%% of trajectories that reached it\n', ...
            100 * n_detected_before / n_with_threshold_hit);
    end

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(results, fullfile(cfg.paths.results_tables, 'exp04_early_warning.csv'));
end
