// UPduino v3.x (Lattice iCE40UP5K-SG48) demo top.
//
// The board has no power stage, so a small plant model stands in for one:
//   * VOUT ramps toward VOUT_COMMAND while enabled and decays to 0 when off
//   * MFR_SIM_VOUT (0xD0), when non-zero, forces VOUT to that value so the
//     host can inject OV/UV faults over the bus
//   * a 1 kHz tick is the "ADC" sample strobe
//
// Pins (check against your board's silkscreen):
//   scl        pin 2   to STM32 I2C SCL, 4.7k pull-up to 3.3V
//   sda        pin 3   to STM32 I2C SDA, 4.7k pull-up to 3.3V
//   smbalert_n pin 4   open drain, 10k pull-up (optional)
//   en_out     pin 6   output enable (logic analyzer)
//   pg_out     pin 9   power good    (logic analyzer)
//   RGB LED: green = power good, blue = enabled, red = SMBALERT#

module upduino_top (
  inout  wire scl,
  inout  wire sda,
  inout  wire smbalert_n,
  output wire en_out,
  output wire pg_out,
  output wire led_r,
  output wire led_g,
  output wire led_b
);

  localparam int        CLK_HZ   = 24_000_000;   // HFOSC / 2, 2x timing margin
  localparam int        TICK_DIV = CLK_HZ / 1000;     // 1 kHz samples
  localparam bit [15:0] SLEW     = 16'd128;           // 0.25 V per sample

  // ---------------------------------------------------------------------------
  // Clock and power-on reset
  // ---------------------------------------------------------------------------
  wire clk;
  SB_HFOSC #(.CLKHF_DIV("0b01")) u_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk));

  logic [7:0] por = 8'd0;
  wire        rst_n = por[7];
  always_ff @(posedge clk) if (!por[7]) por <= por + 1'b1;

  // ---------------------------------------------------------------------------
  // Open-drain pads
  // ---------------------------------------------------------------------------
  wire scl_in, sda_in, sda_oe, alert_oe, alert_unused;

  SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b1)) u_scl_io (
    .PACKAGE_PIN(scl), .OUTPUT_ENABLE(1'b0), .D_OUT_0(1'b0), .D_IN_0(scl_in));
  SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b1)) u_sda_io (
    .PACKAGE_PIN(sda), .OUTPUT_ENABLE(sda_oe), .D_OUT_0(1'b0), .D_IN_0(sda_in));
  SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b1)) u_alert_io (
    .PACKAGE_PIN(smbalert_n), .OUTPUT_ENABLE(alert_oe), .D_OUT_0(1'b0), .D_IN_0(alert_unused));

  // ---------------------------------------------------------------------------
  // Plant model
  // ---------------------------------------------------------------------------
  logic [15:0] tick_cnt;
  logic        tick;
  logic [15:0] vout;
  wire  [15:0] vout_cmd, mfr_sim;
  wire         en, pg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tick_cnt <= '0;
      tick     <= 1'b0;
    end else begin
      tick <= (tick_cnt == 16'(TICK_DIV - 1));
      tick_cnt <= (tick_cnt == 16'(TICK_DIV - 1)) ? '0 : tick_cnt + 1'b1;
    end
  end

  // Registered plant math. VOUT only moves on the 1 kHz tick, so the extra
  // pipeline cycles are invisible and keep the adders off the critical path.
  logic [15:0] target_q, up_q, dn_q, tgt_hi_q;
  logic        go_up, go_dn;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      target_q <= '0; up_q <= '0; dn_q <= '0; tgt_hi_q <= '0;
      go_up <= 1'b0; go_dn <= 1'b0;
    end else begin
      target_q <= en ? vout_cmd : 16'h0000;
      up_q     <= vout + SLEW;
      dn_q     <= vout - SLEW;
      tgt_hi_q <= target_q + SLEW;
      go_up    <= up_q < target_q;
      go_dn    <= vout > tgt_hi_q;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                  vout <= '0;
    else if (mfr_sim != 16'h0)   vout <= mfr_sim;              // forced, no slew
    else if (tick) begin
      if      (go_up)            vout <= up_q;
      else if (go_dn)            vout <= dn_q;
      else                       vout <= target_q;
    end
  end

  // ---------------------------------------------------------------------------
  // IP
  // ---------------------------------------------------------------------------
  pmbus_power_manager #(
    .FILTER_LEN      (3),
    .SDA_HOLD_CYCLES (8),            // 333 ns
    .TIMEOUT_CYCLES  (600_000),     // 25 ms
    .DEBOUNCE        (3),           // 3 ms
    .BLANK_SAMPLES   (32),          // 32 ms soft-start blanking
    .HICCUP_OFF      (100)          // 100 ms off between hiccup retries
  ) u_pm (
    .clk, .rst_n,
    .addr_i         (7'h40),
    .scl_i          (scl_in),
    .sda_i          (sda_in),
    .sda_oe_o       (sda_oe),
    .smbalert_oe_o  (alert_oe),
    .vout_sample_i  (tick),
    .vout_i         (vout),
    .en_o           (en),
    .pg_o           (pg),
    .vout_command_o (vout_cmd),
    .mfr_sim_vout_o (mfr_sim)
  );

  assign en_out = en;
  assign pg_out = pg;

  // ---------------------------------------------------------------------------
  // RGB LED (active low current sinks)
  // ---------------------------------------------------------------------------
  SB_RGBA_DRV #(
    .CURRENT_MODE("0b1"),
    .RGB0_CURRENT("0b000001"),
    .RGB1_CURRENT("0b000001"),
    .RGB2_CURRENT("0b000001")
  ) u_rgb (
    .CURREN(1'b1), .RGBLEDEN(1'b1),
    .RGB0PWM(pg), .RGB1PWM(en), .RGB2PWM(alert_oe),
    .RGB0(led_g), .RGB1(led_b), .RGB2(led_r)
  );

endmodule
