function results = run_ablation_study(dataset, cfg)
%RUN_ABLATION_STUDY Vibration-only / MCSA-only / Fusion / Fusion+state (§34).
%
%   results = RUN_ABLATION_STUDY(dataset, cfg) trains the SAME classifier
%   (the random-forest / bagged-tree tier from train_random_forest, so any
%   difference in results is attributable to the feature set, not the
%   model) on four feature configurations:
%     Model A: vibration-only
%     Model B: MCSA-only
%     Model C: vibration + MCSA (fusion)
%     Model D: vibration + MCSA + operating state (fusion+state)
%
%   Model E (physics-informed residual features) is NOT included here —
%   it depends on physics-residual features that are a later addition
%   (§36 of the original brief) not yet built in Phases 2-11, and is
%   listed as future work rather than fabricated.
%
%   Training uses the Train split, evaluation uses the Test split, per
%   the scenario-level split assigned in generate_scenarios (§23).
%
%   Inputs:
%     dataset - table from generate_dataset
%     cfg     - struct from project_config()
%
%   Output:
%     results - table with columns: model, feature_set, accuracy, macro_f1

    feature_sets = {'vibration', 'mcsa', 'fusion', 'fusion_state'};
    model_labels = {'Model A: Vibration-only', 'Model B: MCSA-only', ...
                     'Model C: Fusion', 'Model D: Fusion+state'};

    n = numel(feature_sets);
    model_name = cell(n, 1);
    feat_set_name = cell(n, 1);
    accuracy = zeros(n, 1);
    macro_f1 = zeros(n, 1);

    for i = 1:n
        [X_train, y_train, feat_names] = load_dataset_split(dataset, 'Train', feature_sets{i});
        [X_test,  y_test,  ~]           = load_dataset_split(dataset, 'Test',  feature_sets{i});

        m = train_random_forest(X_train, y_train, feat_names, cfg);
        y_pred = predict_model(m, X_test);
        metrics = evaluate_classifier(y_test, y_pred);

        model_name{i}    = model_labels{i};
        feat_set_name{i} = feature_sets{i};
        accuracy(i)      = metrics.accuracy;
        macro_f1(i)      = metrics.macro_f1;
    end

    results = table(model_name, feat_set_name, accuracy, macro_f1, ...
        'VariableNames', {'model','feature_set','accuracy','macro_f1'});

    results_path = fullfile(cfg.paths.results_tables, 'ablation_study.csv');
    writetable(results, results_path);
end
