function [degraded, sigparams] = apply_fan_fault(faultType, D, baseline, P)
%APPLY_FAN_FAULT Severity-parameterized CRAC fan fault injection.
%
%   Mirrors APPLY_PUMP_FAULT. Fault set (§6-§7):
%     BearingDegradation    - impulsive vibration at BPFO/BPFI/BSF, small
%                             efficiency loss from added friction.
%     Unbalance              - rotating eccentric mass, strong 1X vibration.
%     Misalignment            - shaft offset, 1X+2X vibration.
%     EfficiencyDegradation  - fouling/blade wear: airflow drops at
%                             constant power with almost no vibration
%                             signature — deliberately the "quiet" fault
%                             used to stress-test vibration-only models
%                             (§D of docs/architecture.md).
%
%   sigparams fields are always present (zeroed if inactive):
%     unbalance_U, bearing_D, misalignment_M, efficiency_D

    degraded = baseline;
    sigparams = struct('unbalance_U', 0, 'bearing_D', 0, ...
                        'misalignment_M', 0, 'efficiency_D', 0);

    switch faultType
        case 'Healthy'
            % no change

        case 'BearingDegradation'
            Db = D;
            degraded.eta = baseline.eta * (1 - 0.05*Db);
            sigparams.bearing_D = Db;

        case 'Unbalance'
            U = D;
            degraded.eta = baseline.eta * (1 - 0.05*U);
            sigparams.unbalance_U = U;

        case 'Misalignment'
            M = D;
            degraded.eta = baseline.eta * (1 - 0.10*M);
            sigparams.misalignment_M = M;

        case 'EfficiencyDegradation'
            E = D;
            % Fouling/blade wear: airflow and efficiency drop directly,
            % with essentially no added vibration energy.
            degraded.eta     = baseline.eta * (1 - 0.40*E);
            degraded.Q_m3ps  = baseline.Q_m3ps * (1 - 0.35*E);
            sigparams.efficiency_D = E;

        otherwise
            error('apply_fan_fault:unknownFault', 'Unknown fan fault type: %s', faultType);
    end

    hydraulic_kW   = (degraded.Q_m3ps * degraded.dP_Pa) / 1000;
    degraded.P_shaft_kW = hydraulic_kW / max(degraded.eta, 1e-3);

    if isfield(degraded, 'torque_Nm')
        degraded.torque_Nm = degraded.torque_Nm * (degraded.P_shaft_kW / max(baseline.P_shaft_kW, 1e-6));
    end
end
