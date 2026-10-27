function results = run_experiment_06(dataset, cfg)
%RUN_EXPERIMENT_06 Fixed vs adaptive threshold monitoring (§35 Exp. 6, §20).
%
%   results = RUN_EXPERIMENT_06(dataset, cfg) builds two baseline
%   monitoring systems from Healthy Train-split vibration RMS:
%     Fixed threshold    - a single mean+3*std computed across ALL
%                          Healthy Train rows regardless of operating
%                          condition.
%     Adaptive threshold - mean+3*std computed PER (speed_bin, load_bin)
%                          combination from Healthy Train rows in that
%                          bin only (threshold = f(speed, load), §20).
%
%   Both are then applied to the Test split (all fault types) and scored
%   on false-positive rate (flags on Healthy Test rows) and detection
%   rate (flags on Faulty Test rows) — the comparison §20 asks for.
%
%   Output:
%     results - struct with fixed and adaptive sub-structs (fpr, detection_rate),
%               saved to results/tables/exp06_threshold_comparison.csv

    train_healthy = dataset(dataset.split == "Train" & dataset.fault_type == "Healthy", :);
    test_set = dataset(dataset.split == "Test", :);

    % ---- Fixed threshold ----
    fixed_thresh = mean(train_healthy.vib_rms) + 3*std(train_healthy.vib_rms);

    % ---- Adaptive threshold: per (speed_bin, load_bin) ----
    [bin_groups, bin_speed, bin_load] = findgroups(train_healthy.speed_bin, train_healthy.load_bin);
    bin_thresh = splitapply(@(v) mean(v) + 3*std(v), train_healthy.vib_rms, bin_groups);
    adaptive_lookup = table(bin_speed, bin_load, bin_thresh);

    % ---- Apply both to Test ----
    is_healthy_test = test_set.fault_type == "Healthy";

    fixed_flag = test_set.vib_rms > fixed_thresh;

    adaptive_flag = false(height(test_set), 1);
    default_thresh = mean(adaptive_lookup.bin_thresh);   % fallback for any unseen bin combo
    for i = 1:height(test_set)
        match = adaptive_lookup.bin_speed == test_set.speed_bin(i) & ...
                adaptive_lookup.bin_load  == test_set.load_bin(i);
        if any(match)
            thresh_i = adaptive_lookup.bin_thresh(find(match, 1));
        else
            thresh_i = default_thresh;
        end
        adaptive_flag(i) = test_set.vib_rms(i) > thresh_i;
    end

    fixed.fpr = sum(fixed_flag & is_healthy_test) / max(sum(is_healthy_test), 1);
    fixed.detection_rate = sum(fixed_flag & ~is_healthy_test) / max(sum(~is_healthy_test), 1);

    adaptive.fpr = sum(adaptive_flag & is_healthy_test) / max(sum(is_healthy_test), 1);
    adaptive.detection_rate = sum(adaptive_flag & ~is_healthy_test) / max(sum(~is_healthy_test), 1);

    results.fixed = fixed;
    results.adaptive = adaptive;

    summary_table = table(["Fixed";"Adaptive"], [fixed.fpr; adaptive.fpr], ...
        [fixed.detection_rate; adaptive.detection_rate], ...
        'VariableNames', {'method','false_positive_rate','detection_rate'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(summary_table, fullfile(cfg.paths.results_tables, 'exp06_threshold_comparison.csv'));

    fprintf('Experiment 6: Fixed FPR=%.3f Det=%.3f | Adaptive FPR=%.3f Det=%.3f\n', ...
        fixed.fpr, fixed.detection_rate, adaptive.fpr, adaptive.detection_rate);
end
