# Test build: unified 16MHz / 48MHz firmware (V02/V03 Build 7)

This is a test branch. One firmware now supports both clock modes, so the CPLD does not need
reprogramming to change mode. Pin 39 (solder bridge JP1 on the V03 board) selects the mode:

- **JP1 open (default): 48MHz mode.**
- **JP1 bridged to GND: 16MHz mode.**

Please power-cycle after changing JP1.

To try it, replace `VideoULA.qsf`, `VideoULA.sdc` and `src/VideoULA.v` in your Quartus project with
the ones in this branch (the `.qsf` has a new pin 39 assignment, and the `.sdc` has timing
constraints for the mode select), compile, and program as usual. The macrocell count is 61/64.

## What to report

Just: **does it work in the mode you normally use, and which machine (Model B or Master) are you using?**

Anything that looks wrong is also useful, for example noise on the screen, a corrupted palette,
or a mode 7 cursor that isn't where you expect it. You don't need to test every combination.

The cursor results we have so far are in the cursor tables in `CPLD Files/README.md`.
