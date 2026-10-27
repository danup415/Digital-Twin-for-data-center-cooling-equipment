function decision = maintenance_decision_engine(fault_prob, severity, HI, RUL, thermal_margin_C, T)
%MAINTENANCE_DECISION_ENGINE Combine diagnosis, health, RUL and thermal
%   margin into one maintenance decision (§29).
%
%   decision = MAINTENANCE_DECISION_ENGINE(fault_prob, severity, HI, RUL,
%   thermal_margin_C, T) evaluates each input against the thresholds in T
%   (from get_maintenance_thresholds) and returns the WORST (most urgent)
%   of the per-signal verdicts, so a single severely-degraded signal can't
%   be masked by otherwise-healthy readings — the whole point of a
%   predictive system is to escalate on the earliest sign of trouble.
%
%   Signals considered:
%     HI                - Health Index, thresholds: HI_warning /
%                         HI_maintenance / HI_critical (lower = worse)
%     RUL                - remaining useful life in hours; NaN is treated
%                         as "no trend yet" (does not escalate on its own)
%     thermal_margin_C  - T_safe - T_server_inlet; thresholds:
%                         thermal_margin_warning_C / _critical_C (lower =
%                         worse, negative = threshold already violated)
%     fault_prob, severity - included in the returned struct for
%                         reporting/logging but do not independently
%                         drive the level in this baseline version
%                         (they are captured in HI, which already
%                         aggregates severity per compute_health_index.m)
%
%   Inputs:
%     fault_prob, severity, HI, RUL, thermal_margin_C - scalars
%     T - struct from get_maintenance_thresholds()
%
%   Output struct 'decision':
%     level    - one of 'NORMAL','MONITOR','WARNING','MAINTENANCE_REQUIRED','CRITICAL'
%     reasons  - cellstr explaining which signal(s) drove the level
%     inputs   - echo of the inputs, for logging/report tables

    levels_order = {'NORMAL','MONITOR','WARNING','MAINTENANCE_REQUIRED','CRITICAL'};
    level_rank = containers.Map(levels_order, 1:numel(levels_order));

    current_level = 'NORMAL';
    reasons = {};

    % ---- Health Index signal ----
    if HI <= T.HI_critical
        current_level = local_escalate(current_level, 'CRITICAL', level_rank);
        reasons{end+1} = sprintf('Health Index %.1f <= critical threshold %.1f', HI, T.HI_critical);
    elseif HI <= T.HI_maintenance
        current_level = local_escalate(current_level, 'MAINTENANCE_REQUIRED', level_rank);
        reasons{end+1} = sprintf('Health Index %.1f <= maintenance threshold %.1f', HI, T.HI_maintenance);
    elseif HI <= T.HI_warning
        current_level = local_escalate(current_level, 'WARNING', level_rank);
        reasons{end+1} = sprintf('Health Index %.1f <= warning threshold %.1f', HI, T.HI_warning);
    end

    % ---- RUL signal (only escalates if a trend exists, i.e. not NaN) ----
    if ~isnan(RUL)
        if RUL <= T.RUL_maintenance_hours
            current_level = local_escalate(current_level, 'MAINTENANCE_REQUIRED', level_rank);
            reasons{end+1} = sprintf('RUL %.1f h <= maintenance threshold %.1f h', RUL, T.RUL_maintenance_hours);
        elseif RUL <= T.RUL_warning_hours
            current_level = local_escalate(current_level, 'WARNING', level_rank);
            reasons{end+1} = sprintf('RUL %.1f h <= warning threshold %.1f h', RUL, T.RUL_warning_hours);
        end
    end

    % ---- Thermal margin signal ----
    if thermal_margin_C <= T.thermal_margin_critical_C
        current_level = local_escalate(current_level, 'CRITICAL', level_rank);
        reasons{end+1} = sprintf('Thermal margin %.2f C <= critical threshold %.2f C', ...
            thermal_margin_C, T.thermal_margin_critical_C);
    elseif thermal_margin_C <= T.thermal_margin_warning_C
        current_level = local_escalate(current_level, 'WARNING', level_rank);
        reasons{end+1} = sprintf('Thermal margin %.2f C <= warning threshold %.2f C', ...
            thermal_margin_C, T.thermal_margin_warning_C);
    end

    if isempty(reasons)
        reasons = {'All signals within normal bounds.'};
    end

    decision.level   = current_level;
    decision.reasons = reasons;
    decision.inputs  = struct('fault_prob', fault_prob, 'severity', severity, ...
                                'HI', HI, 'RUL', RUL, 'thermal_margin_C', thermal_margin_C);
end

% ------------------------------------------------------------------
function new_level = local_escalate(current_level, candidate_level, level_rank)
%LOCAL_ESCALATE Return whichever level is more urgent (higher rank).
    if level_rank(candidate_level) > level_rank(current_level)
        new_level = candidate_level;
    else
        new_level = current_level;
    end
end
