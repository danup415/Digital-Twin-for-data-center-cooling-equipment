function [model, metadata] = load_or_train_model(feature_set)
%LOAD_OR_TRAIN_MODEL Load the persisted classifier, training once if absent.
%
%   [model, metadata] = LOAD_OR_TRAIN_MODEL(feature_set)
%     IF models/ML/trained_classifier.mat exists AND was trained on the
%       requested feature_set: load it.
%     ELSE: call train_and_save_model(feature_set) once, then load the
%       result it just saved.
%
%   The dashboard (Phase E) calls this exactly ONCE at startup and holds
%   the returned model in its app state for the rest of the session — it
%   does not call this again when the user changes fault/severity/IT
%   load/ambient/RPM, so the classifier is never retrained on a parameter
%   change, per the Phase D requirement.
%
%   Input:
%     feature_set - as in train_and_save_model.m (default 'fusion_state')
%
%   Outputs:
%     model    - struct ready for predict_model.m
%     metadata - struct from train_and_save_model.m (training timestamp,
%                feature_set, Test accuracy/macro-F1, etc. — descriptive
%                only, see train_and_save_model.m's docstring)

    if nargin < 1 || isempty(feature_set)
        feature_set = 'fusion_state';
    end

    cfg = project_config();
    saved_path = fullfile(cfg.paths.models_ml, 'trained_classifier.mat');

    if isfile(saved_path)
        L = load(saved_path, 'model', 'metadata');
        model = L.model;
        metadata = L.metadata;

        if ~strcmp(metadata.feature_set, feature_set)
            warning('load_or_train_model:featureSetMismatch', ...
                ['Saved model at %s was trained on feature_set=''%s'' but ', ...
                 '''%s'' was requested — retraining once for the requested ', ...
                 'feature set (this replaces the saved file).'], ...
                saved_path, metadata.feature_set, feature_set);
            saved_path = train_and_save_model(feature_set);
            L = load(saved_path, 'model', 'metadata');
            model = L.model;
            metadata = L.metadata;
        else
            fprintf('Loaded existing trained model (%s, trained %s, Test accuracy=%.3f).\n', ...
                saved_path, metadata.trained_at, metadata.test_accuracy);
        end
    else
        fprintf('No saved model found at %s — training once...\n', saved_path);
        saved_path = train_and_save_model(feature_set);
        L = load(saved_path, 'model', 'metadata');
        model = L.model;
        metadata = L.metadata;
    end
end
