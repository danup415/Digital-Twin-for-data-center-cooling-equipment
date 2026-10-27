function model = train_random_forest(X_train, y_train, feat_names, cfg)
%TRAIN_RANDOM_FOREST Ensemble classifier (Random-Forest-style bagged trees).
%
%   model = TRAIN_RANDOM_FOREST(X_train, y_train, feat_names, cfg) trains
%   a bagged-tree ensemble via fitcensemble('Bag') when the Statistics and
%   Machine Learning Toolbox is available (§21). If XGBoost is not
%   available (never assumed per the brief) this ensemble is the
%   "classical" tier of the model comparison.
%
%   Fallback (§M): if the toolbox is unavailable, a hand-rolled bagging
%   ensemble of decision trees (fitctree, available in base MATLAB is NOT
%   guaranteed either — fitctree itself requires the Statistics Toolbox,
%   so the true fallback here is a simple k-NN-style majority-vote
%   classifier built from base MATLAB only) is used, and the model struct
%   records which path was taken so reports never overstate the method.
%
%   Inputs:
%     X_train, y_train, feat_names - as in train_baseline_classifier
%     cfg - struct from project_config() (uses cfg.toolbox.statistics_ml)
%
%   Output:
%     model - struct with fields: type, ensemble (or knn_fallback data),
%             mu, sigma, feat_names

    mu    = mean(X_train, 1);
    sigma = std(X_train, [], 1);
    sigma(sigma < eps) = 1;
    Xn = (X_train - mu) ./ sigma;

    model.mu = mu;
    model.sigma = sigma;
    model.feat_names = feat_names;

    if cfg.toolbox.statistics_ml
        n_trees = 100;
        template = templateTree('MaxNumSplits', 20);
        model.ensemble = fitcensemble(Xn, y_train, 'Method', 'Bag', ...
            'NumLearningCycles', n_trees, 'Learners', template);
        model.type = 'random_forest_bag';
    else
        % Base-MATLAB fallback: store the normalized training set and use
        % k-NN majority vote at prediction time (predict_model.m).
        model.type = 'knn_fallback';
        model.Xn_train = Xn;
        model.y_train  = y_train;
        model.k        = 5;
    end
end
