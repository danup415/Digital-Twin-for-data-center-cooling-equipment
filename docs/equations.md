# Equations Reference

Every equation below is implemented in exactly one file; this document exists so
the final report chapters can cite a single source of truth rather than
re-deriving anything.

## Pump / Fan affinity laws — `src/physics/pump_model.m`, `fan_model.m`
`Q ∝ N`, `ΔP ∝ N²`, `P_shaft ∝ N³` (speed-scaled from the nominal operating
point), with efficiency following a quadratic best-efficiency-point (BEP)
curve: `η(load_frac) = η_nominal · (1 − k(load_frac − 1)²)`, `k = 0.30`.

## Induction motor — `src/physics/motor_model.m`
Synchronous speed `N_sync = 120·f_line / poles`; slip `s = (N_sync − N)/N_sync`;
mechanical power `P_mech = τ·ω`; electrical power `P_elec = P_mech / η_motor`
(constant assumed `η_motor = 0.90`, `pf = 0.85`); line current from
`S = P_elec/pf`, `I = S/(√3·V)`.

## Bearing fault frequencies — `src/faults/bearing_fault_frequencies.m`
With `Nb` = rolling elements, `Bd` = ball diameter, `Pd` = pitch diameter,
`φ` = contact angle, `f_r` = shaft rotation frequency:
`BPFO = (Nb/2)·f_r·(1 − (Bd/Pd)cosφ)`
`BPFI = (Nb/2)·f_r·(1 + (Bd/Pd)cosφ)`
`BSF  = (Pd/2Bd)·f_r·(1 − ((Bd/Pd)cosφ)²)`
`FTF  = (f_r/2)·(1 − (Bd/Pd)cosφ)`

## Fault degradation coupling — `src/faults/apply_pump_fault.m`, `apply_fan_fault.m`
Generic form `η_fault = η_nominal·(1 − f_D(D))`, with fault-specific
coefficients on hydraulic efficiency/flow/head (documented inline in each
`case` branch) — every fault acts through the single severity variable `D`.

## Vibration signal model — `src/sensors/generate_vibration_signal.m`
`x(t) = A₁sin(2πf_r t) + harmonics + unbalance(U)·sin(2πf_r t) +
misalignment(M)·[1X+2X] + bearing_impulse_train(D_b, BPFO) +
cavitation_broadband(C) + sensor_noise`. The bearing impulse train is a
repeating exponentially-decaying pulse at the BPFO period, amplitude scaled
by `D_b`.

## MCSA signal model — `src/sensors/generate_current_signal.m`
`i(t) = I₀sin(2πf_line t) + harmonics + sideband_modulation`, where the
sideband term amplitude-modulates the fundamental at the rotor mechanical
frequency `f_r`, with modulation depth proportional to the combined
mechanical-fault severity `(U + M + D_b)` — the standard MCSA principle that
a periodic mechanical disturbance modulates motor torque/slip.

## Unbalance force — used conceptually in `apply_pump_fault.m` / `apply_fan_fault.m`
`F_u = m·e·ω²` (rotating eccentric mass); the resulting vibration amplitude
scaling is implemented directly in the signal generator rather than as a
separate force-to-displacement transfer function (reduced-order simplification).

## Cavitation — `src/faults/apply_pump_fault.m` + `src/sensors/generate_vibration_signal.m`
NPSH margin `Δ = NPSH_available − NPSH_required` (values in
`model_parameters.m`); cavitation severity `C` (not `Δ` directly) drives
flow/head/efficiency loss and broadband high-frequency vibration energy —
explicitly a reduced-order surrogate, not a CFD cavitation model.

## Health Index — `src/health_index/compute_health_index.m`
`HI = 100·(1 − min(D_effective/D_critical, 1))`, where `D_effective` is the
worst (max) active fault severity for the asset.

## RUL — `src/RUL/estimate_rul.m`
Linear trend fit `HI(t) = a + b·t` over a recent history window;
`T_critical_est = (HI_critical − a)/b`; `RUL = T_critical_est − t_now`.
Returns `NaN` when `b ≥ 0` (no degrading trend to extrapolate) rather than
fabricating a number.

## Thermal digital twin — `src/thermal/thermal_digital_twin.m`
Lumped first-order RC energy balance: `C_th·dT/dt = Q_IT − Q_cooling_effective`,
`Q_cooling_effective = effectiveness(t)·C_th·(T − T_ambient)/τ`. Integrated
with the EXACT closed-form solution per interval — `T(t) = T_ss + (T0 −
T_ss)·exp(−rate·dt)`, `rate = effectiveness/τ`, `T_ss = T_ambient +
Q_IT·τ/(effectiveness·C_th)` — rather than forward Euler, because this
project's trajectory timesteps (hours) are many times longer than `τ`
(seconds); forward Euler is unstable at that timestep/time-constant ratio
and was found to blow up to astronomical oscillating values, while the
exact exponential update is unconditionally stable for any timestep.
`effectiveness(t)` comes from `cooling_effectiveness_from_degradation.m`, which is the explicit
fault→thermal-consequence link (§28): pump cavitation and fan
airflow-reducing faults get the largest effectiveness penalty; purely
mechanical/vibration faults get a smaller residual penalty.

## Maintenance decision thresholds — `src/maintenance/get_maintenance_thresholds.m`
All threshold values and their rationale are documented as comments in that
file (not repeated here to avoid two sources of truth); `maintenance_decision_engine.m`
returns the most urgent level across the Health Index, RUL and thermal-margin
signals.
