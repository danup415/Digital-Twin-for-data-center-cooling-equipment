function metrics = run_experiment_01(dataset, cfg)
%RUN_EXPERIMENT_01 Normal vs faulty binary classification (§35, Exp. 1).
%
%   metrics = RUN_EXPERIMENT_01(dataset, cfg) relabels every non-'Healthy'
%   fault_type as 'Faulty', trains the Phase-8 Random-Forest/bagged-tree
%   classifier on the fusion+state feature set (Train split), and
%   evaluates on Test.
%
%   Inputs:  dataset - table from generate_dataset; cfg - project_config()
%   Output:  metrics - struct from evaluate_classifier (accuracy, macro_f1,
%            confusion_matrix, per_class), saved to results/metrics/exp01_*.mat

    binary_dataset = dataset;
    is_healthy = binary_dataset.fault_type == "Healthy";
    binary_dataset.fault_type(~is_healthy) = "Faulty";

    [X_train, y_train, feat_names] = load_dataset_split(binary_dataset, 'Train', 'fusion_state');
    [X_test,  y_test,  ~]           = load_dataset_split(binary_dataset, 'Test',  'fusion_state');

    model = train_random_forest(X_train, y_train, feat_names, cfg);
    y_pred = predict_model(model, X_test);
    metrics = evaluate_classifier(y_test, y_pred);

    out_path = fullfile(cfg.paths.results_metrics, 'exp01_normal_vs_faulty.mat');
    if ~isfolder(cfg.paths.results_metrics); mkdir(cfg.paths.results_metrics); end
    save(out_path, 'metrics');

    fprintf('Experiment 1 (Normal vs Faulty): accuracy=%.3f, macro-F1=%.3f\n', ...
        metrics.accuracy, metrics.macro_f1);
end
