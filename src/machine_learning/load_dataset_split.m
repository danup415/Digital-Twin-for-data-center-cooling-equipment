function [X, y, feat_names] = load_dataset_split(dataset, split_name, feature_set)
%LOAD_DATASET_SPLIT Extract a feature matrix / label vector for one split.
%
%   [X, y, feat_names] = LOAD_DATASET_SPLIT(dataset, split_name,
%   feature_set) filters 'dataset' (from generate_dataset) to rows whose
%   .split field equals split_name ('Train'/'Val'/'Test'), then selects
%   columns according to feature_set to support the ablation ladder (§18,
%   §34):
%
%     'vibration' - vib_* columns only               (Model A)
%     'mcsa'      - mcsa_* columns only               (Model B)
%     'fusion'    - vib_* + mcsa_* columns            (Model C)
%     'fusion_state' - vib_* + mcsa_* + operating state (Model D)
%
%   CRITICAL: this function never re-splits rows by anything other than
%   the pre-assigned scenario-level .split column, so no data-leakage
%   re-partitioning happens here (§23).
%
%   Inputs:
%     dataset     - table from generate_dataset
%     split_name  - 'Train' | 'Val' | 'Test'
%     feature_set - 'vibration' | 'mcsa' | 'fusion' | 'fusion_state'
%
%   Outputs:
%     X          - numeric feature matrix (rows = samples)
%     y          - categorical fault_type labels
%     feat_names - cellstr of the columns used, in X's column order

    mask = dataset.split == string(split_name);
    sub = dataset(mask, :);

    all_names = dataset.Properties.VariableNames;
    vib_cols  = all_names(startsWith(all_names, 'vib_'));
    mcsa_cols = all_names(startsWith(all_names, 'mcsa_'));
    state_cols = {'N_rpm','load_frac','ambient_C','speed_bin','load_bin','ambient_bin'};

    switch feature_set
        case 'vibration'
            feat_names = vib_cols;
        case 'mcsa'
            feat_names = mcsa_cols;
        case 'fusion'
            feat_names = [vib_cols, mcsa_cols];
        case 'fusion_state'
            feat_names = [vib_cols, mcsa_cols, state_cols];
        otherwise
            error('load_dataset_split:unknownFeatureSet', ...
                  'Unknown feature_set: %s', feature_set);
    end

    X = table2array(sub(:, feat_names));
    y = categorical(sub.fault_type);
end
