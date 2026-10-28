classdef CoolingDigitalTwinApp < handle
%COOLINGDIGITALTWINAPP Interactive AI-enabled digital twin dashboard.
%
%   Launch with launch_cooling_digital_twin (or app = CoolingDigitalTwinApp()).
%
%   IMPLEMENTATION NOTE: this is a hand-authored classdef, not a binary
%   App Designer .mlapp file — a plain .m class is text-diffable and
%   reviewable like every other file in this project, and behaves
%   identically to a launched App Designer app (uifigure + callbacks);
%   the .mlapp binary format cannot be produced outside App Designer
%   itself. If you prefer, this class can be opened directly in App
%   Designer to convert it, but that is not required to run it.
%
%   THIS CLASS CONTAINS NO PHYSICS, AI, HEALTH, RUL, THERMAL, OR DECISION
%   LOGIC. Every simulated result comes from run_single_operating_point.m
%   (Phase A, already tested in Phase B). This class only: builds UI
%   controls, reads their current values, calls that one backend
%   function, and plots what it returns. The two exceptions — computing
%   an FFT for the waveform plots, and re-running estimate_rul.m over
%   sliding windows of the ALREADY-COMPUTED history for the "RUL vs time"
%   plot — are presentation-layer only: the FFT is a display transform of
%   a real signal already returned by the backend, and the RUL-trend
%   helper calls the project's own existing estimate_rul.m function
%   (never reimplemented) the same way simulate_degradation_trajectory.m
%   and Experiments 4/5/9 already do (5-sample sliding window).

    properties (Access = public)
        UIFigure matlab.ui.Figure
    end

    properties (Access = private)
        % ---- Controls: operating conditions ----
        ITLoadSlider        matlab.ui.control.Slider
        ITLoadLabel         matlab.ui.control.Label
        AmbientSlider       matlab.ui.control.Slider
        AmbientLabel        matlab.ui.control.Label
        RPMSlider           matlab.ui.control.Slider
        RPMLabel            matlab.ui.control.Label
        LoadFracSlider      matlab.ui.control.Slider
        LoadFracLabel       matlab.ui.control.Label

        % ---- Controls: fault configuration ----
        EquipmentDropDown   matlab.ui.control.DropDown
        FaultTypeDropDown   matlab.ui.control.DropDown
        SeveritySlider      matlab.ui.control.Slider
        SeverityLabel       matlab.ui.control.Label

        % ---- Controls: sensor conditions ----
        VibNoiseSlider      matlab.ui.control.Slider
        CurNoiseSlider      matlab.ui.control.Slider

        % ---- Controls: simulation ----
        SweepStepsField     matlab.ui.control.NumericEditField
        RunButton           matlab.ui.control.Button
        SweepButton         matlab.ui.control.Button
        ResetButton         matlab.ui.control.Button
        HealthyButton        matlab.ui.control.Button
        StopButton          matlab.ui.control.Button

        % ---- Status readouts ----
        StatusValueLabel     matlab.ui.control.Label
        EquipmentValueLabel  matlab.ui.control.Label
        FaultValueLabel      matlab.ui.control.Label
        SeverityValueLabel   matlab.ui.control.Label
        PredictedValueLabel  matlab.ui.control.Label
        HIValueLabel         matlab.ui.control.Label
        RULValueLabel        matlab.ui.control.Label
        TempValueLabel       matlab.ui.control.Label
        MarginValueLabel     matlab.ui.control.Label
        CoolEffValueLabel    matlab.ui.control.Label
        MaintValueLabel      matlab.ui.control.Label

        % ---- Phase 6 status indicators (colored labels; every color is
        % set from an actual model variable, never decorative) ----
        PumpStatusLabel      matlab.ui.control.Label
        FanStatusLabel       matlab.ui.control.Label
        CoolingStatusLabel   matlab.ui.control.Label
        ThermalStatusLabel   matlab.ui.control.Label

        % ---- Plot axes ----
        AxVibWave  matlab.ui.control.UIAxes
        AxVibFFT   matlab.ui.control.UIAxes
        AxCurWave  matlab.ui.control.UIAxes
        AxMCSA     matlab.ui.control.UIAxes
        AxHI       matlab.ui.control.UIAxes
        AxRUL      matlab.ui.control.UIAxes
        AxTemp     matlab.ui.control.UIAxes
        AxMargin   matlab.ui.control.UIAxes
        AxCoolEff  matlab.ui.control.UIAxes
        AxD        matlab.ui.control.UIAxes

        % ---- Backend state (Phase A/C/D functions and their outputs) ----
        cfg
        SensorConfig
        P
        T_thresh
        model
        model_metadata
        history = []
        stop_requested logical = false
    end

    methods (Access = public)
        function app = CoolingDigitalTwinApp()
            app.createComponents();
            app.startup();
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)

        % ==============================================================
        % Startup
        % ==============================================================
        function startup(app)
            app.cfg = project_config();
            app.SensorConfig = sensor_config();
            app.P = model_parameters();
            app.T_thresh = get_maintenance_thresholds();

            % Load (or, only if truly absent, train once and save) the
            % classifier. This is the ONLY place the app calls
            % load_or_train_model — never again during the session, so
            % changing controls never retrains anything (Phase D).
            [app.model, app.model_metadata] = load_or_train_model('fusion_state');

            app.EquipmentDropDown.Items = app.cfg.equipment;
            app.EquipmentDropDown.Value = 'Fan';
            app.onEquipmentChanged();   % populates FaultTypeDropDown for 'Fan'

            app.ITLoadSlider.Limits = [10, 100];
            app.ITLoadSlider.Value = app.P.Thermal.IT_load_kW_nominal;
            app.AmbientSlider.Limits = app.cfg.operating.ambient_C_range;
            app.AmbientSlider.Value = app.P.Thermal.ambient_C_nominal;
            app.RPMSlider.Limits = app.cfg.operating.speed_rpm_range;
            app.RPMSlider.Value = app.P.Fan.N_nominal_rpm;
            app.LoadFracSlider.Limits = app.cfg.operating.load_pct_range;
            app.LoadFracSlider.Value = 80;

            app.SeveritySlider.Value = 0;
            app.VibNoiseSlider.Limits = [0, 5];
            app.VibNoiseSlider.Value = 1;
            app.CurNoiseSlider.Limits = [0, 5];
            app.CurNoiseSlider.Value = 1;
            app.SweepStepsField.Value = 30;

            app.updateSliderLabels();

            % Opening state: healthy cooling system (per the spec's
            % "Expected Final User Experience").
            app.onHealthy();
        end

        % ==============================================================
        % Component creation
        % ==============================================================
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Cooling Predictive Maintenance — Interactive Digital Twin', ...
                'Position', [50, 50, 1400, 900]);

            mainGrid = uigridlayout(app.UIFigure, [1, 2]);
            mainGrid.ColumnWidth = {340, '1x'};
            mainGrid.RowHeight = {'1x'};

            app.createControlsPanel(mainGrid);
            app.createRightSide(mainGrid);
        end

        function createControlsPanel(app, parent)
            p = uipanel(parent, 'Title', 'CONTROLS');
            p.Layout.Row = 1; p.Layout.Column = 1;

            g = uigridlayout(p, [26, 2]);
            g.RowHeight = repmat({22}, 1, 26);
            g.ColumnWidth = {'1x', 70};

            r = 1;
            local_section(g, r, 'OPERATING CONDITIONS'); r = r + 1;

            uilabel(g, 'Text', 'IT Load (kW)').Layout = local_pos(r, 1);
            app.ITLoadSlider = uislider(g, 'ValueChangedFcn', @(s,e) app.updateSliderLabels());
            app.ITLoadSlider.Layout = local_pos(r, 2); r = r + 1;
            app.ITLoadLabel = uilabel(g, 'Text', '');
            app.ITLoadLabel.Layout = local_pos(r, [1 2]); r = r + 1;

            uilabel(g, 'Text', 'Ambient (C)').Layout = local_pos(r, 1);
            app.AmbientSlider = uislider(g, 'ValueChangedFcn', @(s,e) app.updateSliderLabels());
            app.AmbientSlider.Layout = local_pos(r, 2); r = r + 1;
            app.AmbientLabel = uilabel(g, 'Text', '');
            app.AmbientLabel.Layout = local_pos(r, [1 2]); r = r + 1;

            uilabel(g, 'Text', 'Speed (rpm)').Layout = local_pos(r, 1);
            app.RPMSlider = uislider(g, 'ValueChangedFcn', @(s,e) app.updateSliderLabels());
            app.RPMSlider.Layout = local_pos(r, 2); r = r + 1;
            app.RPMLabel = uilabel(g, 'Text', '');
            app.RPMLabel.Layout = local_pos(r, [1 2]); r = r + 1;

            uilabel(g, 'Text', 'Load (%)').Layout = local_pos(r, 1);
            app.LoadFracSlider = uislider(g, 'ValueChangedFcn', @(s,e) app.updateSliderLabels());
            app.LoadFracSlider.Layout = local_pos(r, 2); r = r + 1;
            app.LoadFracLabel = uilabel(g, 'Text', '');
            app.LoadFracLabel.Layout = local_pos(r, [1 2]); r = r + 1;

            local_section(g, r, 'FAULT CONFIGURATION'); r = r + 1;

            uilabel(g, 'Text', 'Equipment').Layout = local_pos(r, 1);
            app.EquipmentDropDown = uidropdown(g, 'Items', {'Pump','Fan'}, ...
                'ValueChangedFcn', @(s,e) app.onEquipmentChanged());
            app.EquipmentDropDown.Layout = local_pos(r, 2); r = r + 1;

            uilabel(g, 'Text', 'Fault Type').Layout = local_pos(r, 1);
            app.FaultTypeDropDown = uidropdown(g, 'Items', {'Healthy'});
            app.FaultTypeDropDown.Layout = local_pos(r, 2); r = r + 1;

            uilabel(g, 'Text', 'Severity D').Layout = local_pos(r, 1);
            app.SeveritySlider = uislider(g, 'Limits', [0 100], ...
                'ValueChangedFcn', @(s,e) app.updateSliderLabels());
            app.SeveritySlider.Layout = local_pos(r, 2); r = r + 1;
            app.SeverityLabel = uilabel(g, 'Text', '');
            app.SeverityLabel.Layout = local_pos(r, [1 2]); r = r + 1;

            local_section(g, r, 'SENSOR CONDITIONS'); r = r + 1;

            uilabel(g, 'Text', 'Vib. noise x').Layout = local_pos(r, 1);
            app.VibNoiseSlider = uislider(g, 'Limits', [0 5]);
            app.VibNoiseSlider.Layout = local_pos(r, 2); r = r + 1;

            uilabel(g, 'Text', 'Current noise x').Layout = local_pos(r, 1);
            app.CurNoiseSlider = uislider(g, 'Limits', [0 5]);
            app.CurNoiseSlider.Layout = local_pos(r, 2); r = r + 1;

            local_section(g, r, 'SIMULATION'); r = r + 1;

            uilabel(g, 'Text', 'Sweep steps').Layout = local_pos(r, 1);
            app.SweepStepsField = uieditfield(g, 'numeric', 'Limits', [2 200], 'Value', 30);
            app.SweepStepsField.Layout = local_pos(r, 2); r = r + 1;

            app.RunButton = uibutton(g, 'Text', 'RUN', ...
                'ButtonPushedFcn', @(b,e) app.onRun());
            app.RunButton.Layout = local_pos(r, [1 2]); r = r + 1;

            app.SweepButton = uibutton(g, 'Text', 'FAULT SWEEP', ...
                'ButtonPushedFcn', @(b,e) app.onFaultSweep());
            app.SweepButton.Layout = local_pos(r, [1 2]); r = r + 1;

            app.HealthyButton = uibutton(g, 'Text', 'HEALTHY', ...
                'ButtonPushedFcn', @(b,e) app.onHealthy());
            app.HealthyButton.Layout = local_pos(r, [1 2]); r = r + 1;

            app.ResetButton = uibutton(g, 'Text', 'RESET', ...
                'ButtonPushedFcn', @(b,e) app.onReset());
            app.ResetButton.Layout = local_pos(r, [1 2]); r = r + 1;

            app.StopButton = uibutton(g, 'Text', 'STOP', ...
                'ButtonPushedFcn', @(b,e) app.onStop());
            app.StopButton.Layout = local_pos(r, [1 2]); r = r + 1;
        end

        function createRightSide(app, parent)
            rightGrid = uigridlayout(parent, [2, 1]);
            rightGrid.Layout.Row = 1; rightGrid.Layout.Column = 2;
            rightGrid.RowHeight = {150, '1x'};

            app.createStatusPanel(rightGrid);
            app.createPlotTabs(rightGrid);
        end

        function createStatusPanel(app, parent)
            p = uipanel(parent, 'Title', 'SYSTEM STATUS');
            p.Layout.Row = 1; p.Layout.Column = 1;

            g = uigridlayout(p, [4, 7]);
            g.RowHeight = {22, 22, 22, 22};
            g.ColumnWidth = {110, 130, 110, 130, 110, 130, 110};

            app.StatusValueLabel = local_bignum(g, 1, [1 2], 'NORMAL');
            uilabel(g, 'Text', 'Equipment:').Layout = local_pos(1,3);
            app.EquipmentValueLabel = local_val(g, 1, 4);
            uilabel(g, 'Text', 'Fault (injected):').Layout = local_pos(1,5);
            app.FaultValueLabel = local_val(g, 1, 6);

            uilabel(g, 'Text', 'Severity:').Layout = local_pos(2,1);
            app.SeverityValueLabel = local_val(g, 2, 2);
            uilabel(g, 'Text', 'AI Predicted:').Layout = local_pos(2,3);
            app.PredictedValueLabel = local_val(g, 2, 4);
            uilabel(g, 'Text', 'Maintenance:').Layout = local_pos(2,5);
            app.MaintValueLabel = local_val(g, 2, 6);

            uilabel(g, 'Text', 'Health Index:').Layout = local_pos(3,1);
            app.HIValueLabel = local_val(g, 3, 2);
            uilabel(g, 'Text', 'RUL (h):').Layout = local_pos(3,3);
            app.RULValueLabel = local_val(g, 3, 4);
            uilabel(g, 'Text', 'Cooling eff.:').Layout = local_pos(3,5);
            app.CoolEffValueLabel = local_val(g, 3, 6);

            uilabel(g, 'Text', 'Temperature (C):').Layout = local_pos(4,1);
            app.TempValueLabel = local_val(g, 4, 2);
            uilabel(g, 'Text', 'Thermal margin (C):').Layout = local_pos(4,3);
            app.MarginValueLabel = local_val(g, 4, 4);

            lampGrid = uigridlayout(g, [1,4]);
            lampGrid.Layout = local_pos(4, [5 7]);
            lampGrid.Padding = [0 0 0 0];
            app.PumpStatusLabel = local_statuslamp(lampGrid, 1, 'PUMP');
            app.FanStatusLabel = local_statuslamp(lampGrid, 2, 'FAN');
            app.CoolingStatusLabel = local_statuslamp(lampGrid, 3, 'COOLING');
            app.ThermalStatusLabel = local_statuslamp(lampGrid, 4, 'THERMAL');
        end

        function createPlotTabs(app, parent)
            tg = uitabgroup(parent);
            tg.Layout.Row = 2; tg.Layout.Column = 1;

            tabSignals = uitab(tg, 'Title', 'Signals');
            gS = uigridlayout(tabSignals, [2,2]);
            app.AxVibWave = uiaxes(gS); title(app.AxVibWave, 'Vibration waveform');
            app.AxVibFFT  = uiaxes(gS); title(app.AxVibFFT, 'Vibration spectrum (FFT)');
            app.AxCurWave = uiaxes(gS); title(app.AxCurWave, 'Motor current waveform');
            app.AxMCSA    = uiaxes(gS); title(app.AxMCSA, 'MCSA spectrum');

            tabTrends = uitab(tg, 'Title', 'Trends');
            gT = uigridlayout(tabTrends, [3,2]);
            app.AxHI      = uiaxes(gT); title(app.AxHI, 'Health Index vs time');
            app.AxRUL     = uiaxes(gT); title(app.AxRUL, 'RUL vs time');
            app.AxTemp    = uiaxes(gT); title(app.AxTemp, 'Server inlet temperature vs time');
            app.AxMargin  = uiaxes(gT); title(app.AxMargin, 'Thermal margin vs time');
            app.AxCoolEff = uiaxes(gT); title(app.AxCoolEff, 'Cooling effectiveness vs time');
            app.AxD       = uiaxes(gT); title(app.AxD, 'Degradation D vs time');
        end

        % ==============================================================
        % Callbacks
        % ==============================================================
        function onEquipmentChanged(app)
            equipment = app.EquipmentDropDown.Value;
            app.FaultTypeDropDown.Items = app.cfg.faults.(equipment);
            app.FaultTypeDropDown.Value = 'Healthy';
        end

        function updateSliderLabels(app)
            app.ITLoadLabel.Text = sprintf('%.0f kW', app.ITLoadSlider.Value);
            app.AmbientLabel.Text = sprintf('%.1f C', app.AmbientSlider.Value);
            app.RPMLabel.Text = sprintf('%.0f rpm', app.RPMSlider.Value);
            app.LoadFracLabel.Text = sprintf('%.0f %%', app.LoadFracSlider.Value);
            app.SeverityLabel.Text = sprintf('%.0f %%', app.SeveritySlider.Value);
        end

        function onRun(app)
            app.stop_requested = false;
            app.runOneStep();
        end

        function onFaultSweep(app)
            app.stop_requested = false;
            equipment = app.EquipmentDropDown.Value;
            faultType = app.FaultTypeDropDown.Value;
            n_steps = round(app.SweepStepsField.Value);
            D_vec = linspace(0, 1, n_steps);   % controlled trajectory, existing degradation model

            for k = 1:n_steps
                if app.stop_requested
                    break;
                end
                app.SeveritySlider.Value = D_vec(k) * 100;
                app.updateSliderLabels();
                app.runOneStep();
                drawnow;
            end
        end

        function onHealthy(app)
            app.stop_requested = false;
            app.history = [];
            app.FaultTypeDropDown.Value = 'Healthy';
            app.SeveritySlider.Value = 0;
            app.updateSliderLabels();
            app.runOneStep();
        end

        function onReset(app)
            app.onHealthy();
        end

        function onStop(app)
            app.stop_requested = true;
        end

        function runOneStep(app)
            equipment = app.EquipmentDropDown.Value;
            faultType = app.FaultTypeDropDown.Value;
            D = app.SeveritySlider.Value / 100;
            N_rpm = app.RPMSlider.Value;
            load_frac = app.LoadFracSlider.Value / 100;
            ambient_C = app.AmbientSlider.Value;
            IT_load_kW = app.ITLoadSlider.Value;

            % Live sensor-noise override: a fresh copy of SensorConfig
            % with only the two noise fields scaled by the sliders — the
            % underlying sensor_config() values (from Phase 0's config
            % inspection) are the base, never replaced.
            SensorConfigLive = app.SensorConfig;
            SensorConfigLive.Accelerometer.noise_rms_g = ...
                app.SensorConfig.Accelerometer.noise_rms_g * app.VibNoiseSlider.Value;
            SensorConfigLive.Current.noise_rms_A = ...
                app.SensorConfig.Current.noise_rms_A * app.CurNoiseSlider.Value;

            try
                [result, app.history] = run_single_operating_point(equipment, faultType, D, ...
                    N_rpm, load_frac, ambient_C, IT_load_kW, app.model, app.history, ...
                    app.cfg, SensorConfigLive, app.P, app.T_thresh, 1.0);
                app.updateDashboard(result);
            catch ME
                uialert(app.UIFigure, ME.message, 'Simulation step failed');
            end
        end

        % ==============================================================
        % Dashboard update — every value below comes directly from
        % 'result' (returned by run_single_operating_point) or from
        % app.history (the running buffer that same function maintains).
        % ==============================================================
        function updateDashboard(app, result)
            app.StatusValueLabel.Text = result.decision.level;
            app.StatusValueLabel.BackgroundColor = local_status_color(result.decision.level);

            app.EquipmentValueLabel.Text = result.equipment;
            app.FaultValueLabel.Text = result.fault_type_injected;
            app.SeverityValueLabel.Text = sprintf('%.0f %%', result.D_injected * 100);
            app.PredictedValueLabel.Text = result.predicted_fault_type;
            app.HIValueLabel.Text = sprintf('%.1f', result.HI);
            app.RULValueLabel.Text = local_fmt_rul(result.RUL_hr);
            app.TempValueLabel.Text = sprintf('%.2f', result.T_server_inlet_C);
            app.MarginValueLabel.Text = sprintf('%.2f', result.thermal_margin_C);
            app.CoolEffValueLabel.Text = sprintf('%.2f', result.cooling_effectiveness);
            app.MaintValueLabel.Text = result.decision.level;

            % ---- Phase 6 status indicators — every color tied to a real
            % variable, never decorative ----
            app.updateEquipmentLamp(app.PumpStatusLabel, 'Pump', result);
            app.updateEquipmentLamp(app.FanStatusLabel, 'Fan', result);

            if result.cooling_effectiveness > 0.8
                app.setLamp(app.CoolingStatusLabel, 'Normal', [0.6 0.9 0.6]);
            elseif result.cooling_effectiveness > 0.3
                app.setLamp(app.CoolingStatusLabel, 'Reduced', [1 0.9 0.5]);
            else
                app.setLamp(app.CoolingStatusLabel, 'Critical', [1 0.6 0.6]);
            end

            if result.thermal_margin_C > app.T_thresh.thermal_margin_warning_C
                app.setLamp(app.ThermalStatusLabel, 'Safe', [0.6 0.9 0.6]);
            elseif result.thermal_margin_C > app.T_thresh.thermal_margin_critical_C
                app.setLamp(app.ThermalStatusLabel, 'Warning', [1 0.9 0.5]);
            else
                app.setLamp(app.ThermalStatusLabel, 'Critical', [1 0.6 0.6]);
            end

            app.updatePlots(result);
        end

        function updateEquipmentLamp(app, lbl, equipmentName, result)
            if ~strcmp(result.equipment, equipmentName)
                app.setLamp(lbl, 'Not run', [0.85 0.85 0.85]);
                return;
            end
            D = result.D_injected;
            if D <= 0
                app.setLamp(lbl, 'Healthy', [0.6 0.9 0.6]);
            elseif D < app.P.Health.D_critical
                app.setLamp(lbl, 'Degraded', [1 0.9 0.5]);
            else
                app.setLamp(lbl, 'Critical', [1 0.6 0.6]);
            end
        end

        function setLamp(~, lbl, text, color)
            lbl.Text = text;
            lbl.BackgroundColor = color;
        end

        function updatePlots(app, result)
            Fs_acc = result.signals.Fs_acc;
            Fs_cur = result.signals.Fs_cur;

            plot(app.AxVibWave, result.signals.vib_time, result.signals.vib_signal);
            xlabel(app.AxVibWave, 'Time (s)'); ylabel(app.AxVibWave, 'g');

            [f_v, X_v] = local_fft_for_display(result.signals.vib_signal, Fs_acc);
            plot(app.AxVibFFT, f_v, X_v); xlim(app.AxVibFFT, [0, min(2000, Fs_acc/2)]);
            xlabel(app.AxVibFFT, 'Hz'); ylabel(app.AxVibFFT, '|X(f)|');

            plot(app.AxCurWave, result.signals.current_time, result.signals.current_signal);
            xlabel(app.AxCurWave, 'Time (s)'); ylabel(app.AxCurWave, 'A');

            [f_c, X_c] = local_fft_for_display(result.signals.current_signal, Fs_cur);
            plot(app.AxMCSA, f_c, X_c); xlim(app.AxMCSA, [0, 500]);
            xlabel(app.AxMCSA, 'Hz'); ylabel(app.AxMCSA, '|I(f)|');

            h = app.history;
            plot(app.AxHI, h.time_hr, h.HI, '-o');
            xlabel(app.AxHI, 'Time (hr)'); ylabel(app.AxHI, 'Health Index');

            rul_trend = local_rul_trend_from_history(h, app.P.Health);
            plot(app.AxRUL, h.time_hr, rul_trend, '-o');
            xlabel(app.AxRUL, 'Time (hr)'); ylabel(app.AxRUL, 'RUL (hr)');

            tt = result.thermal_trajectory;
            plot(app.AxTemp, tt.time/3600, tt.T_server_inlet_C, '-o');
            xlabel(app.AxTemp, 'Time (hr)'); ylabel(app.AxTemp, 'T (C)');

            plot(app.AxMargin, tt.time/3600, tt.thermal_margin_C, '-o');
            xlabel(app.AxMargin, 'Time (hr)'); ylabel(app.AxMargin, 'Margin (C)');

            plot(app.AxCoolEff, h.time_hr, h.effectiveness, '-o');
            xlabel(app.AxCoolEff, 'Time (hr)'); ylabel(app.AxCoolEff, 'Effectiveness');

            plot(app.AxD, h.time_hr, h.D, '-o');
            xlabel(app.AxD, 'Time (hr)'); ylabel(app.AxD, 'D');
        end
    end
end

% ======================================================================
% Local (file-scope) helper functions
% ======================================================================
function pos = local_pos(row, col)
    s.Row = row; s.Column = col;
    pos = s;
end

function local_section(g, row, txt)
    lbl = uilabel(g, 'Text', txt, 'FontWeight', 'bold');
    lbl.Layout = local_pos(row, [1 2]);
end

function lbl = local_val(g, row, col)
    lbl = uilabel(g, 'Text', '-', 'FontWeight', 'bold');
    lbl.Layout = local_pos(row, col);
end

function lbl = local_bignum(g, row, cols, txt)
    lbl = uilabel(g, 'Text', txt, 'FontSize', 18, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center');
    lbl.Layout = local_pos(row, cols);
end

function lbl = local_statuslamp(g, col, txt)
    lbl = uilabel(g, 'Text', txt, 'HorizontalAlignment', 'center', ...
        'BackgroundColor', [0.85 0.85 0.85]);
    lbl.Layout = local_pos(1, col);
end

function color = local_status_color(level)
    switch level
        case 'NORMAL'
            color = [0.6 0.9 0.6];
        case 'MONITOR'
            color = [0.85 0.95 0.6];
        case 'WARNING'
            color = [1 0.9 0.5];
        case 'MAINTENANCE_REQUIRED'
            color = [1 0.75 0.5];
        case 'CRITICAL'
            color = [1 0.6 0.6];
        otherwise
            color = [0.85 0.85 0.85];
    end
end

function txt = local_fmt_rul(rul_hr)
    if isnan(rul_hr)
        txt = 'N/A (no trend)';
    else
        txt = sprintf('%.1f', rul_hr);
    end
end

function [f, X] = local_fft_for_display(x, Fs)
%LOCAL_FFT_FOR_DISPLAY Presentation-only FFT magnitude of an
%   already-computed real signal — not a diagnostic computation (the
%   real diagnostic features come from extract_vibration_features.m /
%   extract_mcsa_features.m inside the tested backend).
    n = numel(x);
    X = abs(fft(x));
    X = X(1:floor(n/2)+1);
    f = (0:floor(n/2))' * (Fs/n);
end

function rul_trend = local_rul_trend_from_history(history, HealthP)
%LOCAL_RUL_TREND_FROM_HISTORY Reconstruct a per-step RUL series for
%   plotting, by calling the project's own estimate_rul.m over a 5-sample
%   sliding window of the history — the SAME window size and function
%   already used by simulate_degradation_trajectory.m and Experiments
%   4/5/9, just applied here so the "RUL vs time" plot has more than one
%   point (run_single_operating_point.m itself only returns the CURRENT
%   RUL estimate, by design — this is a plotting convenience, not a
%   second implementation of RUL estimation).
    n = numel(history.time_hr);
    rul_trend = nan(n, 1);
    rul_window = 5;
    for k = 1:n
        w_start = max(1, k - rul_window + 1);
        r = estimate_rul(history.time_hr(w_start:k), history.HI(w_start:k), HealthP);
        rul_trend(k) = r.RUL;
    end
end
