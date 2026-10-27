function [ok, clean, reason] = validate_ignition_command(raw, cfg, icfg)
%VALIDATE_IGNITION_COMMAND Validate a command decoded from the Gateway.
%
%   [ok, clean, reason] = VALIDATE_IGNITION_COMMAND(raw, cfg, icfg)
%   checks the struct 'raw' (from jsondecode of the 'commands' endpoint)
%   against the project's own configuration and returns a normalized
%   'clean' struct only if EVERYTHING passes. Nothing else in the adapter
%   ever sees an unvalidated command.
%
%   Rules (all from project config; nothing invented):
%     equipment    in cfg.equipment
%     faultType    exact label in cfg.faults.(equipment) (case-sensitive; a
%                  label belonging only to the OTHER equipment is rejected)
%     severity     real finite number in [0, 1]; must be 0 for 'Healthy'
%                  (compute_health_index uses D directly, so a "Healthy"
%                  fault with D>0 would show a falling Health Index)
%     rpm          within cfg.operating.speed_rpm_range
%     loadFraction within cfg.operating.load_pct_range / 100
%     ambientC     within cfg.operating.ambient_C_range
%     itLoadKW     within icfg.it_load_range_kW
%     run          logical, or numeric 0/1
%     resetSeq     non-negative integer
%   Wrong types (text where a number is expected, logicals as numbers,
%   NaN/Inf, vectors) are rejected.
%
%   Outputs:
%     ok     - true only if every rule passed
%     clean  - struct with the same field names, normalized types
%              (empty struct when ok is false)
%     reason - '' when ok, otherwise a one-line explanation of the failure(s)

    clean = struct();

    % CMD-FIELDS-BEGIN
    required = {'equipment','faultType','severity','rpm','loadFraction','ambientC','itLoadKW','run','resetSeq'};
    % CMD-FIELDS-END

    if ~isstruct(raw) || ~isscalar(raw)
        ok = false;
        reason = 'command is not a single struct';
        return;
    end
    missing = required(~isfield(raw, required));
    if ~isempty(missing)
        ok = false;
        reason = ['missing field(s): ' strjoin(missing, ', ')];
        return;
    end

    problems = {};

    equipment = local_text(raw.equipment);
    equipment_ok = any(strcmp(equipment, cfg.equipment));
    if ~equipment_ok
        problems{end+1} = sprintf('equipment must be one of {%s}', strjoin(cfg.equipment, ', '));
    end

    faultType = local_text(raw.faultType);
    fault_ok = false;
    if equipment_ok
        valid_faults = cfg.faults.(equipment);
        fault_ok = any(strcmp(faultType, valid_faults));
        if ~fault_ok
            problems{end+1} = sprintf('faultType must be one of {%s} for %s', ...
                strjoin(valid_faults, ', '), equipment);
        end
    end

    severity = local_number(raw.severity);
    if isnan(severity) || severity < 0 || severity > 1
        problems{end+1} = 'severity must be a number in [0, 1]';
    elseif fault_ok && strcmp(faultType, 'Healthy') && severity ~= 0
        problems{end+1} = 'severity must be 0 when faultType is Healthy';
    end

    rpm = local_number(raw.rpm);
    r = cfg.operating.speed_rpm_range;
    if isnan(rpm) || rpm < r(1) || rpm > r(2)
        problems{end+1} = sprintf('rpm must be a number in [%g, %g]', r(1), r(2));
    end

    loadFraction = local_number(raw.loadFraction);
    lr = cfg.operating.load_pct_range / 100;
    if isnan(loadFraction) || loadFraction < lr(1) || loadFraction > lr(2)
        problems{end+1} = sprintf('loadFraction must be a number in [%g, %g]', lr(1), lr(2));
    end

    ambientC = local_number(raw.ambientC);
    ar = cfg.operating.ambient_C_range;
    if isnan(ambientC) || ambientC < ar(1) || ambientC > ar(2)
        problems{end+1} = sprintf('ambientC must be a number in [%g, %g]', ar(1), ar(2));
    end

    itLoadKW = local_number(raw.itLoadKW);
    ir = icfg.it_load_range_kW;
    if isnan(itLoadKW) || itLoadKW < ir(1) || itLoadKW > ir(2)
        problems{end+1} = sprintf('itLoadKW must be a number in [%g, %g]', ir(1), ir(2));
    end

    [run_ok, run_flag] = local_flag(raw.run);
    if ~run_ok
        problems{end+1} = 'run must be true/false (or 0/1)';
    end

    resetSeq = local_number(raw.resetSeq);
    if isnan(resetSeq) || resetSeq < 0 || resetSeq ~= round(resetSeq)
        problems{end+1} = 'resetSeq must be a non-negative integer';
    end

    if ~isempty(problems)
        ok = false;
        reason = strjoin(problems, '; ');
        return;
    end

    ok = true;
    reason = '';
    clean.equipment = equipment;
    clean.faultType = faultType;
    clean.severity = severity;
    clean.rpm = rpm;
    clean.loadFraction = loadFraction;
    clean.ambientC = ambientC;
    clean.itLoadKW = itLoadKW;
    clean.run = run_flag;
    clean.resetSeq = resetSeq;
end

% ------------------------------------------------------------------
function t = local_text(v)
%LOCAL_TEXT Return v as a char row if it is text, else '' (never errors).
    if ischar(v) && (isrow(v) || isempty(v))
        t = v;
    elseif isstring(v) && isscalar(v)
        t = char(v);
    else
        t = '';
    end
end

% ------------------------------------------------------------------
function x = local_number(v)
%LOCAL_NUMBER Return v as a double if it is a real finite numeric scalar
%   (logicals and text are NOT numbers here), else NaN.
    if isnumeric(v) && isscalar(v) && isreal(v) && isfinite(v)
        x = double(v);
    else
        x = NaN;
    end
end

% ------------------------------------------------------------------
function [ok, flag] = local_flag(v)
    ok = false;
    flag = false;
    if islogical(v) && isscalar(v)
        ok = true;
        flag = v;
    elseif isnumeric(v) && isscalar(v) && isreal(v) && (v == 0 || v == 1)
        ok = true;
        flag = (v == 1);
    end
end
