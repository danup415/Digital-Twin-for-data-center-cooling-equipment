function results = run_experiment_08(dataset, cfg, SensorConfig, P)
%RUN_EXPERIMENT_08 AI-only vs physics-informed AI (§35 Exp. 8, §36).
%
%   results = RUN_EXPERIMENT_08(dataset, cfg, SensorConfig, P) is the one
%   place in this project that computes physics-residual features
%   (compute_physics_residual_features.m) and adds them to the
%   fusion+state feature set ("Model E" from §34's ablation ladder,
%   evaluated here rather than in run_ablation_study.m since it needs
%   this extra per-row computation). Compares:
%     AI-only              - fusion+state features (= Model D)
%     Physics-informed AI  - fusion+state + 4 physics-residual features
%
%   Both use the same Random-Forest/bagged-tree classifier so any
%   difference is attributable to the added residual features.
%
%   Output:
%     results - table (model, accuracy, macro_f1), saved to
%               results/tables/exp08_ai_vs_physics_informed.csv

    window_duration_s = 1.0;   % must match generate_dataset.m

    n = height(dataset);
    resid_rms_v = zeros(n,1); resid_kurt_v = zeros(n,1);
    resid_rms_m = zeros(n,1); resid_thd_m  = zeros(n,1);

    for i = 1:n
        r = compute_physics_residual_features(dataset(i,:), cfg, SensorConfig, P, window_duration_s);
        resid_rms_v(i)  = r.resid_vib_rms;
        resid_kurt_v(i) = r.resid_vib_kurtosis;
        resid_rms_m(i)  = r.resid_mcsa_rms;
        resid_thd_m(i)  = r.resid_mcsa_THD;
    end

    augmented = dataset;
    augmented.resid_vib_rms      = resid_rms_v;
    augmented.resid_vib_kurtosis = resid_kurt_v;
    augmented.resid_mcsa_rms     = resid_rms_m;
    augmented.resid_mcsa_THD     = resid_thd_m;

    % ---- AI-only (Model D, fusion+state) ----
    [Xa_train, y_train, feat_a] = load_dataset_split(augmented, 'Train', 'fusion_state');
    [Xa_test,  y_test,  ~]      = load_dataset_split(augmented, 'Test',  'fusion_state');
    model_ai = train_random_forest(Xa_train, y_train, feat_a, cfg);
    y_pred_ai = predict_model(model_ai, Xa_test);
    metrics_ai = evaluate_classifier(y_test, y_pred_ai);

    % ---- Physics-informed AI (fusion+state + residuals, Model E) ----
    resid_cols = {'resid_vib_rms','resid_vib_kurtosis','resid_mcsa_rms','resid_mcsa_THD'};
    feat_e = [feat_a, resid_cols];
    mask_train = augmented.split == "Train";
    mask_test  = augmented.split == "Test";
    Xe_train = table2array(augmented(mask_train, feat_e));
    Xe_test  = table2array(augmented(mask_test,  feat_e));
    model_phys = train_random_forest(Xe_train, y_train, feat_e, cfg);
    y_pred_phys = predict_model(model_phys, Xe_test);
    metrics_phys = evaluate_classifier(y_test, y_pred_phys);

    results = table(["AI-only (Model D)"; "Physics-informed AI (Model E)"], ...
        [metrics_ai.accuracy; metrics_phys.accuracy], ...
        [metrics_ai.macro_f1; metrics_phys.macro_f1], ...
        'VariableNames', {'model','accuracy','macro_f1'});

    if ~isfolder(cfg.paths.results_tables); mkdir(cfg.paths.results_tables); end
    writetable(results, fullfile(cfg.paths.results_tables, 'exp08_ai_vs_physics_informed.csv'));

    fprintf('Experiment 8 (AI-only vs Physics-informed AI):\n');
    disp(results);
end
