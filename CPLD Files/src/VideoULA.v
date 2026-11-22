`timescale 1ns / 1ps
/************************************************************************
VideoULA.v
VideoULA V02/V03 - A replacement Video ULA for the BBC Micro
Build 7 - November 2026 - Unified build. One firmware now supports both
                   the 48MHz and 16MHz modes; the mode is selected by the
                   CLK_SEL input (pin 39, JP1). Pin 39 has a 10K pull-up, so
                   with JP1 open the CPLD runs in 48MHz mode. Bridging JP1 to
                   GND selects 16MHz mode. The state of pin 39 is read at all
                   times, so power-cycle after changing JP1.
Build 6 - November 2026 - SRAM palette write fix. The write is split into a
                   prepare cycle (address driven, nWE high) and a write cycle
                   (nWE low, data driven), so the address is stable before nWE
                   falls. The address setup problem was identified by hoglet,
                   who also proposed a fix. It became apparent with the faster
                   SRAM radiofan was using, and radiofan's fix (a slightly
                   different approach with the same result) is used here. The
                   data bus is only driven during the nWE cycle (hoglet), using
                   a registered enable.
                   In 16MHz mode CLK_6M is now generated from CLK_16M (edge
                   pattern based on radiofan's approach, retimed so tD is
                   about 31ns). The 48MHz oscillator is no longer needed in
                   the 16MHz build.
Build 5 - November 2026 - Mode 7 cursor delay reduced to cursor_invert[0]
                   (one stage, 62.5ns). Gives a correctly aligned mode 7
                   cursor on Master and Model B with the CPLD generating the
                   6MHz.
Build 4 - November 2026 - Cursor alignment fix. Modes 0-6 cursor now uses
                   cursor_invert0 (no delay); mode 7 cursor uses cursor_invert[1].
Build 3 - August 2026 - 16MHz build: CLK_6M from CLK_48M phase
                   locked to CLK_1M via CLK_1M rising edge detection.
                   Both CLK_16M and CLK_48M connected in 16MHz build.

(C) Ken Lowe July 2026.
Community contributions: hoglet (Stardot forums) - unified clock architecture

------------------------------------------------------------------------
CLOCK SELECTION - CLK_SEL (pin 39, JP1)
------------------------------------------------------------------------
JP1 open (CLK_SEL = 1, pulled up): 48MHz mode (recommended).
  48MHz oscillator on CLK_48M pin (GCK).
  Generates CLK_6M for SAA5050 teletext chip.

JP1 bridged to GND (CLK_SEL = 0): 16MHz mode.
  16MHz from BBC motherboard on CLK_16M pin (GCK) via Schmitt trigger.
  CLK_6M is generated from CLK_16M (6 edges per 8 clocks, using both clock
  edges). If CLK_6M is not connected to the teletext IC, the machine's own
  6MHz is used.
------------------------------------------------------------------------

Clock architecture (unified clk_counter in both modes):
  A 4-bit clk_counter divides the effective 16MHz clock.

  48MHz mode: 2-bit prescaler divides CLK_48M by 3 → mhz16_clken
  16MHz mode: mhz16_clken = 1 (every CLK_16M tick)

  CLK_8M   = clk_counter[0]  (direct bit tap)
  CLK_4M   = clk_counter[1]  (direct bit tap)
  CLK_2M   = clk_counter[2]  (direct bit tap)
  CLK_1M   = clk_counter[3]  (direct bit tap)
  CLK_CRTC = clk_counter[2] or clk_counter[3] per r0_crtc_2mhz

  CLK_6M:
    48MHz mode: state decode from {clk_counter, clk_prescaler}
      tD = 20.83ns before CLK_1M falls ✓ (SAA5050 requires 6-60ns)
    16MHz mode: rising-edge toggle XOR falling-edge toggle on CLK_16M,
      tD about 31ns ✓ (edge spacing has fixed jitter of about 10ns)

  pixel_reg sampled on posedge at end of DRAM access cycle x111:
    DRAM nCAS asserted at x110 (via IC45 74S139, ~12ns delay)
    DRAM data valid after ~67ns (55ns HM4816A-3 + 12ns IC45) ✓
    All logic on posedge — no mixed-edge clocking.

Palette storage: external SRAM
  SRAM_ADDR[3:0] <- palette index (logical colour)
  SRAM_DATA[3:0] <-> palette data (physical colour)
  SRAM_nWE       <- write enable (active low)
  Write pulse = one 16MHz cycle = 62.5ns > tWP=25ns min (IS62C256AL-45).
  Faster 5V parts have shorter tWP but are not necessarily more tolerant
  of address/nWE skew (see SRAM PALETTE INTERFACE note below).

Target devices:
  V02: Xilinx XC9572XL-10-VQ64 (72 macrocells) — ISE
  V03: Atmel ATF1504AS-10AU44  (64 macrocells) — Quartus
************************************************************************/

// ------------------------------------------------------------------------
// SRAM PALETTE WRITE TIMING - select at build time
// ------------------------------------------------------------------------
// A palette write takes three cycles of the 8-cycle clk_counter: capture the
// address from D[7:4], prepare (address driven, nWE high), then write (nWE low,
// data driven). The ULA control register write also happens in the prepare cycle.
//
// Default (define commented out) - EARLY timing:
//   capture = cycle 1, prepare = cycle 2, write = cycle 3 (clk_counter 001/010/011).
//   Only one counter bit changes between the prepare and write cycles, so the
//   address mux select cannot glitch between them.
//
// `define SRAM_WRITE_LATE - LATE timing:
//   capture = cycle 2, prepare = cycle 3, write = cycle 4 (clk_counter 010/011/100).
//   All three counter bits change between prepare and write, which can produce a
//   brief glitch on the address mux select and may need slightly more logic.
//   The ULA control register write also happens one cycle later.
//
// Both timings give the SRAM one full cycle of address setup before nWE falls.
//`define SRAM_WRITE_LATE

module VideoULA (
    input  wire        CLK_48M,     // 48MHz oscillator (GCK pin)
    input  wire        CLK_16M,     // 16MHz from BBC via Schmitt trigger (GCK pin)
    input  wire        CLK_SEL,     // pin 39: 1 = 48MHz mode, 0 = 16MHz mode
    output wire        CLK_8M,
    output wire        CLK_4M,
    output wire        CLK_2M,
    output wire        CLK_1M,
    output wire        CLK_CRTC,
    output wire        CLK_6M,
    input  wire        nCS,
    input  wire        A,
    input  wire [7:0]  D,
    input  wire        DISEN,
    input  wire        CURSOR,
    input  wire        R_IN,
    input  wire        G_IN,
    input  wire        B_IN,
    output wire        R,
    output wire        G,
    output wire        B,
    output wire [3:0]  SRAM_ADDR,
    inout  wire [3:0]  SRAM_DATA,
    output wire        SRAM_nWE
);

    // =========================================================================
    // ULA CONTROL REGISTER (R0) FIELDS
    // =========================================================================
    reg        r0_cursor0    = 1'b0;
    reg        r0_cursor1    = 1'b0;
    reg        r0_cursor2    = 1'b0;
    reg        r0_crtc_2mhz = 1'b0;
    reg [1:0]  r0_pixel_rate = 2'b00;
    reg        r0_teletext   = 1'b0;
    reg        r0_flash      = 1'b0;

    // =========================================================================
    // PIXEL SHIFT REGISTER & CRTC DISPLAY ENABLE
    // =========================================================================
    reg [7:0] pixel_reg  = 8'hFF;
    reg       crtc_disen = 1'b0;

    // =========================================================================
    // CLOCK GENERATION
    // =========================================================================
    reg [3:0] clk_counter = 4'b0000;
    wire mhz16_clken;
    wire sel48 = CLK_SEL;
    wire clk_main = sel48 ? CLK_48M : CLK_16M;

    // ---- 48MHz mode: prescaler and 6MHz state decode (CLK_48M) ----
    reg [1:0] clk_prescaler = 2'b00;
    reg       clk_6m_reg    = 1'b0;

    // Prescaler and 6MHz decode run on clk_main (= CLK_48M in 48MHz mode) so they share
    // the same clock path as clk_counter. In 16MHz mode they free-run and are unused.
    always @(posedge clk_main) begin
        if (clk_prescaler[1])
            clk_prescaler <= 2'b00;
        else
            clk_prescaler <= clk_prescaler + 1'b1;
    end

    wire [5:0] clk6m_state = {clk_counter, clk_prescaler};
    always @(posedge clk_main)
        if (clk6m_state == 6'b000010 || clk6m_state == 6'b001101 || clk6m_state == 6'b011000 ||
            clk6m_state == 6'b100010 || clk6m_state == 6'b101101 || clk6m_state == 6'b111000)
            clk_6m_reg <= 1'b0;
        else if (clk6m_state == 6'b001000 || clk6m_state == 6'b010010 || clk6m_state == 6'b011101 ||
                 clk6m_state == 6'b101000 || clk6m_state == 6'b110010 || clk6m_state == 6'b111101)
            clk_6m_reg <= 1'b1;

    assign mhz16_clken = ~sel48 | clk_prescaler[1];

    always @(posedge clk_main)
        if (mhz16_clken)
            clk_counter <= clk_counter + 1'b1;

    // ---- 16MHz mode: 6MHz from CLK_16M (rising toggle XOR falling toggle) ----
    reg [2:0] cnt_pos = 3'd0;
    reg       tgl_pos = 1'b1;
    reg       tgl_neg = 1'b0;

    always @(posedge CLK_16M) begin
        cnt_pos <= cnt_pos + 3'd1;
        if (cnt_pos == 3'd0 || cnt_pos == 3'd1 || cnt_pos == 3'd4 || cnt_pos == 3'd5)
            tgl_pos <= ~tgl_pos;
    end

    always @(negedge CLK_16M) begin
        if (cnt_pos == 3'd3 || cnt_pos == 3'd7)
            tgl_neg <= ~tgl_neg;
    end

    assign CLK_6M = sel48 ? clk_6m_reg : (tgl_pos ^ tgl_neg);

    assign CLK_8M   = clk_counter[0];
    assign CLK_4M   = clk_counter[1];
    assign CLK_2M   = clk_counter[2];
    assign CLK_1M   = clk_counter[3];
    assign CLK_CRTC = r0_crtc_2mhz ? clk_counter[2] : clk_counter[3];

    // =========================================================================
    // CLOCK ENABLES
    // =========================================================================
    // SRAM palette write: address loaded in cycle 1, address driven in cycle 2
    // (prepare), nWE low and data driven in cycle 3.
`ifdef SRAM_WRITE_LATE
    localparam [2:0] WR_CAPTURE = 3'd2, WR_PREP = 3'd3, WR_DO = 3'd4;
`else
    localparam [2:0] WR_CAPTURE = 3'd1, WR_PREP = 3'd2, WR_DO = 3'd3;
`endif
    wire r0_data_ready    = (~nCS) & (clk_counter[2:0] == WR_CAPTURE);
    wire r0_prepare_write = (~nCS) & (clk_counter[2:0] == WR_PREP);
    wire r0_do_write      = (~nCS) & (clk_counter[2:0] == WR_DO);

    wire crtc_clken = (r0_crtc_2mhz  & (clk_counter[2:0] == 3'b111)) |
                      (~r0_crtc_2mhz & (clk_counter[3:0] == 4'b1111));

    wire pixel_clken =
        (r0_pixel_rate == 2'b11) ? 1'b1 :
        (r0_pixel_rate == 2'b10) ? clk_counter[0] :
        (r0_pixel_rate == 2'b01) ? (clk_counter[0] & clk_counter[1]) :
                                   (clk_counter[0] & clk_counter[1] & clk_counter[2]);

    // =========================================================================
    // REGISTER WRITES
    // =========================================================================
    always @(posedge clk_main) begin
        if (mhz16_clken) begin
            if (r0_prepare_write & ~A) begin
                r0_cursor0    <= D[7];
                r0_cursor1    <= D[6];
                r0_cursor2    <= D[5];
                r0_crtc_2mhz <= D[4];
                r0_pixel_rate <= D[3:2];
                r0_teletext   <= D[1];
                r0_flash      <= D[0];
            end
        end
    end

    // =========================================================================
    // SRAM PALETTE INTERFACE
    // Palette write is split over two cycles. In the prepare cycle the
    // address (from sram_addr_reg) is driven while nWE is still high. nWE then
    // goes low in the following cycle, so the address is stable before nWE
    // (SRAM tSA = 0ns). SRAM_DATA is only driven during the nWE cycle, so
    // the CPLD does not fight the SRAM output (SRAM /OE is tied low).
    // sram_addr_reg is loaded from D[7:4] in the cycle before the prepare cycle.
    wire sram_pre_write = r0_prepare_write & A;
    wire sram_do_write  = r0_do_write & A;
    wire sram_busy      = sram_pre_write | sram_do_write;

    reg [3:0] sram_addr_reg = 4'b0000;
    always @(posedge clk_main)
        if (mhz16_clken & r0_data_ready)
            sram_addr_reg <= D[7:4];

    wire [3:0] log_col = {pixel_reg[7], pixel_reg[5], pixel_reg[3], pixel_reg[1]};

    assign SRAM_ADDR = sram_busy ? sram_addr_reg : log_col;
    assign SRAM_nWE  = ~sram_do_write;
    // Data-bus enable is registered: set in the prepare cycle, so it is high
    // for the nWE cycle only (a combinational enable fitted badly in 16MHz mode).
    reg sram_oe_reg = 1'b0;
    always @(posedge clk_main)
        if (mhz16_clken) sram_oe_reg <= sram_pre_write;
    assign SRAM_DATA = sram_oe_reg ? D[3:0] : 4'bZZZZ;

    wire [3:0] phy_col = SRAM_DATA;

    // =========================================================================
    // PIXEL SHIFT REGISTER
    // =========================================================================
    always @(posedge clk_main) begin
        if (mhz16_clken) begin
            if (pixel_clken) begin
                if (crtc_clken) begin
                    pixel_reg  <= D;
                    crtc_disen <= DISEN;
                end else begin
                    pixel_reg  <= {pixel_reg[6:0], 1'b1};
                end
            end
        end
    end

    // =========================================================================
    // CURSOR GENERATION
    // =========================================================================
    reg [3:0] cursor_invert = 4'b0000;
    reg       cursor_active  = 1'b0;
    reg [1:0] cursor_counter = 2'b00;

    wire cursor_invert0 = cursor_active &
                          ((r0_cursor0 & ~cursor_counter[0] & ~cursor_counter[1]) |
                           (r0_cursor1 &  cursor_counter[0] & ~cursor_counter[1]) |
                           (r0_cursor2 &  cursor_counter[1]));

    always @(posedge clk_main) begin
        if (mhz16_clken) begin
            cursor_invert[0] <= cursor_invert0;
            cursor_invert[1] <= cursor_invert[0];
            cursor_invert[2] <= cursor_invert[1];
            cursor_invert[3] <= cursor_invert[2];
            if (crtc_clken) begin
                if (CURSOR | cursor_active) begin
                    cursor_active <= 1'b1;
                    if (cursor_counter == 2'b11)
                        cursor_active <= 1'b0;
                    cursor_counter <= cursor_active ? cursor_counter + 1'b1 : 2'b00;
                end
            end
        end
    end

    // =========================================================================
    // PIXEL GENERATION
    // =========================================================================
    wire red_val   = (phy_col[3] & r0_flash) ^ ~phy_col[0];
    wire green_val = (phy_col[3] & r0_flash) ^ ~phy_col[1];
    wire blue_val  = (phy_col[3] & r0_flash) ^ ~phy_col[2];

    reg RR = 1'b0;
    reg GG = 1'b0;
    reg BB = 1'b0;

    always @(posedge clk_main) begin
        if (mhz16_clken) begin
            if (~sram_busy) begin
                // Modes 0-6: cursor_invert0 has no delay, so the cursor lines up
                // with the palette lookup latency. Do not use cursor_invert0 in
                // the teletext mux below as well: routing both fails to fit.
                RR <= (red_val   & crtc_disen) ^ cursor_invert0;
                GG <= (green_val & crtc_disen) ^ cursor_invert0;
                BB <= (blue_val  & crtc_disen) ^ cursor_invert0;
            end
        end
    end

    // =========================================================================
    // OUTPUT MUX
    // =========================================================================
    // Mode 7: cursor_invert[0] (62.5ns) gives a correctly aligned cursor on a
    // Master and a Model B with the CPLD generating the 6MHz, and on a Model B
    // using the motherboard 6MHz. On a Master using the motherboard 6MHz the
    // cursor may be marginally (less than half a pixel) to the left. Feeding
    // the CPLD CLK_6M directly to the teletext IC gives the cleanest picture.
    assign R = r0_teletext ? (R_IN ^ cursor_invert[0]) : RR;
    assign G = r0_teletext ? (G_IN ^ cursor_invert[0]) : GG;
    assign B = r0_teletext ? (B_IN ^ cursor_invert[0]) : BB;

endmodule
