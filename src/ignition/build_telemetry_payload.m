function payload = build_telemetry_payload(kind, result, history, heartbeat, command_result, icfg)
%BUILD_TELEMETRY_PAYLOAD Assemble the JSON-ready payload sent to Ignition.
%
%   payload = BUILD_TELEMETRY_PAYLOAD(kind, result, history, heartbeat,
%   command_result, icfg)
%
%   kind 'telemetry'  - full payload from the engine 'result' and 'history'
%                       (both returned by run_single_operating_point.m)
%        'heartbeat'  - liveness + last command result only; result and
%                       history are ignored (pass [])
%        'disconnect' - minimal payload sent on clean shutdown
%
%   EVERY value comes straight from the engine result. Nothing is computed,
%   smoothed or substituted here, with two honest conventions:
%     - RUL: if estimate_rul returned NaN (no degrading trend), rulValid is
%       false and rulHours is sent as 0; the HMI must show "N/A" when
%       rulValid is false. RUL is never invented.
%     - rulHistoryPoints is the number of history points behind the RUL, so
%       the HMI can label a short-history RUL as provisional.
%   The injected fault/severity and the AI-predicted fault travel in
%   SEPARATE fields (injectedFault vs predictedFault).
%
%   Throws an error if any numeric field is NaN/Inf, so a faulty result can
%   never be published as if it were valid.
%
%   Outputs:
%     payload - struct; jsonencode-able, all scalars

    % FIELDS-BEGIN
    HEARTBEAT_FIELDS = {'connection','commandResult','heartbeat'};
    TELEMETRY_FIELDS = {'injectedEquipment','injectedFault','predictedFault','severity','vibrationRMS','currentRMS','healthIndex','rulValid','rulHours','rulHistoryPoints','coolingEffectiveness','serverTemperatureC','thermalMarginC','maintenanceState','maintenanceReason','simTimeHours'};
    % FIELDS-END

    payload = struct();
    payload.kind = kind;
    payload.schema = icfg.schema_version;
    payload.tsUtc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));

    switch kind
        case 'disconnect'
            payload.connection = 'DISCONNECTED';
            payload.commandResult = local_text(command_result);
            payload.heartbeat = double(heartbeat);

        case 'heartbeat'
            payload.connection = 'CONNECTED';
            payload.commandResult = local_text(command_result);
            payload.heartbeat = double(heartbeat);

        case 'telemetry'
            payload.connection = 'CONNECTED';
            payload.commandResult = local_text(command_result);
            payload.heartbeat = double(heartbeat);

            payload.injectedEquipment = result.equipment;
            payload.injectedFault = result.fault_type_injected;
            payload.predictedFault = result.predicted_fault_type;
            payload.severity = result.D_injected;
            payload.vibrationRMS = result.vib_features.rms;
            payload.currentRMS = result.mcsa_features.rms;
            payload.healthIndex = result.HI;

            if isfinite(result.RUL_hr)
                payload.rulValid = true;
                payload.rulHours = result.RUL_hr;
            else
                payload.rulValid = false;
                payload.rulHours = 0;
            end
            payload.rulHistoryPoints = numel(history.time_hr);

            payload.coolingEffectiveness = result.cooling_effectiveness;
            payload.serverTemperatureC = result.T_server_inlet_C;
            payload.thermalMarginC = result.thermal_margin_C;
            payload.maintenanceState = result.decision.level;
            payload.maintenanceReason = local_text(result.decision.reasons{1});
            payload.simTimeHours = result.time_hr;

            numeric_fields = {'severity','vibrationRMS','currentRMS','healthIndex','rulHours', ...
                'rulHistoryPoints','coolingEffectiveness','serverTemperatureC', ...
                'thermalMarginC','simTimeHours'};
            for k = 1:numel(numeric_fields)
                v = payload.(numeric_fields{k});
                if ~(isnumeric(v) && isscalar(v) && isfinite(v))
                    error('build_telemetry_payload:nonFinite', ...
                        'Field %s is not a finite number; refusing to publish.', numeric_fields{k});
                end
            end

        otherwise
            error('build_telemetry_payload:badKind', 'Unknown payload kind: %s', kind);
    end
end

% ------------------------------------------------------------------
function t = local_text(v)
%LOCAL_TEXT One-line, length-limited text (the value lands in a tag).
    t = char(string(v));
    t = regexprep(t, '\s+', ' ');
    if numel(t) > 180
        t = [t(1:177) '...'];
    end
end
