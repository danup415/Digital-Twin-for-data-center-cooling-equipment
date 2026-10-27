function P = model_parameters()
%MODEL_PARAMETERS Physical parameters for pump, fan, motor, bearing and
%thermal-twin models.
%
%   P = MODEL_PARAMETERS() returns a struct with every constant used by
%   src/physics/*.m, src/faults/*.m and src/thermal/*.m (Phases 2, 3, 10).
%   Every numeric value below carries a one-line rationale so the report's
%   docs/assumptions.md can be generated directly from this file's comments.

    % =================================================================
    % CHILLED-WATER PUMP — nominal (healthy) operating point + affinity
    % law reference values (§7)
    % =================================================================
    P.Pump.N_nominal_rpm   = 1500;      % nominal shaft speed
    P.Pump.Q_nominal_Lps   = 20;        % nominal flow at N_nominal
    P.Pump.dP_nominal_kPa  = 250;       % nominal head/pressure rise
    P.Pump.eta_nominal     = 0.72;      % nominal hydraulic efficiency (typical centrifugal pump BEP)
    P.Pump.P_shaft_nominal_kW = (P.Pump.Q_nominal_Lps/1000 * P.Pump.dP_nominal_kPa*1000) / P.Pump.eta_nominal / 1000;

    % Cavitation / NPSH (§11)
    P.Pump.NPSH_required_m = 3.0;       % manufacturer-typical NPSHr at BEP
    P.Pump.NPSH_available_nominal_m = 6.0;  % assumed plant NPSHa with margin

    % Unbalance (§12): eccentric mass model F_u = m*e*w^2
    P.Pump.unbalance.mass_kg        = 0.05;   % representative small eccentric mass
    P.Pump.unbalance.eccentricity_m = 1e-4;   % representative eccentricity

    % =================================================================
    % CRAC FAN — nominal operating point (§7)
    % =================================================================
    P.Fan.N_nominal_rpm   = 1450;
    P.Fan.Q_nominal_m3ps  = 2.5;        % nominal airflow
    P.Fan.dP_nominal_Pa   = 300;        % nominal static pressure
    P.Fan.eta_nominal     = 0.65;       % typical centrifugal/axial CRAC fan efficiency
    P.Fan.P_shaft_nominal_kW = (P.Fan.Q_nominal_m3ps * P.Fan.dP_nominal_Pa) / P.Fan.eta_nominal / 1000;

    P.Fan.unbalance.mass_kg        = 0.02;
    P.Fan.unbalance.eccentricity_m = 1.5e-4;

    % =================================================================
    % INDUCTION MOTOR — simplified equivalent-circuit parameters,
    % shared functional form for the pump-drive and fan-drive motors
    % (§8). Values are representative of a small/medium industrial
    % induction motor, not a specific datasheet.
    % =================================================================
    P.Motor.line_freq_Hz     = 50;      % supply frequency
    P.Motor.pole_pairs       = 2;       % => sync speed 1500 rpm at 50 Hz
    P.Motor.rated_voltage_V  = 400;
    P.Motor.rated_current_A  = 15;
    P.Motor.slip_rated       = 0.03;    % typical rated slip
    P.Motor.rotor_bars       = 28;      % used only for sideband-frequency bookkeeping

    % =================================================================
    % BEARING GEOMETRY — used to compute BPFO/BPFI/BSF/FTF (§10).
    % Representative deep-groove ball bearing dimensions.
    % =================================================================
    P.Bearing.num_elements      = 8;      % Nb
    P.Bearing.ball_diameter_mm  = 8;      % Bd
    P.Bearing.pitch_diameter_mm = 40;     % Pd
    P.Bearing.contact_angle_deg = 0;      % phi (deep-groove => ~0)

    % =================================================================
    % THERMAL DIGITAL TWIN — lumped RC network for a single data-hall
    % zone served by this CRAC/pump pair (§26–27).
    % =================================================================
    P.Thermal.IT_load_kW_nominal      = 40;    % representative small data-hall zone
    P.Thermal.ambient_C_nominal       = 24;
    P.Thermal.thermal_mass_kJ_per_C   = 5000;  % lumped thermal mass of hall + equipment
    P.Thermal.cooling_time_constant_s = 350;   % chilled-water loop response time
    % (raised from an earlier 180s: at 180s the loop had so much cooling
    % headroom that even a fully-failed pump/fan never pushed the
    % server-inlet temperature near T_safe, so no trajectory could ever
    % demonstrate an actual thermal-threshold violation for Experiments
    % 4/9 to measure a lead time against. 350s keeps the healthy
    % steady-state comfortably below T_safe while letting severe
    % degradation on a primary-path fault genuinely threaten it.)
    P.Thermal.T_safe_C                = 32;    % configurable server-inlet safety threshold (ASHRAE-style allowable max, representative)
    P.Thermal.cp_water_kJ_per_kgC     = 4.18;
    P.Thermal.rho_water_kg_per_L      = 1.0;
    P.Thermal.cp_air_kJ_per_kgC       = 1.005;
    P.Thermal.rho_air_kg_per_m3       = 1.2;

    % =================================================================
    % DATA-CENTER DYNAMIC LOADS / CHILLER (MathWorks #196 Stage 1)
    % New fields only — existing P.Thermal / P.Pump / P.Fan names unchanged.
    % Q_IT_z = P_idle + (P_max - P_idle)*w_z*u_CPU + alpha_leak*max(0, T_srv_z - T_ref)^2
    % =================================================================
    P.DataCenter.zone_names           = {'Zone_A','Zone_B','Zone_C'};
    P.DataCenter.n_zones              = 3;
    % Per-zone idle / nameplate compute. Uniform w_z = 1/3 and u_CPU ~ 0.7
    % yields plant IT heat near Thermal.IT_load_kW_nominal (40 kW).
    P.DataCenter.P_idle_kW            = 10.0;
    P.DataCenter.P_max_kW             = 22.0;
    P.DataCenter.alpha_leak_kW_per_C2 = 0.04;   % CMOS leakage ~ (T - T_ref)^2
    P.DataCenter.T_ref_C              = 25.0;   % silicon leakage reference
    P.DataCenter.T_srv_limit_C        = 28.0;   % EMPC hard comfort/safety cap
    P.DataCenter.T_chw_sup_nominal_C  = 7.0;    % baseline CHW supply (ASHRAE-typical)
    P.DataCenter.T_chw_sup_min_C      = 6.0;
    P.DataCenter.T_chw_sup_max_C      = 18.0;
    % Diurnal outdoor-air profile (deterministic; min ~03:00, max ~15:00)
    P.DataCenter.T_amb_mean_C         = P.Thermal.ambient_C_nominal;
    P.DataCenter.T_amb_amp_C          = 6.0;
    P.DataCenter.RH_mean              = 0.50;
    P.DataCenter.RH_amp               = 0.18;
    % Server utilization: business-hours baseline + scheduled cloud bursts
    P.DataCenter.u_CPU_night          = 0.28;
    P.DataCenter.u_CPU_day            = 0.72;
    P.DataCenter.burst_hours          = [10.0, 14.0, 21.0];
    P.DataCenter.burst_amplitude      = 0.22;
    P.DataCenter.burst_width_hr       = 0.75;
    % Nominal local cooling-effectiveness bias (A best-cooled, C worst aisle)
    P.DataCenter.zone_effectiveness_nominal = [1.00, 0.95, 0.88];
    % Cooling coil UA per zone so u_eq≈1, T_chw=7 C, Q_IT≈13 kW → T_ss≈18 C
    P.DataCenter.UA_zone_kW_per_K     = 1.20;
    P.DataCenter.C_th_zone_kJ_per_C   = P.Thermal.thermal_mass_kJ_per_C / 3;
    % Chiller COP(T_amb, T_chw_sup): COP = a0 + a1*T_amb + a2*T_chw + humidity derate
    P.DataCenter.COP_a0               = 8.40;
    P.DataCenter.COP_a1               = -0.11;  % hotter outdoor air lowers COP
    P.DataCenter.COP_a2               = 0.16;   % warmer CHW (floating) raises COP
    P.DataCenter.COP_RH_penalty       = 0.10;   % fractional derate above RH_mean
    P.DataCenter.COP_min              = 2.50;
    P.DataCenter.COP_max              = 8.50;

    % =================================================================
    % STAGE-1 CONTROLLERS (gains / constraints; unused by Phases 1–15)
    % =================================================================
    P.Control.T_set_C                 = 24.0;
    P.Control.deadband_C              = 1.0;    % thermostatic hysteresis ±1 C
    P.Control.u_min                   = 0.40;   % affinity-law floor (avoid stall)
    P.Control.u_max                   = 1.00;
    P.Control.du_pump_max             = 0.20;   % healthy slew (per control step)
    P.Control.du_fan_max              = 0.25;
    P.Control.dt_s                    = 60;     % default receding-horizon step
    P.Control.horizon_steps           = 6;
    P.Control.n_grid_u                = 5;
    P.Control.n_grid_tchw             = 5;
    P.Control.Kp_outer                = 0.28;
    P.Control.Ki_outer                = 0.020;
    P.Control.Kd_outer                = 0.050;
    P.Control.Kaw_outer               = 0.40;   % back-calculation anti-windup
    P.Control.Kp_inner                = 1.10;
    P.Control.Ki_inner                = 0.35;
    P.Control.Kaw_inner               = 0.50;
    P.Control.lambda_energy           = 1.0;
    P.Control.lambda_T                = 80.0;   % T_srv > 28 C quadratic slack
    P.Control.lambda_health           = 25.0;
    P.Control.lambda_rul              = 12.0;
    P.Control.RUL_scale_hr            = 48.0;

    % =================================================================
    % HEALTH INDEX / RUL configuration (§24–25)
    % =================================================================
    P.Health.HI_healthy = 100;
    P.Health.HI_critical = 0;
    P.Health.D_critical  = 0.60;   % degradation value treated as "critical" (T_critical trigger)
end
