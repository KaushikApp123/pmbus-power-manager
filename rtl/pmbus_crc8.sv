// SMBus PEC: CRC-8, polynomial x^8 + x^2 + x + 1 (0x07), init 0x00,
// no reflection, no final XOR. One byte per call, fully combinational.
//
// Useful property: running the CRC over a message followed by its own PEC
// gives 0x00, so the receiver checks "crc == 0" at the end of a write.

module pmbus_crc8 (
  input  logic [7:0] crc_i,
  input  logic [7:0] data_i,
  output logic [7:0] crc_o
);
  always_comb begin
    logic [7:0] c;
    c = crc_i ^ data_i;
    for (int i = 0; i < 8; i++) begin
      c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
    end
    crc_o = c;
  end
endmodule
