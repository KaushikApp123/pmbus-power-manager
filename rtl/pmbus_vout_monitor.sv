// Output voltage supervisor.
//
// Compares each new VOUT sample against the four PMBus limits, debounces each
// comparison over DEBOUNCE consecutive samples, sets sticky STATUS_VOUT bits,
// and decides whether the output may stay enabled.
//
// Under-voltage is only checked while the output is on and after
// BLANK_SAMPLES samples of soft-start blanking.
//
// Fault response, bits 7:6 of *_FAULT_RESPONSE:
//   00      ignore (status only)
//   01, 10  shut down and latch off; cleared by OPERATION off
//   11      hiccup: turn off, wait HICCUP_OFF samples, retry (soft-start
//           blanking applies again). Repeats while the fault persists.

module pmbus_vout_monitor #(
  parameter int DEBOUNCE      = 3,
  parameter int BLANK_SAMPLES = 32,
  parameter int HICCUP_OFF    = 32      // samples to stay off before a hiccup retry
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        sample_i,        // new ADC sample strobe
  input  logic [15:0] vout_i,          // LINEAR16 mantissa

  input  logic [15:0] ov_fault_lim_i,
  input  logic [15:0] ov_warn_lim_i,
  input  logic [15:0] uv_warn_lim_i,
  input  logic [15:0] uv_fault_lim_i,
  /* verilator lint_off UNUSEDSIGNAL */   // retry/delay bits 5:0 not implemented
  input  logic [7:0]  ov_fault_resp_i,
  input  logic [7:0]  uv_fault_resp_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        op_on_i,         // OPERATION[7]

  input  logic        clear_faults_i,
  input  logic        w1c_i,
  input  logic [7:0]  w1c_mask_i,

  output logic        en_o,            // output enable to the power stage
  output logic        pg_o,            // power good
  output logic        latched_o,       // latched off by a fault
  output logic [7:0]  status_vout_o,   // [7] OV fault [6] OV warn [5] UV warn [4] UV fault
  output logic [15:0] vout_q_o         // last sample, for READ_VOUT
);

  localparam int DW = $clog2(DEBOUNCE + 1);
  localparam int BW = $clog2(BLANK_SAMPLES + 1);

  // ---------------------------------------------------------------------------
  // Soft-start blanking
  // ---------------------------------------------------------------------------
  logic [BW-1:0] blank_cnt;
  logic          checking;
  assign checking = en_o && (blank_cnt == BW'(BLANK_SAMPLES));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                                         blank_cnt <= '0;
    else if (!en_o)                                     blank_cnt <= '0;
    else if (sample_i && blank_cnt != BW'(BLANK_SAMPLES)) blank_cnt <= blank_cnt + 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Input capture and raw comparisons (two pipeline stages so the 16-bit
  // compares never sit behind the sample source's logic)
  // ---------------------------------------------------------------------------
  logic        sample_d1, sample_d2;
  logic [15:0] vout_s;
  logic [3:0]  raw;      // {ov_f, ov_w, uv_w, uv_f}

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_d1 <= 1'b0;
      sample_d2 <= 1'b0;
      vout_s    <= '0;
      raw       <= '0;
    end else begin
      sample_d1 <= sample_i;
      sample_d2 <= sample_d1;
      if (sample_i) vout_s <= vout_i;
      raw[3] <= vout_s > ov_fault_lim_i;
      raw[2] <= vout_s > ov_warn_lim_i;
      raw[1] <= checking && (vout_s < uv_warn_lim_i);
      raw[0] <= checking && (vout_s < uv_fault_lim_i);
    end
  end

  assign vout_q_o = vout_s;

  // ---------------------------------------------------------------------------
  // Debounce: DEBOUNCE consecutive samples
  // ---------------------------------------------------------------------------
  logic [3:0] act;       // debounced

  genvar g;
  generate
    for (g = 0; g < 4; g++) begin : g_db
      logic [DW-1:0] cnt;
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                       cnt <= '0;
        else if (g < 2 && !checking)      cnt <= '0;   // UV counters reset when not checking
        else if (sample_d2) begin
          if (!raw[g])                    cnt <= '0;
          else if (cnt != DW'(DEBOUNCE))  cnt <= cnt + 1'b1;
        end
      end
      assign act[g] = (cnt == DW'(DEBOUNCE));
    end
  endgenerate

  wire ov_fault = act[3];
  wire ov_warn  = act[2];
  wire uv_warn  = act[1];
  wire uv_fault = act[0];

  // ---------------------------------------------------------------------------
  // Fault response
  // ---------------------------------------------------------------------------
  wire [1:0] ov_resp = ov_fault_resp_i[7:6];
  wire [1:0] uv_resp = uv_fault_resp_i[7:6];

  wire ov_latch  = ov_fault && (ov_resp == 2'b01 || ov_resp == 2'b10);
  wire uv_latch  = uv_fault && (uv_resp == 2'b01 || uv_resp == 2'b10);
  wire ov_hiccup = ov_fault && (ov_resp == 2'b11);
  wire uv_hiccup = uv_fault && (uv_resp == 2'b11);

  localparam int HW = $clog2(HICCUP_OFF + 1);
  logic [HW-1:0] hic_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      latched_o <= 1'b0;
      en_o      <= 1'b0;
      hic_cnt   <= '0;
    end else begin
      if (!op_on_i)                   latched_o <= 1'b0;   // OPERATION off clears the latch
      else if (ov_latch || uv_latch)  latched_o <= 1'b1;

      if (ov_hiccup || uv_hiccup)          hic_cnt <= HW'(HICCUP_OFF);
      else if (sample_i && hic_cnt != '0)  hic_cnt <= hic_cnt - 1'b1;

      en_o <= op_on_i && !latched_o && !ov_latch && !uv_latch &&
              !ov_hiccup && !uv_hiccup && (hic_cnt == '0);
    end
  end

  // ---------------------------------------------------------------------------
  // Status, telemetry, power good
  // ---------------------------------------------------------------------------
  logic [7:0] st_set, st_clr;
  assign st_set = {ov_fault, ov_warn, uv_warn, uv_fault, 4'b0000};
  assign st_clr = clear_faults_i ? 8'hFF : (w1c_i ? w1c_mask_i : 8'h00);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      status_vout_o <= '0;
    end else begin
      status_vout_o <= (status_vout_o & ~st_clr) | st_set;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) pg_o <= 1'b0;
    else        pg_o <= checking && (vout_q_o >= uv_warn_lim_i) && (vout_q_o <= ov_fault_lim_i);
  end

endmodule
