# logArchitecture_dualLaserSynch
# Dual-Laser Bias Controller — Vivado Testing Guide

This guide explains how to simulate each testbench, run final top-level verification, and run synthesis and implementation in Vivado.

## 1. Repository files

### RTL design sources
Add these files as **Design Sources**:

- `power_estimator.v`
- `log_power_estimator.v`
- `error_calculator.v`
- `adaptive_bias_controller.v`
- `laser_bias_ctrl.v`

### Simulation testbenches
Add these files as **Simulation Sources** when running their corresponding tests:

- `tb_power_estimator.v`
- `tb_log_power_estimator.v`
- `tb_error_calculator.v`
- `tb_adaptive_bias_controller.v`
- `tb_laser_bias_ctrl.v`

`laserBias_control.m` is the MATLAB reference/controller script. It is not a Verilog design source and is not required for Vivado RTL simulation or synthesis.

> **Important:** A testbench is for simulation only. Do not use a `tb_...` module as the synthesis top.

---

## 2. Create or open the Vivado project

1. Open Vivado and create or open the project.
2. If creating a project, choose **RTL Project**.
3. Select the correct FPGA **part number** for your target board/device. Check the board documentation or exact device marking if unsure.
4. Add the five RTL files listed above under **Design Sources**.
5. Add the testbench files under **Simulation Sources**. You can add all of them now or add each testbench before running its test.
6. Check that the synthesis top-level design module is `laser_bias_ctrl`.

For an existing project, use **Add Sources**:
- Choose **Add or Create Design Sources** for the five RTL files.
- Choose **Add or Create Simulation Sources** for the testbench files.

---

## 3. Run each module testbench

Run each testbench separately. Keep the RTL design sources the same; change only the **simulation top** for each test.

### General procedure for each test

1. In **Sources**, expand **Simulation Sources**.
2. Find the testbench module for the test you want.
3. Right-click that `tb_...` module and choose **Set as Top**. Make sure the simulation top is the testbench, not the RTL design module.
4. If Vivado asks to update compile order, allow it.
5. In **Flow Navigator**, select **Run Simulation → Run Behavioral Simulation**.
6. Check the **Tcl Console** and **Messages** for `PASS`, `FAIL`, `$error`, or `$fatal` output.
7. If the testbench does not finish automatically, choose **Run All** in the simulator or enter `run all` in the simulation Tcl Console.
8. Save a screenshot of the console showing the test results if you need evidence for your report.
9. Close the simulation before selecting the next testbench.

### Test 1 — Power estimator

**Testbench:** `tb_power_estimator.v`

1. In **Simulation Sources**, right-click `tb_power_estimator` → **Set as Top**.
2. Run **Run Simulation → Run Behavioral Simulation**.
3. Check the console and waveform for mean-square results and `power_valid` behavior.
4. Confirm the expected pass results and no unexpected errors.

This test checks `power_estimator.v` independently.

### Test 2 — Log-power estimator

**Testbench:** `tb_log_power_estimator.v`

1. Right-click `tb_log_power_estimator` → **Set as Top**.
2. Run **Run Behavioral Simulation**.
3. Check the reported log-power values, `log_valid`, and zero-input case.
4. Confirm the expected pass results and no unexpected errors.

This test checks `log_power_estimator.v` independently. Its input is the mean-square value, not the original sample stream.

### Test 3 — Error calculator

**Testbench:** `tb_error_calculator.v`

1. Right-click `tb_error_calculator` → **Set as Top**.
2. Run **Run Behavioral Simulation**.
3. Check the error and compensated-error outputs, such as `dbg_err_q12` and `dbg_ep_q12`, or the corresponding testbench signals.
4. Confirm the expected pass results and no unexpected errors.

This test checks `error_calculator.v` independently.

### Test 4 — Adaptive bias controller

**Testbench:** `tb_adaptive_bias_controller.v`

1. Right-click `tb_adaptive_bias_controller` → **Set as Top**.
2. Run **Run Behavioral Simulation**.
3. Check bias updates, gain/shift selection, deadband behavior, and bias-limit handling.
4. Confirm the expected pass results and no unexpected errors.

This test checks `adaptive_bias_controller.v` independently.

### Test 5 — Complete laser bias controller

**Testbench:** `tb_laser_bias_ctrl.v`

1. Right-click `tb_laser_bias_ctrl` → **Set as Top**.
2. Run **Run Behavioral Simulation**.
3. Inspect the fixed-input tests and feedback-loop passes in the console.
4. Check that the test covers zero input, positive and negative samples, invalid sample cycles, bias limits, and feedback convergence.
5. In the current simplified feedback test, look for final stability checks (for example, `PASS: Bias stable at pass ...`) and the final summary. Check that there are no `FAIL`, `$error`, or `$fatal` messages.

This test verifies integration of the estimator, log conversion, error calculation, and adaptive bias controller. The testbench feedback loop is a simplified simulation model, not a full physical laser/photodetector model.

---

## 4. Add useful signals to the waveform

During behavioral simulation, add relevant signals to the Wave window. For the top-level test, useful signals include:

- `s_data`
- `s_valid`
- `dbg_mean`
- `dbg_lp_q12`
- `dbg_err_q12`
- `dbg_ep_q12`
- `bias_q11`
- `dbg_l_q16`
- `bias_valid`
- `status`
- `dbg_shift`
- `dbg_flip`

Select signals in the **Scopes/Objects** panes and choose **Add to Wave**, or use the context menu. Click **Zoom Fit** to show the full test. For the feedback test, zoom in on several consecutive passes if the full run makes individual changes difficult to see.

Take a screenshot showing important waveform signals and, separately if needed, the console's final pass/fail summary.

---

## 5. Final top-level verification before synthesis

1. Set `tb_laser_bias_ctrl` as the **simulation top**.
2. Run behavioral simulation again from the current source state.
3. Check the console for expected test results and ensure there are no unexpected errors.
4. Confirm that the final bias is within configured limits and that the feedback stability checks pass.
5. Save the final simulation screenshot and console summary for your report.

The simulation top for this step is `tb_laser_bias_ctrl`. The **synthesis top remains `laser_bias_ctrl`**.

---

## 6. Change the FPGA part number

If the project uses the wrong FPGA part, change it before relying on synthesis or implementation results.

1. If synthesis or implementation is running, cancel the run and wait for it to stop.
2. Open **Project Settings**. Depending on the Vivado version, use **Tools → Settings** or the settings icon.
3. Under **General**, find **Project Device** / **Part**.
4. Select the exact FPGA part for the target board. If available and appropriate, select the board through the board-selection option.
5. Click **Apply** and **OK**.
6. If Vivado asks whether to preserve the completed `synth_1` run state and apply the changes to a new run, choose **No** if you do not need to preserve the old run.
7. If `synth_1` is marked out of date, reset the run if necessary, then run synthesis again. Do not force old results to be marked up to date after changing the part.
8. Rerun implementation after the new synthesis completes.

**Why:** Synthesis and implementation results are device-specific. Results from the previous part number are not valid evidence for the new part.

---

## 7. Run synthesis

1. In **Sources → Design Sources**, right-click `laser_bias_ctrl` → **Set as Top**.
2. Verify that all five RTL modules are present and that testbenches are simulation-only sources.
3. In **Flow Navigator**, click **Run Synthesis**.
4. On a computer with 8 GB RAM, use **2 jobs** as a conservative starting point.
5. Wait for synthesis to complete. Open the synthesized design if Vivado offers that option.
6. Open **Reports → Report Utilization** or the utilization report for the synthesized design.
7. Record the resource counts for the selected FPGA, especially:
   - LUTs
   - Flip-flops / registers
   - Block RAM (BRAM)
   - DSP slices
   - I/O resources, where applicable
8. Check Messages and the synthesis log for errors or warnings that need attention.

Use resource numbers from the current part and source version, not from an earlier run.

---

## 8. Run implementation and check timing

1. After successful synthesis, click **Run Implementation** in the Flow Navigator.
2. Use **2 jobs** on an 8 GB RAM computer as a conservative setting.
3. Wait for implementation to complete.
4. Open the implemented design.
5. Generate or open **Report Utilization** and **Report Timing Summary**.
6. Record final utilization and timing information. Check whether clock and I/O constraints were provided and whether timing is met.
7. Review critical warnings, timing failures, or unrouted/unplaced errors reported by Vivado.

**Note:** Timing results are meaningful relative to the clock and I/O constraints applied to the project. If suitable constraints are absent, do not claim that the design meets a target clock frequency just because implementation completes.

---

## 9. Suggested evidence for a project report

Capture these items from the same final source version and FPGA part:

1. Console output for each of the five testbenches.
2. A waveform screenshot for the final `tb_laser_bias_ctrl` simulation.
3. The top-level test's pass/fail and feedback-stability summary.
4. The synthesis utilization report.
5. The implementation utilization report.
6. The timing summary.
7. The exact FPGA part number and clock constraints used.

## 10. Troubleshooting checklist

- **Wrong test runs:** Right-click the intended `tb_...` module in **Simulation Sources** and choose **Set as Top**.
- **Testbench appears in synthesis:** Set `laser_bias_ctrl` as the design top and keep `tb_...` files as simulation-only sources.
- **Module not found / unresolved module:** Check that all five RTL files are under Design Sources and that module names match the instantiations.
- **Run says out of date after changing the part:** Reset and rerun synthesis, then rerun implementation.
- **No visible waveform signals:** Add signals from the Objects/Scopes panes to the Wave window and click **Zoom Fit**.
- **Simulation stops on an error:** Read the first relevant `$error`, `$fatal`, or compile error in the Tcl Console and fix that issue before continuing.

---

## Quick reference

| Purpose | Top module |
|---|---|
| Power-estimator simulation | `tb_power_estimator` |
| Log-power simulation | `tb_log_power_estimator` |
| Error-calculator simulation | `tb_error_calculator` |
| Adaptive-controller simulation | `tb_adaptive_bias_controller` |
| Full-system simulation | `tb_laser_bias_ctrl` |
| Synthesis and implementation | `laser_bias_ctrl` |
