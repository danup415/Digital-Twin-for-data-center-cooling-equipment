function [degraded, sigparams] = apply_pump_fault(faultType, D, baseline, P)
%APPLY_PUMP_FAULT Severity-parameterized pump fault injection.
%
%   [degraded, sigparams] = APPLY_PUMP_FAULT(faultType, D, baseline, P)
%   takes the healthy operating point 'baseline' (from pump_model) and a
%   normalized severity D in [0,1] and returns:
%     degraded  - hydraulic operating point with the fault's physical
%                 effect applied (§6-§7: every fault must act through the
%                 shared degradation variable D, never an arbitrary
%                 sensor-only change)
%     sigparams - struct of per-fault severities consumed by the
%                 vibration/current signal generators (Phase 4), with all
%                 fields always present (zeroed if not the active fault)
%                 so downstream code has a fixed shape regardless of
%                 faultType.
%
%   Fault-specific mechanisms (documented rationale):
%     Cavitation         - NPSH-margin loss: reduces flow, head and
%                           efficiency (vapor pockets disrupt the flow
%                           passage); drives broadband HF vibration.
%     Unbalance           - rotating eccentric mass; negligible hydraulic
%                           effect, strong 1X vibration + current sideband.
%     BearingDegradation - added mechanical friction; small efficiency
%                           loss, strong impulsive vibration at BPFO/BPFI/BSF.
%     Misalignment        - shaft/coupling offset; moderate efficiency
%                           loss, 1X+2X vibration with axial component.

    degraded = baseline;
    sigparams = struct('cavitation_C', 0, 'unbalance_U', 0, ...
                        'bearing_D', 0, 'misalignment_M', 0);

    switch faultType
        case 'Healthy'
            % no change

        case 'Cavitation'
            C = D;
            degraded.eta    = baseline.eta * (1 - 0.50*C);
            degraded.Q_Lps  = baseline.Q_Lps * (1 - 0.30*C);
            degraded.dP_kPa = baseline.dP_kPa * (1 - 0.20*C);
            sigparams.cavitation_C = C;

        case 'Unbalance'
            U = D;
            degraded.eta = baseline.eta * (1 - 0.05*U);   % mostly a vibration fault
            sigparams.unbalance_U = U;

        case 'BearingDegradation'
            Db = D;
            degraded.eta = baseline.eta * (1 - 0.05*Db);  % added friction losses
            sigparams.bearing_D = Db;

        case 'Misalignment'
            M = D;
            degraded.eta = baseline.eta * (1 - 0.10*M);
            sigparams.misalignment_M = M;

        otherwise
            error('apply_pump_fault:unknownFault', 'Unknown pump fault type: %s', faultType);
    end

    % Recompute shaft power / torque consistently with any eta/Q/dP change.
    Q_m3ps = degraded.Q_Lps / 1000;
    dP_Pa  = degraded.dP_kPa * 1000;
    hydraulic_kW = (Q_m3ps * dP_Pa) / 1000;
    degraded.P_shaft_kW = hydraulic_kW / max(degraded.eta, 1e-3);

    if isfield(degraded, 'torque_Nm')
        % torque recomputed by caller via motor_model once N_rpm is known;
        % kept here only as a placeholder consistent with baseline shape.
        degraded.torque_Nm = degraded.torque_Nm * (degraded.P_shaft_kW / max(baseline.P_shaft_kW, 1e-6));
    end
end
