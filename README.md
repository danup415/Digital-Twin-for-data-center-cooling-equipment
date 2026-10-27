# Data-Center Cooling Digital Twin and Predictive Maintenance

A MATLAB/Simulink project for simulated predictive maintenance of data-center cooling equipment. It combines physics-informed models of chilled-water pumps and CRAC fans with virtual vibration and motor-current (MCSA) signals, fault diagnosis, remaining-useful-life estimation, and a reduced-order thermal digital twin.

The project also includes interactive demonstrations, generated datasets and results, a Simulink model, and an optional Ignition integration project. The core workflow is simulation-based and does not require physical equipment.

## What it does

- Simulates cooling demand and pump, fan, and motor behavior.
- Injects equipment faults and generates virtual sensor signals.
- Extracts vibration and motor-current features for multimodal diagnosis.
- Estimates equipment health and remaining useful life (RUL).
- Connects equipment degradation to cooling performance through a thermal digital twin.
- Compares reactive and predictive maintenance scenarios and produces figures, tables, and metrics.
- Provides interactive MATLAB and Simulink demonstrations, plus optional Ignition integration materials.

See [the architecture guide](docs/architecture.md) for system design and assumptions, [the equations reference](docs/equations.md) for model details, and [the project report](docs/report/report.md) for the full write-up and limitations.

## Requirements

- MATLAB R2024a
- Simulink
- Some signal-processing and machine-learning features use MATLAB toolboxes when available. The project documentation describes supported fallbacks and limitations.
- The Ignition integration is optional and has separate setup instructions in `docs/IGNITION_DIGITAL_TWIN_SETUP.md`.

## Run the project

Open MATLAB, set the current folder to the repository root, and run:

```matlab
main
```

The main workflow generates datasets, experiment outputs, figures and tables, and the Simulink model under the project folders. To run the experiments separately, use:

```matlab
run_all_experiments
```

For an interactive digital-twin demonstration, run `launch_cooling_digital_twin` from MATLAB. See `docs/INTERACTIVE_DIGITAL_TWIN.md` for details.

## Repository layout

```text
app/                 Interactive MATLAB digital-twin app and launcher
config/              Model, sensor, and project configuration
data/                Generated datasets and scenario manifests
demo/                Demonstrations and fault-progression examples
docs/                Architecture, equations, setup guides, and report
experiments/         Reproducible experiment entry points
ignition_project/    Optional Ignition integration assets and tools
models/              Physics, machine-learning, and Simulink models
results/              Generated figures, tables, and metrics
src/                 Simulation, sensing, signal processing, diagnosis, and twin code
tests/               MATLAB and integration checks
```

## Data and generated outputs

The repository includes the project’s current sample/generated datasets, trained model, Simulink model, figures, tables, and metrics so they can be inspected without first running the full workflow. Running the project may regenerate or overwrite outputs in `data/` and `results/`.

## Validation

Run `validate_project` in MATLAB for the project validation entry point. Additional validation scripts and test guidance are in `tests/` and `docs/`. Results depend on the MATLAB release, installed toolboxes, and the documented simplifying assumptions; this is a simulation project and does not establish performance on physical equipment.

## Limitations

This is a simulated research and demonstration project. Virtual sensors and reduced-order models are not a substitute for commissioning on real equipment. Review the assumptions and limitations in `docs/architecture.md` and `docs/report/report.md` before interpreting results.

## License

No license file is currently included. Unless a license is added, standard copyright rules apply and reuse permissions are not specified.
