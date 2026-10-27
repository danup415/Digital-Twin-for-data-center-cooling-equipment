classdef DigitalTwinCoreAndDashboard < matlab.System
    %DIGITALTWINCOREANDDASHBOARD Slow-rate AI/health/thermal core + display.
    %
    %   A Simulink "MATLAB System" block that, once per supervisory tick,
    %   calls src/interactive/run_single_operating_point.m — the SAME
    %   already-tested function the MATLAB dashboard app uses — and
    %   through it, literally the project's existing pump_model.m,
    %   fan_model.m, motor_model.m, apply_pump_fault.m, apply_fan_fault.m,
    %   bearing_fault_frequencies.m, generate_vibration_signal.m,
    %   generate_current_signal.m, condition_vibration_signal.m,
    %   condition_current_signal.m, extract_vibration_features.m,
    %   extract_mcsa_features.m, predict_model.m, compute_health_index.m,
    %   estimate_rul.m, cooling_effectiveness_from_degradation.m,
    %   thermal_digital_twin.m, and maintenance_decision_engine.m. NONE OF
    %   THEIR EQUATIONS ARE RE-EXPRESSED OR DUPLICATED HERE — this is a
    %   literal function call, made possible because MATLAB System blocks
    %   run interpreted (unlike MATLAB Function blocks, which are
    %   code-generation-restricted and cannot call struct/table/
    %   string-returning functions like these).
    %
    %   Runs at a SLOW supervisory rate (SampleTime property, default 2
    %   real seconds per tick = SupervisoryTickHours simulated hours per
    %   tick, default 1) — matching the hours-scale semantics the RUL/
    %   thermal-trend math already uses elsewhere in this project (see
    %   docs/architecture.md §H), decoupled from the fast mechanical
    %   animation rate via a Rate Transition block in the model.
    %
    %   Also renders its own figure each tick: a text status panel
    %   (§10 of the interactive-twin brief), the vibration and current
    %   waveforms + FFTs for the CURRENT tick (from result.signals — the
    %   real synthesized signals, not placeholders), and 6 trend plots
    %   (Health Index, RUL, temperature, thermal margin, cooling
    %   effectiveness, degradation D, all vs time) built from the running
    %   history buffer run_single_operating_point.m itself maintains.
    %   Rendering happens here (not via Simulink Scope/Dashboard blocks)
    %   because several of these need real TEXT (fault names, AI
    %   prediction, status), which Simulink's native numeric-gauge
    %   Dashboard blocks do not display — this sidesteps that limitation
    %   entirely rather than depending on whichever Dashboard blocks
    %   happen to be available.
    %
    %   Inputs (all slow-rate Simulink signals, all numeric — decoded via
    %   src/interactive/interactive_code_tables.m so no new fault/status
    %   names are introduced):
    %     equipmentCode  - 1=Pump, 2=Fan
    %     faultCode      - index into tables.fault (validated against the
    %                      selected equipment's REAL cfg.faults list; an
    %                      invalid combination — e.g. Pump + Efficiency
    %                      Degradation — falls back to Healthy, with a
    %                      one-time warning, rather than erroring out a
    %                      live demo)
    %     D              - severity [0,1]
    %     N_rpm, load_frac (0-1), ambient_C, IT_load_kW - operating point
    %
    %   Outputs (numeric, so an optional Scope/Dashboard gauge can also
    %   use them even though the figure above is the primary display):
    %     HI, RUL_hr (-1 sentinel for "no trend yet", documented — NEVER
    %     a fabricated number), T_server, margin, coolEff, decisionCode
    %     (0-based per interactive_code_tables.m), predictedCode

    properties (Nontunable)
        SampleTime (1,1) double = 2.0          % real seconds per supervisory tick
        SupervisoryTickHours (1,1) double = 1.0 % simulated hours per tick
        FeatureSet (1,:) char = 'fusion_state'
    end

    properties (Access = private)
        cfg
        SensorConfig
        P
        T_thresh
        model
        history = []
        tables
        warned_invalid_combo = false
        Figure
        AxStatus
        StatusTextHandles
        AxVibWave
        AxVibFFT
        AxCurWave
        AxMCSA
        AxHI
        AxRUL
        AxTemp
        AxMargin
        AxCoolEff
        AxD
    end

    methods (Access = protected)
        function setupImpl(obj)
            obj.cfg = project_config();
            obj.SensorConfig = sensor_config();
            obj.P = model_parameters();
            obj.T_thresh = get_maintenance_thresholds();
            [obj.model, ~] = load_or_train_model(obj.FeatureSet);
            obj.history = [];
            obj.tables = interactive_code_tables();

            obj.Figure = figure('Name', 'Cooling Digital Twin — AI / Health / Thermal', ...
                'NumberTitle', 'off', 'Position', [1000, 80, 800, 820]);

            g = tiledlayout(obj.Figure, 5, 2);

            obj.AxStatus = nexttile(g, 1, [1 2]);
            axis(obj.AxStatus, 'off');
            obj.StatusTextHandles = text(obj.AxStatus, 0.02, 0.5, '', ...
                'FontName', 'FixedWidth', 'FontSize', 10, 'VerticalAlignment', 'middle');

            obj.AxVibWave = nexttile(g); title(obj.AxVibWave, 'Vibration waveform');
            obj.AxVibFFT  = nexttile(g); title(obj.AxVibFFT, 'Vibration FFT');
            obj.AxCurWave = nexttile(g); title(obj.AxCurWave, 'Current waveform');
            obj.AxMCSA    = nexttile(g); title(obj.AxMCSA, 'MCSA spectrum');
            obj.AxHI      = nexttile(g); title(obj.AxHI, 'Health Index vs time');
            obj.AxRUL     = nexttile(g); title(obj.AxRUL, 'RUL vs time');
            obj.AxTemp    = nexttile(g); title(obj.AxTemp, 'Server temperature vs time');
            obj.AxMargin  = nexttile(g); title(obj.AxMargin, 'Thermal margin vs time');
        end

        function [HI, RUL_hr, T_server, margin, coolEff, decisionCode, predictedCode] = ...
                stepImpl(obj, equipmentCode, faultCode, D, N_rpm, load_frac, ambient_C, IT_load_kW)

            equipment = obj.tables.equipment{round(equipmentCode)};
            faultType = obj.tables.fault{round(faultCode)};

            if ~ismember(faultType, obj.cfg.faults.(equipment))
                if ~obj.warned_invalid_combo
                    warning('DigitalTwinCoreAndDashboard:invalidCombo', ...
                        ['%s is not a valid fault for %s (real fault list: %s) — ', ...
                         'falling back to Healthy for this combination. This warning ', ...
                         'prints once per simulation.'], ...
                        faultType, equipment, strjoin(obj.cfg.faults.(equipment), ', '));
                    obj.warned_invalid_combo = true;
                end
                faultType = 'Healthy';
            end

            [result, obj.history] = run_single_operating_point(equipment, faultType, D, ...
                N_rpm, load_frac, ambient_C, IT_load_kW, obj.model, obj.history, ...
                obj.cfg, obj.SensorConfig, obj.P, obj.T_thresh, obj.SupervisoryTickHours);

            HI = result.HI;
            if isnan(result.RUL_hr)
                RUL_hr = -1;   % sentinel: "no degrading trend yet" — see docstring
            else
                RUL_hr = result.RUL_hr;
            end
            T_server = result.T_server_inlet_C;
            margin = result.thermal_margin_C;
            coolEff = result.cooling_effectiveness;
            decisionCode = find(strcmp(obj.tables.decision_level, result.decision.level)) - 1;
            predictedCode = find(strcmp(obj.tables.fault, result.predicted_fault_type));

            if isvalid(obj.Figure)
                obj.renderDashboard(result);
            end
        end

        function resetImpl(obj)
            obj.history = [];
            obj.warned_invalid_combo = false;
        end

        function releaseImpl(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                close(obj.Figure);
            end
        end

        function st = getSampleTimeImpl(obj)
            st = createSampleTime(obj, 'Type', 'Discrete', 'SampleTime', obj.SampleTime);
        end

        function num = getNumInputsImpl(~)
            num = 7;
        end

        function num = getNumOutputsImpl(~)
            num = 7;
        end

        function [sz1,sz2,sz3,sz4,sz5,sz6,sz7] = getOutputSizeImpl(~)
            sz1=[1 1]; sz2=[1 1]; sz3=[1 1]; sz4=[1 1]; sz5=[1 1]; sz6=[1 1]; sz7=[1 1];
        end

        function [dt1,dt2,dt3,dt4,dt5,dt6,dt7] = getOutputDataTypeImpl(~)
            dt1='double'; dt2='double'; dt3='double'; dt4='double';
            dt5='double'; dt6='double'; dt7='double';
        end

        function [c1,c2,c3,c4,c5,c6,c7] = isOutputComplexImpl(~)
            c1=false; c2=false; c3=false; c4=false; c5=false; c6=false; c7=false;
        end

        function [f1,f2,f3,f4,f5,f6,f7] = isOutputFixedSizeImpl(~)
            f1=true; f2=true; f3=true; f4=true; f5=true; f6=true; f7=true;
        end
    end

    methods (Access = private)
        function renderDashboard(obj, result)
            statusLines = { ...
                sprintf('SYSTEM STATUS: %s', result.decision.level), ...
                sprintf('Equipment: %-6s   Injected fault: %-22s   Severity: %5.1f%%', ...
                    result.equipment, result.fault_type_injected, result.D_injected*100), ...
                sprintf('AI predicted fault: %-22s', result.predicted_fault_type), ...
                sprintf('Health Index: %6.1f     RUL: %-14s', result.HI, local_fmt_rul(result.RUL_hr)), ...
                sprintf('Server temperature: %6.2f C   Thermal margin: %6.2f C', ...
                    result.T_server_inlet_C, result.thermal_margin_C), ...
                sprintf('Cooling effectiveness: %5.2f', result.cooling_effectiveness) ...
            };
            set(obj.StatusTextHandles, 'String', strjoin(statusLines, newline));

            Fs_acc = result.signals.Fs_acc;
            Fs_cur = result.signals.Fs_cur;

            plot(obj.AxVibWave, result.signals.vib_time, result.signals.vib_signal);
            title(obj.AxVibWave, 'Vibration waveform');

            [f_v, X_v] = local_fft_for_display(result.signals.vib_signal, Fs_acc);
            plot(obj.AxVibFFT, f_v, X_v); xlim(obj.AxVibFFT, [0, min(2000, Fs_acc/2)]);
            title(obj.AxVibFFT, 'Vibration FFT');

            plot(obj.AxCurWave, result.signals.current_time, result.signals.current_signal);
            title(obj.AxCurWave, 'Current waveform');

            [f_c, X_c] = local_fft_for_display(result.signals.current_signal, Fs_cur);
            plot(obj.AxMCSA, f_c, X_c); xlim(obj.AxMCSA, [0, 500]);
            title(obj.AxMCSA, 'MCSA spectrum');

            h = obj.history;
            plot(obj.AxHI, h.time_hr, h.HI, '-o'); title(obj.AxHI, 'Health Index vs time');

            rul_trend = local_rul_trend_from_history(h, obj.P.Health);
            plot(obj.AxRUL, h.time_hr, rul_trend, '-o'); title(obj.AxRUL, 'RUL vs time');

            tt = result.thermal_trajectory;
            plot(obj.AxTemp, tt.time/3600, tt.T_server_inlet_C, '-o');
            title(obj.AxTemp, 'Server temperature vs time');

            plot(obj.AxMargin, tt.time/3600, tt.thermal_margin_C, '-o');
            title(obj.AxMargin, 'Thermal margin vs time');

            drawnow limitrate;
        end
    end
end

% ======================================================================
% Local (file-scope) helper functions — presentation-only, see class docstring
% ======================================================================
function txt = local_fmt_rul(rul_hr)
    if isnan(rul_hr)
        txt = 'N/A (no trend)';
    else
        txt = sprintf('%.1f h', rul_hr);
    end
end

function [f, X] = local_fft_for_display(x, Fs)
    n = numel(x);
    X = abs(fft(x));
    X = X(1:floor(n/2)+1);
    f = (0:floor(n/2))' * (Fs/n);
end

function rul_trend = local_rul_trend_from_history(history, HealthP)
%LOCAL_RUL_TREND_FROM_HISTORY Same pattern as app/CoolingDigitalTwinApp.m's
%   helper of the same purpose: calls the project's own estimate_rul.m
%   over a 5-sample sliding window (matching
%   simulate_degradation_trajectory.m / Experiments 4/5/9) purely to give
%   the "RUL vs time" plot more than one point.
    n = numel(history.time_hr);
    rul_trend = nan(n, 1);
    rul_window = 5;
    for k = 1:n
        w_start = max(1, k - rul_window + 1);
        r = estimate_rul(history.time_hr(w_start:k), history.HI(w_start:k), HealthP);
        rul_trend(k) = r.RUL;
    end
end
