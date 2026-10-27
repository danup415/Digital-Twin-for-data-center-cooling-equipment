function y_pred = predict_model(model, X)
%PREDICT_MODEL Unified prediction across every model type this project trains.
%
%   y_pred = PREDICT_MODEL(model, X) normalizes X using the model's stored
%   mu/sigma (fit on Train only, §23) and dispatches to the correct
%   underlying predictor based on model.type, so evaluate_classifier and
%   run_ablation_study can treat every model the same way.
%
%   Inputs:
%     model - struct from train_baseline_classifier / train_random_forest /
%             train_cnn1d
%     X     - raw (unnormalized) feature matrix, columns matching model.feat_names
%
%   Output:
%     y_pred - categorical predicted labels

    Xn = (X - model.mu) ./ model.sigma;

    switch model.type
        case 'baseline_tree'
            y_pred = predict(model.tree, Xn);

        case 'random_forest_bag'
            y_pred = predict(model.ensemble, Xn);

        case 'knn_fallback'
            y_pred = local_knn_predict(model.Xn_train, model.y_train, Xn, model.k);

        case 'cnn1d'
            y_pred = local_cnn_predict(model, Xn);

        otherwise
            error('predict_model:unknownType', 'Unknown model.type: %s', model.type);
    end
end

% ------------------------------------------------------------------
function y_pred = local_knn_predict(Xn_train, y_train, Xn_query, k)
%LOCAL_KNN_PREDICT Base-MATLAB k-NN majority vote (no toolbox dependency).
    n_query = size(Xn_query, 1);
    cats = categories(y_train);
    y_pred = repmat(cats(1), n_query, 1);
    y_pred = categorical(y_pred, cats);

    for i = 1:n_query
        d = sum((Xn_train - Xn_query(i, :)).^2, 2);
        [~, idx] = sort(d, 'ascend');
        nn_labels = y_train(idx(1:min(k, numel(idx))));
        y_pred(i) = mode(nn_labels);
    end
end

% ------------------------------------------------------------------
function y_pred = local_cnn_predict(model, Xn)
%LOCAL_CNN_PREDICT Reshape features into a pseudo-sequence and classify.
    Xseq = local_reshape_for_cnn(Xn);
    y_pred = classify(model.net, Xseq);
end

% ------------------------------------------------------------------
function Xseq = local_reshape_for_cnn(Xn)
%LOCAL_RESHAPE_FOR_CNN Treat the feature vector as a length-F "1D signal"
%   with 1 channel, the input format expected by a sequenceInputLayer/
%   1D-CNN trained in train_cnn1d.m.
    [n, f] = size(Xn);
    Xseq = cell(n, 1);
    for i = 1:n
        Xseq{i} = reshape(Xn(i, :), 1, f);   % 1 channel x f "time steps"
    end
end
