function metrics = run_experiment_02(dataset, cfg)
%RUN_EXPERIMENT_02 Multi-class fault classification (§35, Exp. 2).
%
%   metrics = RUN_EXPERIMENT_02(dataset, cfg) trains the full multi-class
%   fault-type classifier (all fault labels, not collapsed to
%   Healthy/Faulty as in Experiment 1) on the fusion+state feature set —
%   this is the "production" classifier the diagnosis subsystem would use.
%
%   Output: metrics struct (accuracy, macro_f1, confusion_matrix,
%   per_class), saved to results/metrics/exp02_*.mat and the confusion
%   matrix additionally to results/tables/exp02_confusion_matrix.csv

    [X_train, y_train, feat_names] = load_dataset_split(dataset, 'Train', 'fusion_state');
    [X_test,  y_test,  ~]           = load_dataset_split(dataset, 'Test',  'fusion_state');

    model = train_random_forest(X_train, y_train, feat_names, cfg);
    y_pred = predict_model(model, X_test);
    metrics = evaluate_classifier(y_test, y_pred);

    if ~isfolder(cfg.paths.results_metrics); mkdir(cfg.paths.results_metrics); end
    save(fullfile(cfg.paths.results_metrics, 'exp02_multiclass.mat'), 'metrics');
    writetable(metrics.confusion_matrix, fullfile(cfg.paths.results_tables, 'exp02_confusion_matrix.csv'), ...
        'WriteRowNames', true);

    fprintf('Experiment 2 (Multi-class): accuracy=%.3f, macro-F1=%.3f\n', ...
        metrics.accuracy, metrics.macro_f1);
end
