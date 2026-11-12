`timescale 1ns / 1ps
/************************************************************************
VideoULA.v
VideoULA V02/V03 - A replacement Video ULA for the BBC Micro
Build 3 - August 2026 - 16MHz build: CLK_6M from CLK_48M phase
                   locked to CLK_1M via CLK_1M rising edge detection.
                   Both CLK_16M and CLK_48M connected in 16MHz build.

(C) Ken Lowe July 2026.
Community contributions: hoglet (Stardot forums) - unified clock architecture

------------------------------------------------------------------------
CLOCK CONFIGURATION - uncomment ONE define only
------------------------------------------------------------------------
`define CLK_48MHZ
  48MHz oscillator on CLK_48M pin (GCK).
  Generates CLK_6M for SAA5050 teletext chip.
  CLK_16M pin unused.

`define CLK_16MHZ
  16MHz from BBC motherboard on CLK_16M pin (GCK) via Schmitt trigger.
  CLK_6M held high-Z.
  CLK_48M pin unused (oscillator not required).
------------------------------------------------------------------------

Clock architecture (unified clk_counter in both modes):
  A 4-bit clk_counter divides the effective 16MHz clock.

  48MHz mode: 2-bit prescaler divides CLK_48M by 3 → mhz16_clken
  16MHz mode: mhz16_clken = 1 (every CLK_IN tick)

  CLK_8M   = clk_counter[0]  (direct bit tap)
  CLK_4M   = clk_counter[1]  (direct bit tap)
  CLK_2M   = clk_counter[2]  (direct bit tap)
  CLK_1M   = clk_counter[3]  (direct bit tap)
  CLK_CRTC = clk_counter[2] or clk_counter[3] per r0_crtc_2mhz

  CLK_6M (48MHz mode only):
    State decode from {clk_counter, clk_prescaler}
    tD = 20.83ns before CLK_1M falls ✓ (SAA5050 requires 6-60ns)

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
// CLOCK CONFIGURATION - uncomment ONE define only
// ------------------------------------------------------------------------
`define CLK_48MHZ
//`define CLK_16MHZ

`ifdef CLK_48MHZ
  `ifdef CLK_16MHZ
    ERROR_BOTH_CLOCK_DEFINES_SET
  `endif
`endif

module VideoULA (
    input  wire        CLK_48M,     // 48MHz oscillator (GCK pin in 48MHz mode;
                                   // optional CLK_6M source in 16MHz mode)
`ifdef CLK_16MHZ
    input  wire        CLK_16M,     // 16MHz from BBC via Schmitt trigger (GCK pin)
`endif
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

`ifdef CLK_48MHZ
    // 2-bit prescaler: divides CLK_48M by 3 → mhz16_clken every 3rd tick
    reg [1:0] clk_prescaler = 2'b00;
    reg       clk_6m_reg    = 1'b0;

    always @(posedge CLK_48M) begin
        if (clk_prescaler[1])
            clk_prescaler <= 2'b00;
        else
            clk_prescaler <= clk_prescaler + 1'b1;
    end

    // CLK_6M: phase locked via {clk_counter, clk_prescaler} state decode
    // tD = 20.83ns before CLK_1M falls ✓ (SAA5050 requires 6-60ns)
    wire [5:0] clk6m_state = {clk_counter, clk_prescaler};
    always @(posedge CLK_48M)
        if (clk6m_state == 6'b000010 || clk6m_state == 6'b001101 || clk6m_state == 6'b011000 ||
            clk6m_state == 6'b100010 || clk6m_state == 6'b101101 || clk6m_state == 6'b111000)
            clk_6m_reg <= 1'b0;
        else if (clk6m_state == 6'b001000 || clk6m_state == 6'b010010 || clk6m_state == 6'b011101 ||
                 clk6m_state == 6'b101000 || clk6m_state == 6'b110010 || clk6m_state == 6'b111101)
            clk_6m_reg <= 1'b1;

    assign mhz16_clken = clk_prescaler[1];
    assign CLK_6M      = clk_6m_reg;

    always @(posedge CLK_48M)
        if (mhz16_clken)
            clk_counter <= clk_counter + 1'b1;

`else // CLK_16MHZ
    // 16MHz mode: mhz16_clken always active
    // CLK_16M drives clk_counter directly
    // CLK_48M used only for CLK_6M generation
    assign mhz16_clken = 1'b1;

    always @(posedge CLK_16M)
        clk_counter <= clk_counter + 1'b1;

    // CLK_6M generation: free-running counter on CLK_48M, phase locked
    // to CLK_1M by resetting cnt_6m to 5 on CLK_1M rising edge.
    // CLK_1M rising edge detected synchronously via CLK_48M.
    // CLK_6M rises at tick 23 of each 1MHz cycle → tD = 20.8ns ✓
    // SAA5050 requires tD = 6-60ns. ✓
    reg [2:0] cnt_6m     = 3'b101;
    reg       clk_1m_prev = 1'b0;
    reg       clk_6m_reg  = 1'b0;

    always @(posedge CLK_48M) begin
        clk_1m_prev <= CLK_1M;
        // Detect CLK_1M rising edge and reset cnt_6m to phase-lock CLK_6M
        if (CLK_1M & ~clk_1m_prev)
            cnt_6m <= 3'd5;
        else
            cnt_6m <= (cnt_6m == 3'd7) ? 3'd0 : cnt_6m + 1'b1;
        // CLK_6M high when cnt_6m >= 4
        clk_6m_reg <= cnt_6m[2];
    end

    assign CLK_6M = clk_6m_reg;

`endif

    assign CLK_8M   = clk_counter[0];
    assign CLK_4M   = clk_counter[1];
    assign CLK_2M   = clk_counter[2];
    assign CLK_1M   = clk_counter[3];
    assign CLK_CRTC = r0_crtc_2mhz ? clk_counter[2] : clk_counter[3];

    // =========================================================================
    // CLOCK ENABLES
    // =========================================================================
    wire r0_clken   = (~nCS) & (clk_counter[2:0] == 3'b010);

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
`ifdef CLK_48MHZ
    always @(posedge CLK_48M) begin
`else
    always @(posedge CLK_16M) begin
`endif
        if (mhz16_clken) begin
            if (r0_clken & ~A) begin
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
    // sram_write is combinational (r0_clken & A). SRAM_nWE and the SRAM_ADDR
    // mux select both derive from it, so address and nWE change at nearly
    // the same time; address setup to nWE is NOT guaranteed (SRAM tSA=0ns).
    // r0_preload (cycle 001) loads sram_addr_reg from D[7:4] at the 001->010
    // clock edge, which can race with sram_write asserting at that same edge.
    // This is not a one-cycle setup margin.
    // =========================================================================
    wire r0_preload = (~nCS) & (clk_counter[2:0] == 3'b001);
    wire sram_write = r0_clken & A;

    reg [3:0] sram_addr_reg = 4'b0000;
`ifdef CLK_48MHZ
    always @(posedge CLK_48M)
`else
    always @(posedge CLK_16M)
`endif
        if (mhz16_clken & r0_preload)
            sram_addr_reg <= D[7:4];

    wire [3:0] log_col = {pixel_reg[7], pixel_reg[5], pixel_reg[3], pixel_reg[1]};

    assign SRAM_ADDR = sram_write ? sram_addr_reg : log_col;
    assign SRAM_nWE  = ~sram_write;
    assign SRAM_DATA = sram_write ? D[3:0] : 4'bZZZZ;

    wire [3:0] phy_col = SRAM_DATA;

    // =========================================================================
    // PIXEL SHIFT REGISTER
    // =========================================================================
`ifdef CLK_48MHZ
    always @(posedge CLK_48M) begin
`else
    always @(posedge CLK_16M) begin
`endif
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

`ifdef CLK_48MHZ
    always @(posedge CLK_48M) begin
`else
    always @(posedge CLK_16M) begin
`endif
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

`ifdef CLK_48MHZ
    always @(posedge CLK_48M) begin
`else
    always @(posedge CLK_16M) begin
`endif
        if (mhz16_clken) begin
            if (~sram_write) begin
                RR <= (red_val   & crtc_disen) ^ cursor_invert[0];
                GG <= (green_val & crtc_disen) ^ cursor_invert[0];
                BB <= (blue_val  & crtc_disen) ^ cursor_invert[0];
            end
        end
    end

    // =========================================================================
    // OUTPUT MUX
    // =========================================================================
    assign R = r0_teletext ? (R_IN ^ cursor_invert[3]) : RR;
    assign G = r0_teletext ? (G_IN ^ cursor_invert[3]) : GG;
    assign B = r0_teletext ? (B_IN ^ cursor_invert[3]) : BB;

endmodule
