function metrics = evaluate_classifier(y_true, y_pred)
%EVALUATE_CLASSIFIER Compute the classification metrics required by §32.
%
%   metrics = EVALUATE_CLASSIFIER(y_true, y_pred) computes accuracy,
%   per-class precision/recall/F1, macro-F1, and the confusion matrix,
%   directly from the confusion counts (no toolbox dependency, so this
%   works identically whether or not Statistics and ML Toolbox is
%   installed).
%
%   Inputs:
%     y_true, y_pred - categorical vectors, same category set
%
%   Output struct 'metrics':
%     accuracy, macro_f1, confusion_matrix (table), per_class (table with
%     columns: class, precision, recall, f1)

    cats = categories(y_true);
    n_classes = numel(cats);

    C = zeros(n_classes, n_classes);   % rows = true, cols = predicted
    for i = 1:numel(y_true)
        r = find(strcmp(cats, char(y_true(i))));
        c = find(strcmp(cats, char(y_pred(i))));
        if ~isempty(r) && ~isempty(c)
            C(r, c) = C(r, c) + 1;
        end
    end

    metrics.accuracy = sum(diag(C)) / max(sum(C(:)), 1);

    precision = zeros(n_classes, 1);
    recall    = zeros(n_classes, 1);
    f1        = zeros(n_classes, 1);

    for k = 1:n_classes
        tp = C(k, k);
        fp = sum(C(:, k)) - tp;
        fn = sum(C(k, :)) - tp;
        precision(k) = tp / max(tp + fp, 1);
        recall(k)    = tp / max(tp + fn, 1);
        if (precision(k) + recall(k)) > 0
            f1(k) = 2 * precision(k) * recall(k) / (precision(k) + recall(k));
        else
            f1(k) = 0;
        end
    end

    metrics.macro_f1 = mean(f1);
    metrics.confusion_matrix = array2table(C, 'VariableNames', cats, 'RowNames', cats);
    metrics.per_class = table(cats, precision, recall, f1, ...
        'VariableNames', {'class','precision','recall','f1'});
end
