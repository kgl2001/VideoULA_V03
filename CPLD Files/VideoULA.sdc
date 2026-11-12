# VideoULA Timing Constraints
# Target: Atmel ATF1504AS (Rev03) / Xilinx XC9572XL (Rev02)

# Primary clock: 48MHz oscillator
create_clock -name CLK_48M -period 20.833 [get_ports CLK_48M]

# Primary clock: 16MHz from BBC Micro	
create_clock -name CLK_16M -period 62.5 [get_ports CLK_16M]

# CLK_16M: static/async inputs â€” no timing analysis needed
set_false_path -from [get_ports CLK_SEL]
set_false_path -from [get_ports CLK_16M]

# All other inputs are only sampled on mhz16_clken (every 62.5ns minimum â€”
# one 16MHz cycle). Strict 48MHz timing analysis is not meaningful for these
# signals, so use false paths to avoid spurious timing violations.
set_false_path -from [get_ports {nCS A D[*] DISEN CURSOR R_IN G_IN B_IN SRAM_DATA[*]}]

# Output clocks: these are direct bit taps from clk_counter â€” fast paths
set_false_path -to [get_ports {CLK_8M CLK_4M CLK_2M CLK_1M CLK_CRTC CLK_6M}]

# Other outputs: only update on mhz16_clken, so false paths are appropriate
set_false_path -to [get_ports {R G B SRAM_ADDR[*] SRAM_nWE SRAM_DATA[*]}]
