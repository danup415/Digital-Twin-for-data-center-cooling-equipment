function model = train_baseline_classifier(X_train, y_train, feat_names)
%TRAIN_BASELINE_CLASSIFIER Decision-tree baseline fault classifier.
%
%   model = TRAIN_BASELINE_CLASSIFIER(X_train, y_train, feat_names)
%   trains a simple decision tree (fitctree) as the project's floor
%   baseline (§21). Feature normalization statistics are fit on the
%   TRAIN split only and stored with the model so evaluation on Val/Test
%   never leaks normalization information from those splits (§23).
%
%   Inputs:
%     X_train, y_train - training feature matrix / categorical labels
%     feat_names        - cellstr, column names of X_train
%
%   Output:
%     model - struct with fields: type, tree, mu, sigma, feat_names

    mu    = mean(X_train, 1);
    sigma = std(X_train, [], 1);
    sigma(sigma < eps) = 1;   % avoid divide-by-zero for constant columns

    Xn = (X_train - mu) ./ sigma;

    tree = fitctree(Xn, y_train);

    model.type       = 'baseline_tree';
    model.tree        = tree;
    model.mu          = mu;
    model.sigma        = sigma;
    model.feat_names   = feat_names;
end
