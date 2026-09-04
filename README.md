# VideoULA V03 — BBC Micro Video ULA Replacement
## 44-pin Atmel ATF1504AS CPLD Version

This repository contains the hardware design and firmware for the VideoULA V03, a drop-in replacement for the VC2069 Video ULA (IC6) in the Acorn BBC Micro Model B and Master 128.

---

## Project Overview

The original BBC Micro Video ULA (IC6) is a custom ASIC that is no longer manufactured. Failed or missing ULAs result in a non-functional machine. This project provides a modern replacement using a CPLD and a small external SRAM for palette storage.

There are three hardware versions of this replacement, each in a separate repository:

| Version | CPLD | Macrocells | Tool | Repository |
|---|---|---|---|---|
| V01 | Xilinx XC9572XL-10-VQ44 | 72 | ISE 14.7 | [VideoULA_V01](https://github.com/kgl2001/VideoULA_V01) |
| V02 | Xilinx XC9572XL-10-VQ64 | 72 | ISE 14.7 | [VideoULA_V02](https://github.com/kgl2001/VideoULA_V02) |
| **V03** | Atmel ATF1504AS-10AU44 | 64 | Quartus 13.0 SP1 | This repo |

All three versions share the same 28-pin DIP footprint as the original ULA and are pin-compatible with the BBC Micro motherboard.

---

## V03 Hardware

- **CPLD**: Atmel ATF1504AS-10AU44 (64 macrocells, 5V) — still in production
- **SRAM**: ISSI IS62C256AL-45TLI (32K×8, 5V, TSOP-28, 45ns) — only locations 0-15 and bits 0-3 used
- **Oscillator**: 48MHz SMD oscillator (3225 package, 5V) — optional in 16MHz mode
- **Clock buffer**: 74LVC1G17 (SOT-23) — Schmitt trigger buffer on 16MHz CLK_IN
- **No LDO required** — everything runs at 5V

### Key differences from V01/V02

- **5V CPLD** — ATF1504AS operates at 5V throughout, no LDO required
- **Higher output voltage** — 5V logic outputs directly compatible with Master 128 custom ICs requiring higher logic 1 voltage; no output clock buffering needed
- **Still in production** — ATF1504AS is actively manufactured by Microchip, unlike the obsolete XC9572XL
- **64 macrocells** — slightly fewer than the XC9572XL's 72, but sufficient for the design (52/64 used in 48MHz build)
- **Quartus 13.0 SP1** — uses Altera/Intel Quartus instead of Xilinx ISE
- **Separate CLK_16M and CLK_48M GCK pins** — no solder bridge needed to switch modes

### Hardware Revisions

| Revision | Status | Changes |
|---|---|---|
| Rev01 | PCB designed, not yet built or tested | Initial release |

---

## Firmware

The firmware is written in Verilog and built using Altera Quartus 13.0 SP1. The same Verilog source file (`src/VideoULA.v`) is shared between V02 and V03.

The Quartus project targets the `EPM7064STC44-10` device — the Altera MAX7000S equivalent of the ATF1504AS, which Quartus supports natively. The `.pof` output is converted to a `.jed` file using the `pof2jed` utility for programming the ATF1504AS.

### Operating Modes

Two firmware builds are required — one per operating mode. Both CLK_16M and CLK_48M are wired to dedicated GCK pins, so no hardware changes are needed to switch modes — simply reprogram the CPLD with the appropriate `.jed` file.

#### 48MHz Mode (recommended)
- Uses the onboard 48MHz oscillator as the master clock
- Generates all BBC clock outputs (8/4/2/1MHz, CRTC, 6MHz) internally
- Provides clean, phase-locked 6MHz output for the SAA5050 teletext chip (tD ≈ 20ns ✓)
- Works reliably on all machines from cold power-up
- Build: uncomment `` `define CLK_48MHZ `` in `VideoULA.v`

#### 16MHz Mode
- Uses the BBC motherboard's 16MHz clock as the master clock (via Schmitt trigger buffer)
- The 48MHz oscillator is optional in 16MHz mode:
  - **Not fitted**: BBC's existing 6MHz circuit drives the SAA5050 as normal
  - **Fitted**: CPLD generates clean phase-locked 6MHz output (connect via IC37 replacement board)
- Build: uncomment `` `define CLK_16MHZ `` in `VideoULA.v`

### Quartus Build Instructions

1. Open Altera Quartus 13.0 SP1
2. Open `VideoULA.qpf`
3. Select the operating mode by uncommenting the appropriate `define` in `src/VideoULA.v`
4. Run `Start Compilation` (Ctrl+L)
5. Convert the output `.pof` file to `.jed` using `pof2jed`
6. Program the ATF1504AS using the V03 programmer board (see below)

### Programming the ATF1504AS

Unlike V01 and V02, the V03 board does not have an onboard JTAG connector. This is because the ATF1504AS shares its JTAG pins with I/O pins used by the BBC Micro bus interface — they cannot be used for JTAG programming while the board is installed in the computer.

To program the V03 board, a dedicated programmer board is required. This programmer:

- Accepts the V03 VideoULA board as a plug-in module
- Is powered from the BBC Micro auxiliary power socket (Molex +5V/+12V connector)
- Has a switch to select between normal I/O mode and JTAG programming mode
- Has a standard JTAG header for connection to a compatible JTAG programmer (e.g. running ATMISP)

The KiCAD design files for the programmer board and FreeCAD design files for a suitable enclosure are included in this repository.

**Programming procedure:**
1. Remove the V03 board from the BBC Micro
2. Insert the V03 board into the programmer
3. Connect the programmer to the BBC Micro auxiliary power socket
4. Connect a JTAG programmer to the JTAG header on the programmer board
5. Set the switch to JTAG programming mode
6. Program the `.jed` file using ATMISP or compatible software
7. Set the switch back to I/O mode
8. Remove the V03 board from the programmer and reinstall in the BBC Micro

### Quartus Warning Suppression

The following warnings are suppressed in the `.qsf` and are expected/harmless:

| Message | Reason |
|---|---|
| 15705 | Unused clock port pin assignment (expected when only one clock mode is built) |
| 20028 | Parallel compilation not licensed — informational only |
| 199027 | Output file format — `.pof` is generated correctly |
| 332174, 332049 | Timing analysis informational messages |
| 335095 | TimeQuest latch analysis — no latches in design |

---

## SRAM Wiring

The external SRAM stores the 16-entry colour palette (4 bits per entry):

| SRAM Pin | Connection |
|---|---|
| A0-A3 | CPLD SRAM_ADDR[0:3] |
| A4-A14 | GND (tie low) |
| D0-D3 | CPLD SRAM_DATA[0:3] (bidirectional) |
| D4-D7 | Leave unconnected |
| /WE | CPLD SRAM_nWE |
| /OE | GND (always output enabled) |
| /CS | GND (always selected) |

---

## 6MHz Clock for Mode 7 (Teletext)

- **48MHz mode**: CLK_6M pin provides clean phase-locked 6MHz (tD ≈ 20ns ✓). Connect to SAA5050 via IC37 replacement board.
- **16MHz mode, oscillator fitted**: CLK_6M provides clean phase-locked 6MHz, self-correcting every 1µs. Connect via IC37 replacement board.
- **16MHz mode, oscillator not fitted**: CLK_6M output ignored. BBC motherboard's existing 6MHz circuit used as normal.

---

## PCB Design Notes

The PCB has been designed using KiCAD V10 as a 2-layer board. It can easily be changed to a 4-layer board with GND/Power planes on the inner layers if signal integrity is a concern.

### JLCPCB Fabrication

The board design includes a 5×5mm silkscreen box on the underside of the PCB. This is used by JLCPCB to position a QR code serial number. When ordering from JLCPCB:

- Select **Specify position** in the QR code / 2D barcode options during the ordering process
- If this option is not selected, JLCPCB will print the 5×5mm silkscreen box as-is and attempt to place the QR code at a different location of their choosing

If not using JLCPCB, the chosen fabricator will likely print the 5×5mm box as a plain white square on the PCB. To avoid this, remove the silkscreen box from the PCB design and regenerate the Gerber files before submitting.

### Assembly

A combined CPL (Component Placement List) and BOM (Bill of Materials) Excel file is included in the Gerbers folder. This can be used directly with the JLCPCB PCBA (PCB Assembly) service.

Note that the JLCPCB Economy PCBA process only assembles components on one side of the PCB. Select the **top side** for assembly — this leaves only the SRAM and its associated decoupling capacitor to be hand soldered to the underside of the board.

---

## Known Limitations

- **SCART/HDMI adapter compatibility**: Some SCART→HDMI display adapters may show minor pixel artefacts with non-standard screen modes. RGBtoHDMI and direct CRT connections are not affected.

---

## Compatibility

Designed for BBC Micro Model B and Master 128. The 5V CPLD outputs are directly compatible with the higher logic 1 voltage required by some Master 128 custom ICs.

---

## Credits

- **Ken Lowe** — PCB design, Verilog development and testing
- **hoglet (Stardot forums)** — Clock architecture analysis, DRAM timing analysis, community testing
- **Stardot community** — Testing, feedback and suggestions

---

## Licence

Hardware: [Creative Commons BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

Firmware: [MIT Licence](https://opensource.org/licenses/MIT)
