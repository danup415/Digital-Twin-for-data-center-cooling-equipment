function metrics = run_experiment_03(dataset, cfg)
%RUN_EXPERIMENT_03 Fault severity estimation as regression (§35, Exp. 3).
%
%   metrics = RUN_EXPERIMENT_03(dataset, cfg) trains a regressor that
%   predicts the continuous fault_severity (D in [0,1]) from the
%   fusion+state feature set, evaluated with MAE/RMSE (§32).
%
%   Uses fitrensemble (bagged trees) if the Statistics and Machine
%   Learning Toolbox is available; otherwise falls back to ordinary
%   least-squares linear regression via the backslash operator (base
%   MATLAB only, §M).
%
%   Output: metrics struct (MAE, RMSE, model_type), saved to
%   results/metrics/exp03_severity_regression.mat

    [X_train, y_train_fault, feat_names] = load_dataset_split(dataset, 'Train', 'fusion_state');
    [X_test,  y_test_fault,  ~]           = load_dataset_split(dataset, 'Test',  'fusion_state');

    mask_train = dataset.split == "Train";
    mask_test  = dataset.split == "Test";
    d_train = dataset.fault_severity(mask_train);
    d_test  = dataset.fault_severity(mask_test);

    mu    = mean(X_train, 1);
    sigma = std(X_train, [], 1);
    sigma(sigma < eps) = 1;
    Xn_train = (X_train - mu) ./ sigma;
    Xn_test  = (X_test  - mu) ./ sigma;

    if cfg.toolbox.statistics_ml
        reg_model = fitrensemble(Xn_train, d_train, 'Method', 'Bag');
        d_pred = predict(reg_model, Xn_test);
        model_type = 'bagged_tree_regressor';
    else
        A = [ones(size(Xn_train,1),1), Xn_train];
        coeffs = A \ d_train;
        A_test = [ones(size(Xn_test,1),1), Xn_test];
        d_pred = A_test * coeffs;
        model_type = 'ols_linear_fallback';
    end

    d_pred = min(max(d_pred, 0), 1);   % severity is physically bounded to [0,1]

    metrics.model_type = model_type;
    metrics.MAE  = mean(abs(d_pred - d_test));
    metrics.RMSE = sqrt(mean((d_pred - d_test).^2));

    if ~isfolder(cfg.paths.results_metrics); mkdir(cfg.paths.results_metrics); end
    save(fullfile(cfg.paths.results_metrics, 'exp03_severity_regression.mat'), 'metrics');

    fprintf('Experiment 3 (Severity regression, %s): MAE=%.4f, RMSE=%.4f\n', ...
        model_type, metrics.MAE, metrics.RMSE);
end
