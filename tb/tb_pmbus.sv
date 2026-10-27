// Self-checking testbench for pmbus_power_manager.
//
//   * Generated register map data (tb/generated/regmap_tb.svh) drives a generic
//     test of every command: reset value, read, read+PEC, write, write+PEC,
//     bad PEC, bad length, write to read-only, read of send-byte.
//   * Every one of the 256 command codes is exercised; unsupported ones must
//     flag STATUS_CML.INVALID_CMD.
//   * Directed tests inject bus errors (NACK, partial byte, aborted write,
//     glitches, SCL timeout) and output faults (OV/UV warn and fault, debounce,
//     soft-start blanking, latch-off, hiccup, write protect).
//   * Functional coverage is collected per command and per scenario. Any hole
//     fails the run.
//
// Run: make sim   (prints TEST PASSED / TEST FAILED)

`timescale 1ns/1ps

module tb_pmbus;
  import pmbus_regmap_pkg::*;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  localparam int       CLK_NS         = 20;        // 50 MHz
  localparam int       T_HALF         = 1250;      // 400 kHz SCL
  localparam int       T_Q            = T_HALF / 2;
  localparam int       TIMEOUT_CYCLES = 5000;      // 100 us (scaled down from 25 ms)
  localparam int       SAMPLE_CYCLES  = 2500;      // 50 us between VOUT samples
  localparam int       DEBOUNCE       = 3;
  localparam int       BLANK          = 16;
  localparam int       HICCUP_OFF     = 8;
  localparam bit [6:0] TB_ADDR        = DEFAULT_ADDR;

  localparam [15:0] V_NOM    = 16'h0699;   // 3.30 V
  localparam [15:0] V_OVWARN = 16'h0700;   // 3.50 V: above OV warn, below OV fault
  localparam [15:0] V_OVF    = 16'h0800;   // 4.00 V: above OV fault
  localparam [15:0] V_UVWARN = 16'h0620;   // 3.06 V: below UV warn, above UV fault
  localparam [15:0] V_UVF    = 16'h0500;   // 2.50 V: below UV fault

  // STATUS_CML bits
  localparam [7:0] CML_CMD   = 8'h80;
  localparam [7:0] CML_DATA  = 8'h40;
  localparam [7:0] CML_PEC   = 8'h20;
  localparam [7:0] CML_OTHER = 8'h02;

  // Coverage kinds (used by the generated cov_applicable)
  localparam int K_RD        = 0;
  localparam int K_RD_PEC    = 1;
  localparam int K_WR        = 2;
  localparam int K_WR_PEC    = 3;
  localparam int K_WR_BADPEC = 4;
  localparam int K_WR_BADLEN = 5;
  localparam int K_WR_REJECT = 6;
  localparam int K_RD_REJECT = 7;
  localparam int K_UNSUP_RD  = 8;
  localparam int K_UNSUP_WR  = 9;
  localparam int NUM_K       = 10;

  `include "generated/regmap_tb.svh"

  // ---------------------------------------------------------------------------
  // Clock, reset, bus
  // ---------------------------------------------------------------------------
  logic clk = 0, rst_n = 0;
  always #(CLK_NS / 2) clk = ~clk;

  tri1  scl, sda;                       // pull-ups
  logic m_scl_oe = 0, m_sda_oe = 0;     // host drives low
  logic glitch_scl = 0, glitch_sda = 0; // injected spikes
  wire  dut_sda_oe, dut_alert_oe;

  assign scl = (m_scl_oe || glitch_scl) ? 1'b0 : 1'bz;
  assign sda = (m_sda_oe || glitch_sda) ? 1'b0 : 1'bz;
  assign sda = dut_sda_oe ? 1'b0 : 1'bz;
  wire alert_n = ~dut_alert_oe;

  // VOUT "ADC": TB sets vout, the DUT samples it every SAMPLE_CYCLES
  logic [15:0] vout = V_NOM;
  logic        sample = 0;
  int          sample_cnt = 0;
  int          n_samples = 0;
  always @(posedge clk) begin
    sample <= 1'b0;
    if (sample_cnt == SAMPLE_CYCLES - 1) begin
      sample_cnt <= 0;
      sample     <= 1'b1;
      n_samples  <= n_samples + 1;
    end else begin
      sample_cnt <= sample_cnt + 1;
    end
  end

  wire        en, pg;
  wire [15:0] vout_cmd, mfr_sim;

  pmbus_power_manager #(
    .FILTER_LEN      (3),
    .SDA_HOLD_CYCLES (12),          // 240 ns + sync/filter delay > 300 ns
    .TIMEOUT_CYCLES  (TIMEOUT_CYCLES),
    .DEBOUNCE        (DEBOUNCE),
    .BLANK_SAMPLES   (BLANK),
    .HICCUP_OFF      (HICCUP_OFF)
  ) dut (
    .clk, .rst_n,
    .addr_i         (TB_ADDR),
    .scl_i          (scl),
    .sda_i          (sda),
    .sda_oe_o       (dut_sda_oe),
    .smbalert_oe_o  (dut_alert_oe),
    .vout_sample_i  (sample),
    .vout_i         (vout),
    .en_o           (en),
    .pg_o           (pg),
    .vout_command_o (vout_cmd),
    .mfr_sim_vout_o (mfr_sim)
  );

  `include "i2c_master_bfm.svh"

  // Glitch injectors: a 1-cycle spike in the middle of every SCL high period
  bit glitch_scl_en = 0, glitch_sda_en = 0;
  always @(posedge scl) if (glitch_scl_en) begin
    #(T_HALF / 2 - 100);
    glitch_scl = 1; #(CLK_NS); glitch_scl = 0;
  end
  always @(posedge scl) if (glitch_sda_en) begin
    #(T_HALF / 2 + 100);
    glitch_sda = 1; #(CLK_NS); glitch_sda = 0;
  end

  // ---------------------------------------------------------------------------
  // Checking and coverage
  // ---------------------------------------------------------------------------
  int errors = 0;
  int checks = 0;
  int cov [0:255][0:NUM_K-1];

  localparam int S_ADDR_NACK       = 0;
  localparam int S_STOP_MID_BYTE   = 1;
  localparam int S_RSTART_ABORT    = 2;
  localparam int S_READ_NO_CMD     = 3;
  localparam int S_SCL_GLITCH      = 4;
  localparam int S_SDA_GLITCH      = 5;
  localparam int S_BUS_TIMEOUT     = 6;
  localparam int S_HOST_NACK_EARLY = 7;
  localparam int S_OV_WARN         = 8;
  localparam int S_OV_FAULT_LATCH  = 9;
  localparam int S_UV_WARN         = 10;
  localparam int S_UV_FAULT_LATCH  = 11;
  localparam int S_UV_BLANKING     = 12;
  localparam int S_DEBOUNCE_SPIKE  = 13;
  localparam int S_RESP_IGNORE     = 14;
  localparam int S_RESP_HICCUP     = 15;
  localparam int S_STATUS_W1C      = 16;
  localparam int S_FAULT_PERSISTS  = 17;
  localparam int S_WP_80           = 18;
  localparam int S_WP_40           = 19;
  localparam int S_WP_20           = 20;
  localparam int S_ILLEGAL_VALUE   = 21;
  localparam int S_ALERT_CYCLE     = 22;
  localparam int S_LATCH_RECOVER   = 23;
  localparam int NUM_S             = 24;
  int scen [0:NUM_S-1];

  function automatic string scen_name(input int s);
    case (s)
      S_ADDR_NACK:       return "wrong address NACKed";
      S_STOP_MID_BYTE:   return "STOP in the middle of a byte";
      S_RSTART_ABORT:    return "repeated START after data aborts write";
      S_READ_NO_CMD:     return "read with no command";
      S_SCL_GLITCH:      return "SCL glitch rejected";
      S_SDA_GLITCH:      return "SDA glitch rejected";
      S_BUS_TIMEOUT:     return "SMBus SCL-low timeout";
      S_HOST_NACK_EARLY: return "host NACKs word read early";
      S_OV_WARN:         return "OV warning";
      S_OV_FAULT_LATCH:  return "OV fault latch-off";
      S_UV_WARN:         return "UV warning";
      S_UV_FAULT_LATCH:  return "UV fault latch-off";
      S_UV_BLANKING:     return "UV ignored during soft-start";
      S_DEBOUNCE_SPIKE:  return "short spike filtered by debounce";
      S_RESP_IGNORE:     return "fault response = ignore";
      S_RESP_HICCUP:     return "fault response = hiccup";
      S_STATUS_W1C:      return "STATUS_VOUT write-1-to-clear";
      S_FAULT_PERSISTS:  return "CLEAR_FAULTS with fault still present";
      S_WP_80:           return "WRITE_PROTECT 0x80";
      S_WP_40:           return "WRITE_PROTECT 0x40";
      S_WP_20:           return "WRITE_PROTECT 0x20";
      S_ILLEGAL_VALUE:   return "illegal value rejected";
      S_ALERT_CYCLE:     return "SMBALERT# assert and release";
      S_LATCH_RECOVER:   return "latch cleared by OPERATION off/on";
      default:           return "?";
    endcase
  endfunction

  function automatic string kind_name(input int k);
    case (k)
      K_RD:        return "RD";
      K_RD_PEC:    return "RD+PEC";
      K_WR:        return "WR";
      K_WR_PEC:    return "WR+PEC";
      K_WR_BADPEC: return "BADPEC";
      K_WR_BADLEN: return "BADLEN";
      K_WR_REJECT: return "WR_REJ";
      K_RD_REJECT: return "RD_REJ";
      K_UNSUP_RD:  return "UNS_RD";
      K_UNSUP_WR:  return "UNS_WR";
      default:     return "?";
    endcase
  endfunction

  task automatic check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $display("[%0t] ERROR: %s", $time, msg);
      if ($test$plusargs("stop_on_error")) begin
        $display("TEST FAILED");
        $finish;
      end
    end
  endtask

  task automatic cov_hit(input [7:0] c, input int k);
    cov[c][k]++;
  endtask

  task automatic scen_hit(input int s);
    scen[s]++;
  endtask

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  task automatic wait_samples(input int n);
    repeat (n) @(posedge sample);
    repeat (5) @(posedge clk);
  endtask

  task automatic wr(input [7:0] c, input [15:0] d);
    bit a;
    pm_write(c, d, reg_size(c), PEC_NONE, a);
    check(a, $sformatf("write %s not ACKed", reg_name(c)));
  endtask

  task automatic wr_pec(input [7:0] c, input [15:0] d);
    bit a;
    pm_write(c, d, reg_size(c), PEC_GOOD, a);
    check(a, $sformatf("write+PEC %s not ACKed", reg_name(c)));
  endtask

  task automatic rd(input [7:0] c, output [15:0] d);
    bit a, p;
    pm_read(c, reg_size(c), 1'b0, d, p, a);
    check(a, $sformatf("read %s not ACKed", reg_name(c)));
  endtask

  task automatic rd_expect(input [7:0] c, input [15:0] exp, input string what);
    logic [15:0] d;
    rd(c, d);
    check(d == exp, $sformatf("%s: %s = 0x%04h, expected 0x%04h", what, reg_name(c), d, exp));
  endtask

  task automatic send(input [7:0] c);
    bit a;
    pm_write(c, 16'h0, 0, PEC_NONE, a);
    check(a, $sformatf("send %s not ACKed", reg_name(c)));
  endtask

  // Read STATUS_CML, compare, then clear whatever is set
  task automatic expect_cml(input [7:0] exp, input string what);
    logic [15:0] d;
    rd(CMD_STATUS_CML, d);
    check(d[7:0] == exp, $sformatf("%s: STATUS_CML = 0x%02h, expected 0x%02h", what, d[7:0], exp));
    if (exp != 0) check(alert_n == 1'b0, $sformatf("%s: SMBALERT# not asserted", what));
    if (d[7:0] != 0) wr(CMD_STATUS_CML, 16'h00FF);
  endtask

  task automatic power_on_nominal();
    vout = V_NOM;
    wr(CMD_OPERATION, 16'h0000);
    send(CMD_CLEAR_FAULTS);
    wr(CMD_OPERATION, 16'h0080);
    wait_samples(BLANK + DEBOUNCE + 2);
    check(en && pg, "output did not come up with nominal VOUT");
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------
  task automatic test_crc_vector();
    logic [7:0] c;
    string s;
    s = "123456789";
    c = 8'h00;
    for (int i = 0; i < 9; i++) c = tb_crc8(c, s[i]);
    check(c == 8'hF4, $sformatf("CRC-8 check value 0x%02h, expected 0xF4", c));
  endtask

  task automatic test_reset_state();
    $display("[%0t] -- reset state", $time);
    check(!en && !pg, "output enabled out of reset");
    check(alert_n == 1'b1, "SMBALERT# asserted out of reset");
    rd_expect(CMD_STATUS_BYTE, 16'h0040, "reset");    // OFF
    rd_expect(CMD_STATUS_WORD, 16'h0840, "reset");    // POWER_GOOD#, OFF
    rd_expect(CMD_STATUS_VOUT, 16'h0000, "reset");
    rd_expect(CMD_STATUS_CML,  16'h0000, "reset");
    rd_expect(CMD_READ_VOUT,   V_NOM,    "reset");
  endtask

  // Generic per-command tests built from the generated register data
  task automatic test_rw_reg(input [7:0] c);
    logic [15:0] d, rst, v, vbad;
    bit p, a;
    int sz;
    sz  = reg_size(c);
    rst = reg_reset(c);

    pm_read(c, sz, 1'b0, d, p, a);  cov_hit(c, K_RD);
    check(d == rst, $sformatf("%s reset 0x%04h, expected 0x%04h", reg_name(c), d, rst));
    pm_read(c, sz, 1'b1, d, p, a);  cov_hit(c, K_RD_PEC);
    check(d == rst && p, $sformatf("%s read+PEC: 0x%04h pec_ok=%0d", reg_name(c), d, p));

    for (int j = 0; j < reg_num_test_values(c); j++) begin
      v = reg_test_value(c, j);
      pm_write(c, v, sz, PEC_NONE, a);  cov_hit(c, K_WR);
      rd_expect(c, v, "write/read back");
    end
    expect_cml(8'h00, $sformatf("%s writes", reg_name(c)));

    v = reg_test_value(c, 0);
    pm_write(c, v, sz, PEC_GOOD, a);  cov_hit(c, K_WR_PEC);
    pm_read(c, sz, 1'b1, d, p, a);
    check(d == v && p, $sformatf("%s write+PEC/read+PEC: 0x%04h pec_ok=%0d", reg_name(c), d, p));
    expect_cml(8'h00, $sformatf("%s write+PEC", reg_name(c)));

    wr(c, rst);
    vbad = (reg_test_value(c, 0) != rst) ? reg_test_value(c, 0) : reg_test_value(c, 1);

    pm_write(c, vbad, sz, PEC_BAD, a);  cov_hit(c, K_WR_BADPEC);
    rd_expect(c, rst, "bad PEC must not write");
    expect_cml(CML_PEC, $sformatf("%s bad PEC", reg_name(c)));

    pm_write(c, vbad, sz + 2, PEC_NONE, a);  cov_hit(c, K_WR_BADLEN);
    rd_expect(c, rst, "bad length must not write");
    expect_cml(CML_DATA, $sformatf("%s too many bytes", reg_name(c)));

    if (sz == 2) begin
      pm_write(c, vbad, 1, PEC_NONE, a);
      rd_expect(c, rst, "short write must not write");
      expect_cml(CML_DATA, $sformatf("%s too few bytes", reg_name(c)));
    end
  endtask

  task automatic test_ro_reg(input [7:0] c, input bit is_const);
    logic [15:0] d, d2;
    bit p, a;
    int sz;
    sz = reg_size(c);
    pm_read(c, sz, 1'b0, d, p, a);  cov_hit(c, K_RD);
    if (is_const) check(d == reg_reset(c), $sformatf("%s = 0x%04h, expected 0x%04h", reg_name(c), d, reg_reset(c)));
    pm_read(c, sz, 1'b1, d2, p, a);  cov_hit(c, K_RD_PEC);
    check(p, $sformatf("%s read PEC mismatch", reg_name(c)));
    if (is_const) check(d2 == reg_reset(c), $sformatf("%s read+PEC value", reg_name(c)));

    pm_write(c, ~reg_reset(c), sz, PEC_NONE, a);  cov_hit(c, K_WR_REJECT);
    expect_cml(CML_CMD, $sformatf("write to read-only %s", reg_name(c)));
    if (is_const) rd_expect(c, reg_reset(c), "read-only must not change");
  endtask

  task automatic test_w1c_reg(input [7:0] c);
    logic [15:0] d;
    bit p, a;
    pm_read(c, 1, 1'b0, d, p, a);  cov_hit(c, K_RD);
    pm_read(c, 1, 1'b1, d, p, a);  cov_hit(c, K_RD_PEC);
    check(p, $sformatf("%s read PEC mismatch", reg_name(c)));
    pm_write(c, 16'h0000, 1, PEC_NONE, a);  cov_hit(c, K_WR);
    expect_cml(8'h00, $sformatf("%s write 0", reg_name(c)));
    pm_write(c, 16'h0000, 1, PEC_GOOD, a);  cov_hit(c, K_WR_PEC);
    expect_cml(8'h00, $sformatf("%s write+PEC 0", reg_name(c)));
    pm_write(c, 16'h0000, 1, PEC_BAD, a);   cov_hit(c, K_WR_BADPEC);
    expect_cml(CML_PEC, $sformatf("%s bad PEC", reg_name(c)));
    pm_write(c, 16'h0000, 3, PEC_NONE, a);  cov_hit(c, K_WR_BADLEN);
    expect_cml(CML_DATA, $sformatf("%s bad length", reg_name(c)));
  endtask

  task automatic test_send_reg(input [7:0] c);
    logic [15:0] d;
    bit p, a;
    pm_write(c, 16'h0, 0, PEC_NONE, a);  cov_hit(c, K_WR);
    expect_cml(8'h00, $sformatf("%s send", reg_name(c)));
    pm_write(c, 16'h0, 0, PEC_GOOD, a);  cov_hit(c, K_WR_PEC);
    expect_cml(8'h00, $sformatf("%s send+PEC", reg_name(c)));
    pm_write(c, 16'h0, 0, PEC_BAD, a);   cov_hit(c, K_WR_BADPEC);
    expect_cml(CML_PEC, $sformatf("%s bad PEC", reg_name(c)));
    pm_write(c, 16'h0, 2, PEC_NONE, a);  cov_hit(c, K_WR_BADLEN);
    expect_cml(CML_DATA, $sformatf("%s with data", reg_name(c)));
    pm_read(c, 1, 1'b0, d, p, a);        cov_hit(c, K_RD_REJECT);
    check(d[7:0] == 8'hFF, $sformatf("read of send-byte %s returned 0x%02h", reg_name(c), d[7:0]));
    expect_cml(CML_CMD, $sformatf("read of send-byte %s", reg_name(c)));
  endtask

  task automatic test_all_registers();
    logic [7:0] c;
    $display("[%0t] -- generated per-command tests (%0d commands)", $time, NUM_REGS);
    for (int i = 0; i < NUM_REGS; i++) begin
      c = reg_code_at(i);
      case (reg_access(c))
        ACC_RW:       test_rw_reg(c);
        ACC_RO_CONST: test_ro_reg(c, 1'b1);
        ACC_RO_HW:    test_ro_reg(c, 1'b0);
        ACC_W1C_HW:   test_w1c_reg(c);
        ACC_SEND:     test_send_reg(c);
        default:      check(0, "unknown access type");
      endcase
    end
  endtask

  task automatic test_unsupported_commands();
    logic [15:0] d;
    bit p, a;
    int n = 0;
    $display("[%0t] -- unsupported command codes", $time);
    for (int c = 0; c < 256; c++) begin
      if (!reg_known(c[7:0])) begin
        pm_write(c[7:0], 16'h00AB, 1, PEC_NONE, a);  cov_hit(c[7:0], K_UNSUP_WR);
        check(a, "unsupported write should still be ACKed");
        pm_read(c[7:0], 1, 1'b0, d, p, a);            cov_hit(c[7:0], K_UNSUP_RD);
        check(d[7:0] == 8'hFF, $sformatf("unsupported 0x%02h read 0x%02h", c, d[7:0]));
        expect_cml(CML_CMD, $sformatf("unsupported 0x%02h", c));
        n++;
      end
    end
    $display("[%0t]    %0d unsupported codes checked", $time, n);
  endtask

  task automatic test_bus_errors();
    bit a;
    logic [7:0]  b;
    logic [15:0] d;
    $display("[%0t] -- bus error injection", $time);

    // Wrong address: no ACK, nothing changes
    i2c_start();
    i2c_write_byte({TB_ADDR ^ 7'h01, 1'b0}, a);
    i2c_stop();
    check(!a, "wrong address was ACKed");
    expect_cml(8'h00, "wrong address");
    scen_hit(S_ADDR_NACK);

    // STOP in the middle of the first data byte
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b0}, a);
    i2c_write_byte(CMD_VOUT_COMMAND, a);
    i2c_write_partial(8'h12, 4);
    i2c_stop();
    #(T_HALF);
    rd_expect(CMD_VOUT_COMMAND, RST_VOUT_COMMAND, "partial byte must not write");
    expect_cml(CML_DATA, "STOP mid byte");
    scen_hit(S_STOP_MID_BYTE);

    // Repeated START after data bytes: write is discarded, read returns 0xFF
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b0}, a);
    i2c_write_byte(CMD_VOUT_COMMAND, a);
    i2c_write_byte(8'h34, a);
    i2c_write_byte(8'h12, a);
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b1}, a);
    i2c_read_byte(b, 1'b0);
    i2c_stop();
    #(T_HALF);
    check(b == 8'hFF, $sformatf("read after aborted write returned 0x%02h", b));
    rd_expect(CMD_VOUT_COMMAND, RST_VOUT_COMMAND, "aborted write must not commit");
    expect_cml(8'h00, "repeated START abort");
    scen_hit(S_RSTART_ABORT);

    // Read with no command byte
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b1}, a);
    check(a, "address+R not ACKed");
    i2c_read_byte(b, 1'b0);
    i2c_stop();
    #(T_HALF);
    check(b == 8'hFF, "read with no command should return 0xFF");
    expect_cml(8'h00, "read with no command");
    scen_hit(S_READ_NO_CMD);

    // Glitches shorter than the filter on SCL and SDA
    glitch_scl_en = 1;
    wr_pec(CMD_VOUT_COMMAND, 16'h0700);
    rd_expect(CMD_VOUT_COMMAND, 16'h0700, "with SCL glitches");
    glitch_scl_en = 0;
    expect_cml(8'h00, "SCL glitches");
    scen_hit(S_SCL_GLITCH);
    glitch_sda_en = 1;
    wr_pec(CMD_VOUT_COMMAND, 16'h0701);
    rd_expect(CMD_VOUT_COMMAND, 16'h0701, "with SDA glitches");
    glitch_sda_en = 0;
    expect_cml(8'h00, "SDA glitches");
    scen_hit(S_SDA_GLITCH);
    wr(CMD_VOUT_COMMAND, RST_VOUT_COMMAND);

    // SMBus timeout: host holds SCL low mid-write
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b0}, a);
    i2c_write_byte(CMD_VOUT_COMMAND, a);
    i2c_write_byte(8'h00, a);
    repeat (TIMEOUT_CYCLES + 200) @(posedge clk);
    check(!dut_sda_oe, "SDA still driven after timeout");
    i2c_write_byte(8'h08, a);   // DUT has reset, this byte is ignored
    i2c_stop();
    #(T_HALF);
    rd_expect(CMD_VOUT_COMMAND, RST_VOUT_COMMAND, "timed-out write must not commit");
    expect_cml(CML_OTHER, "SCL timeout");
    scen_hit(S_BUS_TIMEOUT);

    // Host NACKs after the first byte of a word read
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b0}, a);
    i2c_write_byte(CMD_READ_VOUT, a);
    i2c_start();
    i2c_write_byte({TB_ADDR, 1'b1}, a);
    i2c_read_byte(b, 1'b0);
    i2c_stop();
    #(T_HALF);
    check(b == vout[7:0], "early-NACK low byte wrong");
    rd_expect(CMD_READ_VOUT, vout, "bus still works after early NACK");
    expect_cml(8'h00, "early NACK");
    scen_hit(S_HOST_NACK_EARLY);
  endtask

  task automatic test_write_protect();
    $display("[%0t] -- write protect", $time);
    wr(CMD_WRITE_PROTECT, 16'h0080);
    wr(CMD_VOUT_COMMAND, 16'h0700);
    wr(CMD_OPERATION, 16'h0000);
    rd_expect(CMD_VOUT_COMMAND, RST_VOUT_COMMAND, "WP 0x80 blocks VOUT_COMMAND");
    rd_expect(CMD_STATUS_CML, {8'h00, CML_DATA}, "WP 0x80 flags invalid data");
    send(CMD_CLEAR_FAULTS);                                   // also blocked
    rd_expect(CMD_STATUS_CML, {8'h00, CML_DATA}, "WP 0x80 blocks CLEAR_FAULTS");
    scen_hit(S_WP_80);

    wr(CMD_WRITE_PROTECT, 16'h0040);
    send(CMD_CLEAR_FAULTS);                                   // blocked at 0x40 too
    rd_expect(CMD_STATUS_CML, {8'h00, CML_DATA}, "WP 0x40 blocks CLEAR_FAULTS");
    wr(CMD_WRITE_PROTECT, 16'h0000);
    expect_cml(CML_DATA, "after WP");

    wr(CMD_WRITE_PROTECT, 16'h0040);
    wr(CMD_OPERATION, 16'h0000);
    wr(CMD_VOUT_COMMAND, 16'h0700);
    rd_expect(CMD_VOUT_COMMAND, RST_VOUT_COMMAND, "WP 0x40 blocks VOUT_COMMAND");
    wr(CMD_WRITE_PROTECT, 16'h0000);
    expect_cml(CML_DATA, "WP 0x40 (only VOUT_COMMAND rejected)");
    scen_hit(S_WP_40);

    wr(CMD_WRITE_PROTECT, 16'h0020);
    wr(CMD_VOUT_COMMAND, 16'h0700);
    rd_expect(CMD_VOUT_COMMAND, 16'h0700, "WP 0x20 allows VOUT_COMMAND");
    wr(CMD_VOUT_OV_FAULT_LIMIT, 16'h0000);
    rd_expect(CMD_VOUT_OV_FAULT_LIMIT, RST_VOUT_OV_FAULT_LIMIT, "WP 0x20 blocks limits");
    wr(CMD_WRITE_PROTECT, 16'h0000);
    expect_cml(CML_DATA, "WP 0x20");
    wr(CMD_VOUT_COMMAND, RST_VOUT_COMMAND);
    scen_hit(S_WP_20);

    // Illegal values
    wr(CMD_OPERATION, 16'h0081);
    rd_expect(CMD_OPERATION, 16'h0000, "OPERATION 0x81 rejected");
    expect_cml(CML_DATA, "OPERATION 0x81");
    wr(CMD_WRITE_PROTECT, 16'h0011);
    rd_expect(CMD_WRITE_PROTECT, 16'h0000, "WRITE_PROTECT 0x11 rejected");
    expect_cml(CML_DATA, "WRITE_PROTECT 0x11");
    scen_hit(S_ILLEGAL_VALUE);
  endtask

  task automatic test_faults();
    int s0, ups, off_min, t_off;
    bit en_prev;
    $display("[%0t] -- output faults", $time);
    power_on_nominal();
    rd_expect(CMD_STATUS_WORD, 16'h0000, "powered and good");
    check(alert_n, "SMBALERT# asserted while healthy");

    // OV warning: status only, output stays on
    vout = V_OVWARN;
    wait_samples(DEBOUNCE + 1);
    check(en, "OV warning must not shut down");
    check(!alert_n, "SMBALERT# not asserted on OV warning");
    rd_expect(CMD_STATUS_VOUT, 16'h0040, "OV warning");
    rd_expect(CMD_STATUS_BYTE, 16'h0001, "OV warning summary");
    scen_hit(S_OV_WARN);

    // CLEAR_FAULTS while still above the warning: bit comes back
    send(CMD_CLEAR_FAULTS);
    wait_samples(1);
    rd_expect(CMD_STATUS_VOUT, 16'h0040, "warning re-asserts while present");
    scen_hit(S_FAULT_PERSISTS);

    // Back to nominal: bit is sticky, clear it with write-1-to-clear
    vout = V_NOM;
    wait_samples(2);
    rd_expect(CMD_STATUS_VOUT, 16'h0040, "warning is sticky");
    wr(CMD_STATUS_VOUT, 16'h0080);                          // wrong bit, no effect
    rd_expect(CMD_STATUS_VOUT, 16'h0040, "W1C of other bit");
    wr(CMD_STATUS_VOUT, 16'h0040);
    rd_expect(CMD_STATUS_VOUT, 16'h0000, "W1C clears warning");
    check(alert_n, "SMBALERT# not released after clear");
    scen_hit(S_STATUS_W1C);
    scen_hit(S_ALERT_CYCLE);

    // Spike shorter than the debounce window is ignored
    @(posedge sample);
    repeat (2) @(posedge clk);       // let the DUT consume this sample first
    vout = V_OVF;
    repeat (DEBOUNCE - 1) @(posedge sample);
    #(CLK_NS * 10);
    vout = V_NOM;
    wait_samples(2);
    check(en, "short OV spike shut the output down");
    check(dut.status_vout == 8'h00, "short OV spike set status");
    scen_hit(S_DEBOUNCE_SPIKE);

    // OV fault: shut down and latch
    vout = V_OVF;
    wait_samples(DEBOUNCE + 1);
    check(!en, "OV fault did not shut down");
    rd_expect(CMD_STATUS_VOUT, 16'h00C0, "OV fault + warning");
    rd_expect(CMD_STATUS_WORD, 16'h8861, "OV fault: VOUT, PG#, OFF, VOUT_OV, other");
    vout = V_NOM;
    send(CMD_CLEAR_FAULTS);
    wait_samples(DEBOUNCE + 1);
    check(!en, "latch cleared by CLEAR_FAULTS (should stay off)");
    rd_expect(CMD_STATUS_VOUT, 16'h0000, "status clear after CLEAR_FAULTS");
    scen_hit(S_OV_FAULT_LATCH);
    wr(CMD_OPERATION, 16'h0000);
    wr(CMD_OPERATION, 16'h0080);
    wait_samples(BLANK + DEBOUNCE + 2);
    check(en && pg, "did not recover after OPERATION off/on");
    scen_hit(S_LATCH_RECOVER);

    // UV warning
    vout = V_UVWARN;
    wait_samples(DEBOUNCE + 1);
    check(en && !pg, "UV warning: expected on and not power good");
    rd_expect(CMD_STATUS_VOUT, 16'h0020, "UV warning");
    vout = V_NOM;
    wait_samples(2);
    check(pg, "power good did not return");
    send(CMD_CLEAR_FAULTS);
    scen_hit(S_UV_WARN);

    // UV fault: shut down and latch
    vout = V_UVF;
    wait_samples(DEBOUNCE + 1);
    check(!en, "UV fault did not shut down");
    rd_expect(CMD_STATUS_VOUT, 16'h0030, "UV fault + warning");
    rd_expect(CMD_STATUS_BYTE, 16'h0041, "UV fault summary: OFF + other");
    scen_hit(S_UV_FAULT_LATCH);

    // Soft-start blanking: turn on into a low output
    wr(CMD_OPERATION, 16'h0000);
    send(CMD_CLEAR_FAULTS);
    vout = 16'h0000;
    wr(CMD_OPERATION, 16'h0080);
    s0 = n_samples;
    while (n_samples - s0 < BLANK - 4) @(posedge clk);
    check(en && dut.status_vout == 8'h00, "UV checked during soft-start blanking");
    wait_samples(DEBOUNCE + 6);
    check(!en && dut.status_vout[4], "UV fault not seen after blanking");
    scen_hit(S_UV_BLANKING);
    wr(CMD_OPERATION, 16'h0000);
    vout = V_NOM;
    send(CMD_CLEAR_FAULTS);

    // Response = ignore: OV fault reported, output stays on
    wr(CMD_VOUT_OV_FAULT_RESPONSE, 16'h0000);
    power_on_nominal();
    vout = V_OVF;
    wait_samples(DEBOUNCE + 2);
    check(en, "ignore response still shut down");
    rd_expect(CMD_STATUS_VOUT, 16'h00C0, "ignore response status");
    vout = V_NOM;
    wr(CMD_VOUT_OV_FAULT_RESPONSE, 16'h0080);
    send(CMD_CLEAR_FAULTS);
    scen_hit(S_RESP_IGNORE);

    // Response = hiccup: off while fault present, retries, recovers
    wr(CMD_VOUT_UV_FAULT_RESPONSE, 16'h00C0);
    vout = V_UVF;
    ups = 0;
    off_min = 1 << 30;
    en_prev = en;
    s0 = n_samples;
    t_off = n_samples;
    while (n_samples - s0 < 4 * (HICCUP_OFF + BLANK + DEBOUNCE + 2)) begin
      @(posedge clk);
      if (!en && en_prev) t_off = n_samples;
      if (en && !en_prev) begin
        ups++;
        if (n_samples - t_off < off_min) off_min = n_samples - t_off;
      end
      en_prev = en;
    end
    check(ups >= 2, $sformatf("hiccup restarted %0d times, expected >= 2", ups));
    check(off_min >= HICCUP_OFF - 1, $sformatf("hiccup off time %0d samples, expected >= %0d", off_min, HICCUP_OFF - 1));
    vout = V_NOM;
    wait_samples(HICCUP_OFF + BLANK + DEBOUNCE + 4);
    check(en && pg, "hiccup did not recover when fault cleared");
    wr(CMD_VOUT_UV_FAULT_RESPONSE, 16'h0080);
    send(CMD_CLEAR_FAULTS);
    scen_hit(S_RESP_HICCUP);

    wr(CMD_OPERATION, 16'h0000);
    send(CMD_CLEAR_FAULTS);
    wait_samples(2);
    check(alert_n, "SMBALERT# stuck at end of fault tests");
  endtask

  // ---------------------------------------------------------------------------
  // Coverage report
  // ---------------------------------------------------------------------------
  task automatic report_coverage();
    int holes = 0, n_bins = 0, hit = 0;
    int uns_total = 0, uns_hit = 0;
    string row;
    $display("");
    $display("Command coverage (count per bin, '-' = not applicable)");
    row = $sformatf("%-24s %-4s", "command", "code");
    for (int k = 0; k < K_UNSUP_RD; k++) row = {row, $sformatf(" %7s", kind_name(k))};
    $display("%s", row);
    for (int i = 0; i < NUM_REGS; i++) begin
      logic [7:0] c;
      c = reg_code_at(i);
      row = $sformatf("%-24s 0x%02h", reg_name(c), c);
      for (int k = 0; k < K_UNSUP_RD; k++) begin
        if (cov_applicable(c, k)) begin
          n_bins++;
          if (cov[c][k] > 0) hit++; else holes++;
          if (cov[c][k] > 0) row = {row, $sformatf(" %7d", cov[c][k])};
          else               row = {row, "    HOLE"};
        end else begin
          row = {row, $sformatf(" %7s", "-")};
        end
      end
      $display("%s", row);
    end
    for (int c = 0; c < 256; c++) begin
      if (!reg_known(c[7:0])) begin
        uns_total += 2;
        n_bins += 2;
        if (cov[c][K_UNSUP_RD] > 0) begin uns_hit++; hit++; end else holes++;
        if (cov[c][K_UNSUP_WR] > 0) begin uns_hit++; hit++; end else holes++;
      end
    end
    $display("unsupported codes: %0d/%0d read+write bins hit", uns_hit, uns_total);
    $display("");
    $display("Scenario coverage");
    for (int s = 0; s < NUM_S; s++) begin
      n_bins++;
      if (scen[s] > 0) hit++; else holes++;
      $display("  %-42s %s", scen_name(s), scen[s] > 0 ? "hit" : "HOLE");
    end
    $display("");
    $display("Coverage: %0d/%0d bins (%0d%%), %0d holes", hit, n_bins, (100 * hit) / n_bins, holes);
    if (holes > 0) begin
      errors++;
      $display("ERROR: coverage holes");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  initial begin
    if ($test$plusargs("wave")) begin           // everything (large)
      $dumpfile("tb_pmbus.vcd");
      $dumpvars(0, tb_pmbus);
    end else if ($test$plusargs("vcd_bus")) begin  // pins only, for hw/la_check.py
      $dumpfile("bus.vcd");
      $dumpvars(0, tb_pmbus.scl, tb_pmbus.sda, tb_pmbus.alert_n, tb_pmbus.en, tb_pmbus.pg);
    end
    for (int c = 0; c < 256; c++) for (int k = 0; k < NUM_K; k++) cov[c][k] = 0;
    for (int s = 0; s < NUM_S; s++) scen[s] = 0;

    repeat (10) @(posedge clk);
    rst_n = 1;
    wait_samples(2);

    test_crc_vector();
    test_reset_state();
    test_all_registers();
    test_unsupported_commands();
    test_bus_errors();
    test_write_protect();
    test_faults();
    report_coverage();

    $display("");
    $display("%0d transactions, %0d checks, %0d errors, sim time %0t", n_transactions, checks, errors, $time);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $finish;
  end

  // Watchdog
  initial begin
    #2s;
    $display("ERROR: watchdog timeout");
    $display("TEST FAILED");
    $finish;
  end

endmodule
