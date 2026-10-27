function model = train_cnn1d(X_train, y_train, feat_names, cfg)
%TRAIN_CNN1D Lightweight 1D-CNN fault classifier (deep-learning tier).
%
%   model = TRAIN_CNN1D(X_train, y_train, feat_names, cfg) trains a small
%   1D convolutional network over the feature vector (treated as a
%   length-F sequence with 1 channel) per §21. A TCN was considered but
%   the brief explicitly requires a robust CNN fallback if TCN training is
%   unstable — this project defaults straight to the CNN as the primary
%   deep-learning tier to keep training reliable and reproducible.
%
%   If the Deep Learning Toolbox is unavailable, this function returns
%   model.type = 'unavailable' and the caller (run_ablation_study) skips
%   the deep-learning tier and reports that honestly rather than
%   fabricating a result (§51).
%
%   Inputs:
%     X_train, y_train, feat_names - as in train_baseline_classifier
%     cfg - struct from project_config() (uses cfg.toolbox.deep_learning)
%
%   Output:
%     model - struct with fields: type, net, mu, sigma, feat_names
%             (or type='unavailable' with no net)

    mu    = mean(X_train, 1);
    sigma = std(X_train, [], 1);
    sigma(sigma < eps) = 1;

    model.mu = mu;
    model.sigma = sigma;
    model.feat_names = feat_names;

    if ~cfg.toolbox.deep_learning
        model.type = 'unavailable';
        warning('train_cnn1d:noToolbox', ...
            ['Deep Learning Toolbox not detected — skipping CNN tier. ', ...
             'Reporting classical-ML-only results (see docs/architecture.md §M).']);
        return;
    end

    Xn = (X_train - mu) ./ sigma;
    n_features = size(Xn, 2);
    n_classes  = numel(categories(y_train));

    Xseq = cell(size(Xn, 1), 1);
    for i = 1:size(Xn, 1)
        Xseq{i} = reshape(Xn(i, :), 1, n_features);
    end

    layers = [
        sequenceInputLayer(1, 'Name', 'input')
        convolution1dLayer(5, 16, 'Padding', 'same', 'Name', 'conv1')
        batchNormalizationLayer('Name', 'bn1')
        reluLayer('Name', 'relu1')
        convolution1dLayer(3, 32, 'Padding', 'same', 'Name', 'conv2')
        batchNormalizationLayer('Name', 'bn2')
        reluLayer('Name', 'relu2')
        globalAveragePooling1dLayer('Name', 'gap')
        fullyConnectedLayer(n_classes, 'Name', 'fc')
        softmaxLayer('Name', 'softmax')
        classificationLayer('Name', 'output')
    ];

    options = trainingOptions('adam', ...
        'MaxEpochs', 30, ...
        'MiniBatchSize', 32, ...
        'Shuffle', 'every-epoch', ...
        'Verbose', false, ...
        'Plots', 'none');

    try
        net = trainNetwork(Xseq, y_train, layers, options);
        model.type = 'cnn1d';
        model.net  = net;
    catch ME
        warning('train_cnn1d:trainingFailed', ...
            'CNN training failed (%s) — falling back to classical-ML-only reporting.', ME.message);
        model.type = 'unavailable';
    end
end
