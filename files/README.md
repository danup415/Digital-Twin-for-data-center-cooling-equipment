# Data-Center Cooling Digital Twin and Predictive Maintenance

This directory contains the MATLAB entry points and a copy of the main project guide for the full repository. The simulation models, configuration, data, experiments, and documentation remain in the repository root and its other folders.

The project simulates predictive maintenance for data-center chilled-water pumps and CRAC fans. It combines physics-informed equipment models, virtual vibration and motor-current (MCSA) signals, fault diagnosis, remaining-useful-life estimation, and a reduced-order thermal digital twin. It is simulation-based and does not require physical equipment.

## Requirements

- MATLAB R2024a
- Simulink
- Signal-processing and machine-learning toolboxes are used where available; see the project documentation for fallbacks and limitations.

## Run from the repository root

In MATLAB, set the current folder to the repository root, add this directory to the MATLAB path, then call the main function:

```matlab
addpath('files')
main
```

To run experiments individually, use:

```matlab
run_all_experiments
```

For the interactive digital-twin app, run `launch_cooling_digital_twin` after adding this directory to the path.

## Project documentation

- [Architecture](../docs/architecture.md)
- [Equations and model details](../docs/equations.md)
- [Project report and limitations](../docs/report/report.md)
- [Interactive digital twin guide](../docs/INTERACTIVE_DIGITAL_TWIN.md)
- [Ignition setup (optional)](../docs/IGNITION_DIGITAL_TWIN_SETUP.md)

The full project includes generated datasets, trained model files, a Simulink model, experiment outputs, and validation scripts. Results are simulation outputs and do not establish performance on physical equipment.

## License

No license file is included; reuse permissions are not specified.
