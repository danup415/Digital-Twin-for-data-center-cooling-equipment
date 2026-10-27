function saved_path = train_and_save_model(feature_set)
%TRAIN_AND_SAVE_MODEL Train once via the existing pipeline, persist to disk.
%
%   saved_path = TRAIN_AND_SAVE_MODEL(feature_set) runs the EXISTING
%   dataset-generation and training pipeline
%   (generate_scenarios -> generate_dataset -> load_dataset_split ->
%   train_random_forest — no new training logic), then saves the trained
%   model struct plus descriptive metadata to
%   models/ML/trained_classifier.mat. This is the one place in the
%   interactive layer that trains a model; load_or_train_model.m calls
%   this only when no saved model exists yet, so the dashboard itself
%   never retrains.
%
%   What gets saved, and why:
%     model     - the full struct from train_random_forest (type, mu,
%                 sigma, feat_names, and either .ensemble or the
%                 k-NN-fallback training data — whatever
%                 train_random_forest itself produced, unmodified). This
%                 already contains "feature names/order" (model.feat_names)
%                 and everything predict_model needs for inference.
%     metadata  - feature_set used, training timestamp, seed, sample
%                 counts, and Test-split accuracy/macro-F1 AS DESCRIPTIVE
%                 STATISTICS about this training run only. These numbers
%                 are never read back by run_single_operating_point or any
%                 inference path — they exist purely so the dashboard (or
%                 you) can display "this model was trained on <date>,
%                 Test accuracy was X" without needing to retrain to find
%                 out. Test-set PREDICTIONS themselves are not saved at
%                 all, so there is no path by which they could later be
%                 mistaken for model inputs.
%
%   Input:
%     feature_set - 'vibration' | 'mcsa' | 'fusion' | 'fusion_state'
%                   (default 'fusion_state', matching the "production"
%                   classifier used in Experiment 2)
%
%   Output:
%     saved_path - full path to the saved .mat file

    if nargin < 1 || isempty(feature_set)
        feature_set = 'fusion_state';
    end

    cfg = project_config();
    SensorConfig = sensor_config();
    P = model_parameters();

    scenarios = generate_scenarios(cfg, 6);
    dataset = generate_dataset(cfg, SensorConfig, P, scenarios);

    [X_train, y_train, feat_names] = load_dataset_split(dataset, 'Train', feature_set);
    model = train_random_forest(X_train, y_train, feat_names, cfg);

    % Test-split accuracy is computed here ONLY to record as descriptive
    % metadata (see docstring above) — the predictions themselves are not
    % saved, and nothing downstream reads this back as an input.
    [X_test, y_test, ~] = load_dataset_split(dataset, 'Test', feature_set);
    y_pred = predict_model(model, X_test);
    test_metrics = evaluate_classifier(y_test, y_pred);

    metadata.feature_set      = feature_set;
    metadata.trained_at        = datestr(now);
    metadata.seed               = cfg.seed;
    metadata.n_train_samples    = size(X_train, 1);
    metadata.n_test_samples     = size(X_test, 1);
    metadata.test_accuracy      = test_metrics.accuracy;
    metadata.test_macro_f1      = test_metrics.macro_f1;
    metadata.equipment          = cfg.equipment;
    metadata.faults             = cfg.faults;

    if ~isfolder(cfg.paths.models_ml)
        mkdir(cfg.paths.models_ml);
    end
    saved_path = fullfile(cfg.paths.models_ml, 'trained_classifier.mat');
    save(saved_path, 'model', 'metadata');

    fprintf(['Trained model saved to %s\n  feature_set=%s, Train n=%d, Test n=%d, ', ...
             'Test accuracy=%.3f, Test macro-F1=%.3f\n'], ...
        saved_path, feature_set, metadata.n_train_samples, metadata.n_test_samples, ...
        metadata.test_accuracy, metadata.test_macro_f1);
end
