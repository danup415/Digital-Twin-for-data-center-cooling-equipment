function tables = interactive_code_tables()
%INTERACTIVE_CODE_TABLES Numeric<->name encodings for Simulink signals.
%
%   tables = INTERACTIVE_CODE_TABLES() returns the fixed numeric-code
%   tables used ONLY as a presentation-layer encoding so equipment/fault/
%   decision NAMES (which come unchanged from cfg.faults.Pump,
%   cfg.faults.Fan, and maintenance_decision_engine.m's decision.level)
%   can travel as plain numeric Simulink signals between blocks. No new
%   fault or status names are introduced — every code below maps 1:1 onto
%   a name that already exists in the validated project.
%
%   Both MechanicalAnimation.m and DigitalTwinCoreAndDashboard.m call this
%   function so their encodings can never drift apart.
%
%   tables.equipment      = {'Pump','Fan'}                (code = index)
%   tables.fault          = union of cfg.faults.Pump and cfg.faults.Fan,
%                            in a fixed order (code = index); a fault not
%                            valid for the selected equipment is handled
%                            by the caller, not by this table
%   tables.decision_level = {'NORMAL','MONITOR','WARNING',
%                             'MAINTENANCE_REQUIRED','CRITICAL'} (code = index-1,
%                            matching the 0-based convention already used
%                            in models/Simulink/build_simulink_model.m's
%                            DecisionBlock, kept identical here for
%                            consistency across the two Simulink models)

    tables.equipment = {'Pump', 'Fan'};

    % Fixed union of both equipment's fault lists (cfg.faults.Pump union
    % cfg.faults.Fan), in a stable order. Verified against
    % config/project_config.m at authoring time:
    %   cfg.faults.Pump = {'Healthy','Cavitation','Unbalance','BearingDegradation','Misalignment'}
    %   cfg.faults.Fan  = {'Healthy','BearingDegradation','Unbalance','Misalignment','EfficiencyDegradation'}
    tables.fault = {'Healthy', 'Cavitation', 'Unbalance', 'BearingDegradation', ...
                     'Misalignment', 'EfficiencyDegradation'};

    tables.decision_level = {'NORMAL', 'MONITOR', 'WARNING', ...
                               'MAINTENANCE_REQUIRED', 'CRITICAL'};
end
