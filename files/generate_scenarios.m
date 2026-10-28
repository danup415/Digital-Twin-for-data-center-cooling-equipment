function scenarios = generate_scenarios(cfg, n_repeats_per_combo)
%GENERATE_SCENARIOS Build the scenario table driving dataset generation.
%
%   scenarios = GENERATE_SCENARIOS(cfg, n_repeats_per_combo) enumerates
%   every (equipment, fault_type, severity_label) combination from cfg
%   and draws n_repeats_per_combo randomized operating-condition scenarios
%   for each, per §22.
%
%   CRITICAL (§23, data-leakage avoidance): the Train/Val/Test split is
%   assigned HERE, at the scenario level, before any signal or feature is
%   generated. A scenario's samples/windows never get split across two
%   partitions. A dedicated "unseen operating condition" slice is carved
%   out into Test only, to support the generalization experiment (§23,
%   Experiment 10).
%
%   Inputs:
%     cfg                  - struct from project_config()
%     n_repeats_per_combo  - number of randomized scenarios to draw per
%                             (equipment, fault, severity) combination
%
%   Output:
%     scenarios - table with columns:
%       scenario_id, equipment, fault_type, severity_label, severity_D,
%       N_rpm, load_frac, ambient_C, split, is_unseen_condition

    if nargin < 2
        n_repeats_per_combo = 6;
    end

    rng(cfg.seed);   % reproducibility (§43)

    rows = {};
    scenario_id = 0;

    for eq_idx = 1:numel(cfg.equipment)
        equipment = cfg.equipment{eq_idx};
        fault_list = cfg.faults.(equipment);

        for f_idx = 1:numel(fault_list)
            fault_type = fault_list{f_idx};

            for s_idx = 1:numel(cfg.severity_labels)
                severity_label = cfg.severity_labels{s_idx};
                severity_D = cfg.severity_values(s_idx);

                % Healthy scenarios only make sense at D=0; skip the
                % non-zero severity labels for the Healthy fault type.
                if strcmp(fault_type, 'Healthy') && severity_D > 0
                    continue;
                end
                % Conversely, a non-Healthy fault type at D=0 produces a
                % signal that is physically indistinguishable from Healthy
                % (apply_pump_fault/apply_fan_fault with D=0 changes
                % nothing) — but would still carry the fault's label,
                % which is pure label noise for the classifier. Skip it.
                if ~strcmp(fault_type, 'Healthy') && severity_D == 0
                    continue;
                end

                for r = 1:n_repeats_per_combo
                    scenario_id = scenario_id + 1;

                    % Most repeats sample the "known" speed band; a
                    % dedicated fraction samples the unseen band and is
                    % forced into Test (generalization experiment, §23).
                    is_unseen = (r == n_repeats_per_combo);   % last repeat per combo
                    if is_unseen
                        N_rpm = local_rand_in(cfg.operating.unseen_speed_rpm_range);
                        split = "Test";
                    else
                        N_rpm = local_rand_in(cfg.operating.known_speed_rpm_range);
                        split = local_assign_split(r, n_repeats_per_combo);
                    end

                    load_frac = local_rand_in(cfg.operating.load_pct_range) / 100;
                    ambient_C = local_rand_in(cfg.operating.ambient_C_range);

                    rows(end+1, :) = { scenario_id, string(equipment), string(fault_type), ...
                        string(severity_label), severity_D, N_rpm, load_frac, ambient_C, ...
                        string(split), is_unseen }; %#ok<AGROW>
                end
            end
        end
    end

    scenarios = cell2table(rows, 'VariableNames', ...
        {'scenario_id','equipment','fault_type','severity_label','severity_D', ...
         'N_rpm','load_frac','ambient_C','split','is_unseen_condition'});
end

% ------------------------------------------------------------------
function v = local_rand_in(range2)
    v = range2(1) + (range2(2)-range2(1)) * rand();
end

% ------------------------------------------------------------------
function split = local_assign_split(r, n_total)
%LOCAL_ASSIGN_SPLIT Roughly 60/20/20 Train/Val/Test across the "known"
%   repeats (the unseen-condition repeat is handled separately by the
%   caller and always goes to Test).
    frac = r / max(n_total - 1, 1);
    if frac <= 0.6
        split = 'Train';
    elseif frac <= 0.8
        split = 'Val';
    else
        split = 'Test';
    end
end
