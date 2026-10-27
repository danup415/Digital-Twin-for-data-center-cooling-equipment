function results = run_experiment_10(dataset, cfg)
%RUN_EXPERIMENT_10 Known vs unseen operating conditions (§35 Exp. 10, §23).
%
%   results = RUN_EXPERIMENT_10(dataset, cfg) trains the fusion+state
%   classifier on Train (which only contains the "known" speed band,
%   1200-1600 rpm, by construction in generate_scenarios.m), then
%   evaluates it SEPARATELY on the two disjoint parts of the Test split:
%     known_condition_test   - is_unseen_condition == false
%     unseen_condition_test  - is_unseen_condition == true (1600-1800 rpm,
%                              a speed band never seen in Train)
%
%   This directly measures the generalization gap (§23) rather than
%   assuming the model generalizes.
%
%   Output:
%     results - table (test_subset, accuracy, macro_f1), saved to
%               results/tables/exp10_known_vs_unseen.csv

    [X_train, y_train, feat_names] = load_dataset_split(dataset, 'Train', 'fusion_state');
    model = train_random_forest(X_train, y_train, feat_names, cfg);

    test_set = dataset(dataset.split == "Test", :);

    known_mask  = ~test_set.is_unseen_condition;
    unseen_mask =  test_set.is_unseen_condition;

    subset_names = {'known_condition_test', 'unseen_condition_test'};
    masks = {known_mask, unseen_mask};
    accuracy = zeros(2,1); macro_f1 = zeros(2,1); n_samples = zeros(2,1);

    for i = 1:2
        sub = test_set(masks{i}, :);
        n_samples(i) = height(sub);
        if n_samples(i) == 0
            accuracy(i) = NaN; macro_f1(i) = NaN;
            continue;
        end
        X_sub = table2array(sub(:, feat_names));
        y_sub = categorical(sub.fault_type);
        y_pred = predict_model(model, X_sub);
        m = evaluate_classifier(y_sub, y_pred);
        accuracy(i) = m.accuracy;
        macro_f1(i) = m.macro_f1;
    end

    results = table(subset_names', n_samples, accuracy, macro_f1, ...
        'VariableNames', {'test_subset','n_samples','accuracy','macro_f1'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(results, fullfile(cfg.paths.results_tables, 'exp10_known_vs_unseen.csv'));

    fprintf('Experiment 10 (Known vs Unseen conditions):\n');
    disp(results);
end
