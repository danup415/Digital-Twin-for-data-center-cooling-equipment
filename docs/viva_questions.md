# Viva Preparation — Questions and Model Answers

## Instrumentation & Sensors
**1. Why does the accelerometer sample at 10 kHz while the temperature sensor samples at 1 Hz?**
Bearing fault frequencies and vibration harmonics live in the hundreds-of-Hz
to low-kHz range, so 10 kHz gives comfortable margin below Nyquist. Thermal
states change on the order of seconds to minutes (large thermal mass), so 1
Hz is more than sufficient and avoids wasted data volume — see the rationale
comments in `config/sensor_config.m`.

**2. Why include sensor bias and quantization in the virtual sensor model, not just noise?**
Real sensors have systematic bias and finite ADC resolution in addition to
random noise; omitting them would make the synthetic data unrealistically
clean and could inflate ML performance relative to a real deployment.

**3. What's the difference between the accelerometer's noise floor and its bias?**
Noise is zero-mean random variation (`noise_rms_g`, a different draw every
sample); bias is a constant offset (`bias_g`) present on every sample.

## Vibration & FFT
**4. Why is a Hann window applied before computing the FFT?**
Windowing reduces spectral leakage from segment edge discontinuities, giving
cleaner peak estimates for dominant frequency and bearing-fault band energy
(`src/signal_processing/segment_signal.m`).

**5. What does the crest factor tell you that RMS alone doesn't?**
Crest factor (`peak/RMS`) captures impulsiveness — a bearing fault produces
short sharp impulses that raise the peak much more than the RMS, so crest
factor rises even when RMS is still modest, often before RMS alone flags
anything.

**6. Why kurtosis in addition to crest factor?**
Kurtosis measures how "peaky" the whole amplitude distribution is (fourth
statistical moment), and is a standard early indicator of impulsive bearing
defects that's less sensitive to overall signal level than crest factor.

## MCSA & Induction Motors
**7. Why do mechanical faults show up as *sidebands* on the current spectrum rather than as new frequencies?**
A periodic mechanical disturbance (unbalance, a bearing defect) modulates the
motor's instantaneous torque/slip at the mechanical fault frequency `f_r`,
which amplitude-modulates the fundamental stator current — modulation in the
time domain is convolution in the frequency domain, producing sidebands at
`f_line ± f_r` (see `generate_current_signal.m`).

**8. What is slip, and why does it matter for MCSA?**
Slip `s = (N_sync - N)/N_sync` is the fractional difference between
synchronous and actual rotor speed; it sets the rotor's electrical frequency
and is the basis for locating fault-related sidebands relative to the line
frequency.

**9. Why did you assume constant motor efficiency and power factor instead of a full induction-motor model?**
This is a documented reduced-order simplification (`motor_model.m`) — the
goal is a physically-consistent current magnitude for MCSA feature
generation, not a torque-speed-curve-accurate drive model; a full dq-axis
model would be excessive for this project's diagnostic focus.

## Bearing Faults
**10. Derive/explain BPFO.**
`BPFO = (Nb/2)·f_r·(1 - (Bd/Pd)cosφ)` — the outer-race ball-pass frequency:
each of `Nb` rolling elements passes a fixed outer-race defect point at this
rate, scaled by geometry (`Bd/Pd`, contact angle `φ`) since elements travel
slower than the cage/shaft.

**11. Why is BPFI usually higher than BPFO for the same bearing?**
The `+` sign in BPFI vs `-` in BPFO reflects that, in the rotating (shaft)
reference frame, an inner-race defect is passed by more rolling elements per
revolution than an outer-race defect (which is fixed relative to the
stationary outer race), for typical geometry.

**12. What does FTF (cage frequency) tell you diagnostically?**
FTF is the rotational frequency of the cage itself; a defect there produces
a much lower-frequency, often amplitude-modulating signature, useful for
identifying cage-specific wear distinct from race/ball defects.

## Cavitation
**13. What is NPSH, and why does its margin matter?**
Net Positive Suction Head; when `NPSH_available` falls toward
`NPSH_required`, local pressure drops enough for vapor bubbles to form and
then violently collapse downstream — the mechanism behind cavitation noise
and damage.

**14. Why is your cavitation model called a "reduced-order surrogate" rather than a physical model?**
It does not solve the underlying two-phase flow/bubble-dynamics equations
(that would require CFD); it instead maps a severity variable `C` directly
to broadband vibration energy and flow/efficiency loss, capturing the
*qualitative* trend without claiming CFD-level fidelity.

## Pump / Fan Affinity Laws
**15. State the pump affinity laws used and their physical basis.**
`Q ∝ N`, `ΔP ∝ N²`, `P_shaft ∝ N³` — derived from dimensional analysis /
similarity theory for centrifugal machines operating at a fixed geometry and
similar flow coefficient.

**16. Why does efficiency follow a quadratic curve around the BEP rather than staying constant?**
Centrifugal pumps/fans are designed for peak efficiency at one flow
coefficient (BEP); operating away from it (part-load or overload) increases
internal losses (recirculation, incidence losses), which the quadratic
falloff term in `pump_model.m`/`fan_model.m` approximates.

## Signal Processing
**17. Why detrend before filtering?**
Removes DC offset/slow drift that would otherwise dominate the FFT's low-
frequency bins and can also destabilize some filter implementations.

**18. What's the fallback if the Signal Processing Toolbox isn't available, and why does it still work?**
A moving-average-based high-pass/low-pass (`movmean`), base MATLAB only; it's
cruder than a Butterworth/`filtfilt` design but still removes DC/slow drift
and limits high-frequency content, adequate for this project's feature
extraction.

## Machine Learning
**19. Why train/val/test split by scenario, not by random window?**
Windows from the same scenario/trajectory are highly correlated (same
underlying signal); splitting them across Train and Test would leak
information and inflate reported accuracy — the classic data-leakage trap
this project's `generate_scenarios.m` and `validate_project.m` are built to
prevent.

**20. What does the ablation study (Models A-E) actually prove?**
Whether each added information source — MCSA beyond vibration, operating
state beyond raw fusion, physics-residual features beyond fusion+state —
measurably improves accuracy/macro-F1, using the *same* classifier throughout
so the comparison isolates the feature set's effect.

**21. Why macro-F1 rather than plain accuracy as the headline metric?**
With multiple fault classes of uneven scenario counts, accuracy can be
dominated by the majority class; macro-F1 averages F1 per class equally,
surfacing poor performance on rare fault types that accuracy would hide.

**22. What happens in this project if the Deep Learning Toolbox isn't installed?**
`train_cnn1d.m` detects this, prints a warning, returns `type='unavailable'`,
and the pipeline reports classical-ML-only results — it does not fabricate a
CNN result.

## Feature Fusion
**23. Why concatenate vibration and MCSA features rather than train two separate models and average their outputs?**
Feature-level (early) fusion lets the single downstream classifier learn
joint relationships between vibration and current signatures, which can
capture fault signatures that are only distinguishable when both modalities
are considered together; this project's ablation study (Model C) tests
whether that fusion actually helps versus either modality alone.

**24. Why add operating-state features (Model D) at all?**
To let the model distinguish "high vibration because of high load" from
"high vibration because of a developing fault" — without state features, a
model may over- or under-flag depending on where in the operating envelope a
sample was collected.

## Health Index & RUL
**25. Why is the Health Index defined off the WORST (max) fault channel rather than an average?**
An asset's health is limited by its most severe active fault; averaging
across mostly-zero channels would understate risk from one badly degrading
component.

**26. Why does `estimate_rul.m` return NaN instead of a number when the HI trend isn't decreasing?**
Extrapolating a flat/increasing trend to a "time to critical" would be
fabricating a number with no support in the data — the brief explicitly
prohibits claiming RUL accuracy that isn't validated (§25/§51).

**27. What would you need to add an ML-based RUL model, and why hasn't it been built yet?**
A labeled sequence dataset of full degradation trajectories and a sequence
model (LSTM/TCN); it's listed as future work rather than fabricated because
building and validating it properly is out of scope for the phases completed
so far.

## Digital Twins
**28. In what sense is the thermal model a "digital twin" and not just a simulation?**
It mirrors a specific real asset's structure (a data-hall zone served by this
pump/fan pair) with parameters intended to be calibrated against that asset,
and is driven by the SAME degradation state as the diagnostic signals — so
in principle it can run alongside a real system, informed by its sensors.

**29. Why a lumped RC model instead of a spatially resolved CFD thermal model?**
A first-order RC network captures the dominant thermal time-constant
behavior with far less computation, is easy to justify/parameterize, and is
sufficient to demonstrate the fault→thermal-consequence chain this project
targets — full CFD would be excessive for that goal.

## Simulink
**30. Why are MATLAB Function blocks used only at specific subsystem boundaries rather than one big block for the whole model?**
Large monolithic MATLAB Function blocks are hard to read, test, and debug;
keeping each block small and focused (fault coupling, online feature
extraction, Health Index, decision logic) mirrors good software-engineering
practice and matches the brief's explicit instruction to avoid monolithic
blocks (§38).

**31. Why do the MATLAB Function blocks re-express the math instead of calling the .m files directly?**
Simulink Coder-compatible MATLAB Function blocks can't call arbitrary
struct-returning .m functions; the block code re-expresses the same
documented equations in scalar/vector form, with the .m files remaining the
authoritative implementation used offline for dataset generation and ML
training.

**32. What's the fallback if the Dashboard blocks aren't available?**
Scope blocks — the model still runs and can be observed, just without the
richer Dashboard UI.

## Thermal Modeling
**33. Walk through the energy-balance equation in the thermal twin.**
`C_th·dT/dt = Q_IT - Q_cooling_effective`; `Q_cooling_effective` is the
nominal RC cooling term `C_th·(T-T_ambient)/τ` scaled by the degradation-
driven `effectiveness` factor — so as effectiveness drops, less heat is
removed for the same temperature difference, and T rises.

**34. Why floor `effectiveness` at 0.05 rather than letting it reach zero?**
To avoid dividing by zero or producing non-physical infinite heating rates
downstream; it's a numerical-safety floor, documented in
`cooling_effectiveness_from_degradation.m`.

## Predictive Maintenance
**35. What exactly does "predictive" mean in this project's decision engine, precisely?**
The decision engine escalates on Health Index, RUL, and thermal-margin
trends BEFORE the thermal safety threshold is actually violated — Experiment
9 measures the resulting lead time directly by comparing the timestamp of
first WARNING-or-worse against the timestamp the thermal margin would
otherwise cross zero.

**36. Why does the decision engine take the WORST of several signals rather than requiring all of them to agree?**
Requiring agreement would mask an early warning from any one signal that
happens to lag the others; taking the worst preserves the earliest possible
warning, consistent with the project's predictive intent.

## False Positives / Data Leakage
**37. How does `validate_project.m` check for data leakage specifically?**
It regenerates the scenario table and checks that every unique `scenario_id`
maps to exactly one split value (Train/Val/Test) — if any scenario appears in
more than one split, the check fails.

**38. Why is the "unseen operating condition" slice forced entirely into Test?**
To create a genuine generalization test (Experiment 10) — if any unseen-band
scenarios leaked into Train, the model would no longer be tested on truly
unseen conditions.

**39. In Experiment 6, why compute the adaptive threshold per (speed_bin, load_bin) from Healthy data only?**
Fixed thresholds computed across all operating conditions either false-alarm
at high load or miss faults at low load; per-bin thresholds from Healthy data
approximate the "normal for this operating condition" baseline that §20
calls an adaptive threshold.

## Validation
**40. What does the reproducibility check in `validate_project.m` actually verify?**
That calling `generate_scenarios(cfg, n)` twice with the same seed
(`rng(cfg.seed)` inside the function) produces identical `N_rpm`/`load_frac`
draws — proving the pipeline is deterministic given the seed.

**41. Why check fault-injection monotonicity rather than trusting the equations by inspection?**
An automated check catches a coding mistake (e.g., a sign error) that visual
inspection of the formula might miss, and gives a repeatable pass/fail record
rather than a one-time manual review.

## Edge Computing / Deployment
**42. What would MATLAB Coder buy you here, and why isn't it used yet (§37)?**
It would let the lightweight classifier/feature-extraction code be compiled
to deployable C/C++ for an edge device; it's listed as future work since
building and benchmarking a codegen path is a separate, non-trivial phase not
yet undertaken.

**43. What's the intended edge-inference pipeline conceptually?**
Raw sensor data → local filtering → feature extraction → lightweight model →
fault probability → local alarm, sending only summarized information
upstream — exactly the chain the online `10_Feature_Extraction`/
`11_Fault_Diagnosis`-style MATLAB Function blocks in the Simulink model are
built toward.

## Industrial Deployment / General
**44. Why did you choose a chilled-water pump and CRAC fan specifically?**
They're the two most common rotating/electromechanical assets whose failure
directly threatens data-center cooling capacity, giving a clean, well-scoped
pair of assets to demonstrate the full fault→consequence chain on.

**45. What would change if you deployed this on a real pump/fan instead of simulated data?**
Sensor noise/bias/Fs would need to be calibrated to the real hardware; the
fault-severity variable `D` (currently a known simulation input) would need
to be estimated purely from data since ground truth wouldn't be available;
and the thermal-twin parameters would need calibration against the real
data-hall's thermal response.

**46. What's the single biggest limitation of this project as it stands (be honest)?**
Every number is generated from a synthetic, reduced-order physics model — no
component has been validated against real sensor data or a real cooling
asset; the architecture and methodology transfer, but the specific numeric
results reported here are only as good as the synthetic model.

**47. Why keep an explicit reactive-vs-predictive comparison (Experiment 9) rather than just reporting the predictive system's numbers?**
Because the whole point of "predictive" maintenance is the improvement over
reactive maintenance — without a reactive baseline run on the identical
trajectory, there's no way to substantiate a claim of earlier warning or
lower peak temperature.

**48. Why did some faults (e.g., fan EfficiencyDegradation) get a smaller vibration signature by design?**
To deliberately create a "quiet" fault that stress-tests whether a
vibration-only model would miss it — this directly motivates the multimodal
fusion argument (Experiment 7/Model C) rather than assuming fusion helps.

**49. How would you extend this project to a third equipment type (e.g., a compressor)?**
Add its physics model (`src/physics/compressor_model.m`) and fault set
following the same severity-`D` coupling pattern, extend `cfg.equipment` and
`cfg.faults` in `project_config.m`, and everything downstream (sensors,
features, ML, HI/RUL, thermal twin, decision engine) already generalizes
since none of it hard-codes "Pump" or "Fan" beyond the physics-selection
switch statements.

**50. If your classifier reports 60% recall instead of the >90% target in §33, what do you do?**
Report the actual 60% honestly, investigate why (e.g., insufficient
scenario diversity, a fault whose signature overlaps another's, a feature
set gap), improve the methodology, and re-validate — never adjust the data
or labels to hit the target, per §51.
