// PMBus Power Manager IP, top level.
//
//   SCL/SDA --> pmbus_i2c_target --> pmbus_core --> pmbus_regfile (generated)
//                                                         |
//   VOUT samples ------------------> pmbus_vout_monitor <-+--> en_o, pg_o
//
// Pins are open drain: drive the pad low when *_oe_o is 1, otherwise release.

module pmbus_power_manager #(
  parameter int FILTER_LEN      = 3,
  parameter int SDA_HOLD_CYCLES = 16,        // 333 ns at 48 MHz
  parameter int TIMEOUT_CYCLES  = 1_200_000, // 25 ms at 48 MHz
  parameter int DEBOUNCE        = 3,         // samples
  parameter int BLANK_SAMPLES   = 32,        // samples of UV blanking after turn-on
  parameter int HICCUP_OFF      = 32         // samples off before a hiccup retry
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic [6:0]  addr_i,          // 7-bit target address (pin strap or constant)

  // SMBus / PMBus
  input  logic        scl_i,
  input  logic        sda_i,
  output logic        sda_oe_o,
  output logic        smbalert_oe_o,   // drive SMBALERT# low

  // Power stage
  input  logic        vout_sample_i,
  input  logic [15:0] vout_i,
  output logic        en_o,
  output logic        pg_o,
  output logic [15:0] vout_command_o,
  output logic [15:0] mfr_sim_vout_o
);

  // ---------------------------------------------------------------------------
  // Bus
  // ---------------------------------------------------------------------------
  logic       start, stop, addr_hit, rw, rx_valid, tx_req, timeout;
  logic [7:0] rx_data, tx_data;

  pmbus_i2c_target #(
    .FILTER_LEN      (FILTER_LEN),
    .SDA_HOLD_CYCLES (SDA_HOLD_CYCLES),
    .TIMEOUT_CYCLES  (TIMEOUT_CYCLES)
  ) u_i2c (
    .clk, .rst_n,
    .own_addr_i (addr_i),
    .scl_i, .sda_i,
    .sda_oe_o,
    .start_o    (start),
    .stop_o     (stop),
    .addr_hit_o (addr_hit),
    .rw_o       (rw),
    .rx_valid_o (rx_valid),
    .rx_data_o  (rx_data),
    .tx_req_o   (tx_req),
    .tx_data_i  (tx_data),
    .timeout_o  (timeout)
  );

  // ---------------------------------------------------------------------------
  // Transaction layer
  // ---------------------------------------------------------------------------
  logic [7:0]  cmd;
  logic        cmd_valid, cmd_readable, cmd_writable, cmd_wp_ok, cmd_value_ok;
  logic [1:0]  cmd_size;
  logic [15:0] rdata, wdata;
  logic        wr_en;
  logic        clear_faults_wr, status_vout_wr, status_cml_wr;
  logic [7:0]  status_cml;

  pmbus_core u_core (
    .clk, .rst_n,
    .own_addr_i     (addr_i),
    .start_i        (start),
    .stop_i         (stop),
    .addr_hit_i     (addr_hit),
    .rw_i           (rw),
    .rx_valid_i     (rx_valid),
    .rx_data_i      (rx_data),
    .tx_req_i       (tx_req),
    .tx_data_o      (tx_data),
    .timeout_i      (timeout),
    .cmd_o          (cmd),
    .cmd_valid_i    (cmd_valid),
    .cmd_readable_i (cmd_readable),
    .cmd_writable_i (cmd_writable),
    .cmd_size_i     (cmd_size),
    .cmd_wp_ok_i    (cmd_wp_ok),
    .cmd_value_ok_i (cmd_value_ok),
    .rdata_i        (rdata),
    .wr_en_o        (wr_en),
    .wdata_o        (wdata),
    .clear_faults_i (clear_faults_wr),
    .cml_w1c_i      (status_cml_wr),
    .status_cml_o   (status_cml)
  );

  // ---------------------------------------------------------------------------
  // Register file (generated from gen/regmap.yaml)
  // ---------------------------------------------------------------------------
  logic [7:0]  operation, write_protect, ov_fault_resp, uv_fault_resp;
  logic [15:0] ov_fault_lim, ov_warn_lim, uv_warn_lim, uv_fault_lim;
  logic [7:0]  status_byte, status_vout;
  logic [15:0] status_word, read_vout;

  pmbus_regfile u_regs (
    .clk, .rst_n,
    .cmd_i                    (cmd),
    .cmd_valid_o              (cmd_valid),
    .cmd_readable_o           (cmd_readable),
    .cmd_writable_o           (cmd_writable),
    .cmd_size_o               (cmd_size),
    .cmd_wp_ok_o              (cmd_wp_ok),
    .cmd_value_ok_o           (cmd_value_ok),
    .rdata_o                  (rdata),
    .wr_en_i                  (wr_en),
    .wdata_i                  (wdata),
    .operation_q              (operation),
    .write_protect_q          (write_protect),
    .vout_command_q           (vout_command_o),
    .vout_ov_fault_limit_q    (ov_fault_lim),
    .vout_ov_fault_response_q (ov_fault_resp),
    .vout_ov_warn_limit_q     (ov_warn_lim),
    .vout_uv_warn_limit_q     (uv_warn_lim),
    .vout_uv_fault_limit_q    (uv_fault_lim),
    .vout_uv_fault_response_q (uv_fault_resp),
    .mfr_sim_vout_q           (mfr_sim_vout_o),
    .status_byte_i            (status_byte),
    .status_word_i            (status_word),
    .status_vout_i            (status_vout),
    .status_cml_i             (status_cml),
    .read_vout_i              (read_vout),
    .clear_faults_wr          (clear_faults_wr),
    .status_vout_wr           (status_vout_wr),
    .status_cml_wr            (status_cml_wr)
  );

  // ---------------------------------------------------------------------------
  // Output supervisor
  // ---------------------------------------------------------------------------
  logic latched;

  pmbus_vout_monitor #(
    .DEBOUNCE      (DEBOUNCE),
    .BLANK_SAMPLES (BLANK_SAMPLES),
    .HICCUP_OFF    (HICCUP_OFF)
  ) u_mon (
    .clk, .rst_n,
    .sample_i        (vout_sample_i),
    .vout_i          (vout_i),
    .ov_fault_lim_i  (ov_fault_lim),
    .ov_warn_lim_i   (ov_warn_lim),
    .uv_warn_lim_i   (uv_warn_lim),
    .uv_fault_lim_i  (uv_fault_lim),
    .ov_fault_resp_i (ov_fault_resp),
    .uv_fault_resp_i (uv_fault_resp),
    .op_on_i         (operation[7]),
    .clear_faults_i  (clear_faults_wr),
    .w1c_i           (status_vout_wr),
    .w1c_mask_i      (wdata[7:0]),
    .en_o,
    .pg_o,
    .latched_o       (latched),
    .status_vout_o   (status_vout),
    .vout_q_o        (read_vout)
  );

  // ---------------------------------------------------------------------------
  // Summary status and SMBALERT#
  // ---------------------------------------------------------------------------
  //                 BUSY  OFF    VOUT_OV         IOUT  VIN   TEMP  CML          NONE_OF_ABOVE
  assign status_byte = {1'b0, ~en_o, status_vout[7], 1'b0, 1'b0, 1'b0, |status_cml, |status_vout[6:4]};
  //                 VOUT          IOUT INPUT MFR  PG#    FANS OTHER UNKNOWN
  assign status_word = {|status_vout, 3'b000,         ~pg_o, 3'b000,          status_byte};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) smbalert_oe_o <= 1'b0;
    else        smbalert_oe_o <= (|status_vout) || (|status_cml);
  end

  // write_protect and the low bits of operation are used inside the regfile
  // or reserved; latched is visible to simulation for debug.
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, write_protect, operation[6:0], latched};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
