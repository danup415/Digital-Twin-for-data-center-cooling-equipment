function effectiveness = cooling_effectiveness_from_degradation(equipment, fault_type, D)
%COOLING_EFFECTIVENESS_FROM_DEGRADATION Fault -> thermal-consequence link (§28).
%
%   effectiveness = COOLING_EFFECTIVENESS_FROM_DEGRADATION(equipment,
%   fault_type, D) returns a multiplier in (0,1] applied to the nominal
%   cooling capacity, implementing the two consequence chains from §28:
%
%     Fan bearing/unbalance/misalignment/efficiency degradation
%       -> airflow reduction -> cooling-capacity reduction
%     Pump cavitation
%       -> chilled-water flow instability/reduction -> cooling-capacity
%          reduction
%
%   Faults with a primarily vibration/current signature but negligible
%   hydraulic effect (Unbalance, BearingDegradation, Misalignment on the
%   PUMP side) get a small residual effectiveness penalty, reflecting
%   that severe mechanical faults are usually addressed (or trip the
%   equipment) before they meaningfully starve the cooling loop —
%   documented as a modeling simplification, not a physical claim.
%
%   Inputs:
%     equipment  - 'Pump' or 'Fan'
%     fault_type - as in cfg.faults.(equipment)
%     D          - severity in [0,1]
%
%   Output:
%     effectiveness - scalar multiplier in (0,1]

    switch equipment
        case 'Pump'
            switch fault_type
                case 'Healthy'
                    effectiveness = 1.0;
                case 'Cavitation'
                    effectiveness = 1 - 0.7*D;    % primary pump->thermal path
                    % (raised from 0.6: at 0.6 even D=1, full cavitation
                    % failure, still left too much effectiveness for the
                    % thermal twin to ever cross T_safe — see the
                    % cooling_time_constant_s comment in model_parameters.m)
                case {'Unbalance','BearingDegradation','Misalignment'}
                    effectiveness = 1 - 0.10*D;   % small residual penalty
                otherwise
                    error('cooling_effectiveness_from_degradation:unknownFault', ...
                          'Unknown pump fault: %s', fault_type);
            end

        case 'Fan'
            switch fault_type
                case 'Healthy'
                    effectiveness = 1.0;
                case 'EfficiencyDegradation'
                    effectiveness = 1 - 0.75*D;   % primary fan->thermal path (airflow loss)
                case {'BearingDegradation','Unbalance','Misalignment'}
                    effectiveness = 1 - 0.15*D;   % moderate airflow impact from vibration faults
                otherwise
                    error('cooling_effectiveness_from_degradation:unknownFault', ...
                          'Unknown fan fault: %s', fault_type);
            end

        otherwise
            error('cooling_effectiveness_from_degradation:unknownEquipment', ...
                  'equipment must be ''Pump'' or ''Fan''');
    end

    effectiveness = max(effectiveness, 0.05);   % floor: never fully zero (avoids div-by-zero downstream)
end
