// Bit-banged I2C / PMBus host for the testbench. Included inside tb_pmbus.
//
// Bus rule used here: between bits SCL is low. After i2c_stop both lines are
// released. All PEC math is done with tb_crc8, which is written independently
// of the RTL CRC.

bit scl_held_low = 0;

function automatic [7:0] tb_crc8(input [7:0] crc, input [7:0] data);
  logic [7:0] c;
  c = crc ^ data;
  repeat (8) c = c[7] ? ({c[6:0], 1'b0} ^ 8'h07) : {c[6:0], 1'b0};
  return c;
endfunction

// ---------------------------------------------------------------------------
// Bit level
// ---------------------------------------------------------------------------
task automatic i2c_start();
  if (scl_held_low) begin            // repeated START
    m_sda_oe = 0;  #(T_Q);
    m_scl_oe = 0;  #(T_HALF);
  end
  m_sda_oe = 1;  #(T_HALF);
  m_scl_oe = 1;  #(T_Q);
  scl_held_low = 1;
endtask

task automatic i2c_stop();
  m_sda_oe = 1;  #(T_Q);
  m_scl_oe = 0;  #(T_HALF);
  m_sda_oe = 0;  #(T_HALF);
  scl_held_low = 0;
endtask

task automatic i2c_write_bit(input bit b);
  m_sda_oe = ~b; #(T_Q);
  m_scl_oe = 0;  #(T_HALF);
  m_scl_oe = 1;  #(T_Q);
endtask

task automatic i2c_read_bit(output bit b);
  m_sda_oe = 0;  #(T_Q);
  m_scl_oe = 0;  #(T_HALF / 2);
  b = sda;       #(T_HALF / 2);
  m_scl_oe = 1;  #(T_Q);
endtask

task automatic i2c_write_byte(input [7:0] data, output bit ack);
  bit b;
  for (int i = 7; i >= 0; i--) i2c_write_bit(data[i]);
  i2c_read_bit(b);
  ack = ~b;
endtask

task automatic i2c_read_byte(output [7:0] data, input bit ack);
  bit b;
  for (int i = 7; i >= 0; i--) begin
    i2c_read_bit(b);
    data[i] = b;
  end
  i2c_write_bit(~ack);
endtask

// Send only the first nbits of a byte (for aborted-byte tests)
task automatic i2c_write_partial(input [7:0] data, input int nbits);
  for (int i = 7; i > 7 - nbits; i--) i2c_write_bit(data[i]);
endtask

// ---------------------------------------------------------------------------
// PMBus transactions
// ---------------------------------------------------------------------------
localparam int PEC_NONE = 0;
localparam int PEC_GOOD = 1;
localparam int PEC_BAD  = 2;

int n_transactions = 0;

// Write cmd followed by nbytes data bytes. Bytes 0-1 come from data (low byte
// first), any extra bytes are filler. pec_mode adds a good or corrupted PEC.
task automatic pm_write(input [7:0] cmd, input [15:0] data, input int nbytes,
                        input int pec_mode, output bit acked);
  bit         a;
  logic [7:0] crc, b;
  crc = 8'h00;
  i2c_start();
  i2c_write_byte({TB_ADDR, 1'b0}, a);
  acked = a;
  crc = tb_crc8(crc, {TB_ADDR, 1'b0});
  if (a) begin
    i2c_write_byte(cmd, a);  acked &= a;
    crc = tb_crc8(crc, cmd);
    for (int i = 0; i < nbytes; i++) begin
      b = (i < 2) ? data[8*i +: 8] : (8'hA5 ^ i[7:0]);
      i2c_write_byte(b, a);  acked &= a;
      crc = tb_crc8(crc, b);
    end
    if (pec_mode == PEC_GOOD) begin i2c_write_byte(crc, a);         acked &= a; end
    if (pec_mode == PEC_BAD)  begin i2c_write_byte(crc ^ 8'h5A, a); acked &= a; end
  end
  i2c_stop();
  #(T_HALF);
  n_transactions++;
endtask

// Read nbytes after cmd. With use_pec the PEC byte is clocked out and checked.
task automatic pm_read(input [7:0] cmd, input int nbytes, input bit use_pec,
                       output [15:0] data, output bit pec_ok, output bit acked);
  bit         a;
  logic [7:0] crc, b, pec;
  crc    = 8'h00;
  data   = 16'h0000;
  pec_ok = 0;
  i2c_start();
  i2c_write_byte({TB_ADDR, 1'b0}, a);  acked = a;
  crc = tb_crc8(crc, {TB_ADDR, 1'b0});
  if (a) begin
    i2c_write_byte(cmd, a);  acked &= a;
    crc = tb_crc8(crc, cmd);
    i2c_start();                       // repeated START
    i2c_write_byte({TB_ADDR, 1'b1}, a);  acked &= a;
    crc = tb_crc8(crc, {TB_ADDR, 1'b1});
    for (int i = 0; i < nbytes; i++) begin
      i2c_read_byte(b, (i < nbytes - 1) || use_pec);
      if (i < 2) data[8*i +: 8] = b;
      crc = tb_crc8(crc, b);
    end
    if (use_pec) begin
      i2c_read_byte(pec, 1'b0);
      pec_ok = (pec == crc);
    end
  end
  i2c_stop();
  #(T_HALF);
  n_transactions++;
endtask
