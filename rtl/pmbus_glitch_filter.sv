// Two-flop synchronizer plus a digital glitch filter. The output only changes
// after the synchronized input has held a new level for LEN clock cycles.
// At 48 MHz, LEN = 3 rejects spikes shorter than about 60 ns (SMBus asks for 50 ns).

module pmbus_glitch_filter #(
  parameter int LEN = 3
)(
  input  logic clk,
  input  logic rst_n,
  input  logic d_i,      // asynchronous pin
  output logic q_o
);
  localparam int CW = (LEN < 2) ? 1 : $clog2(LEN + 1);

  logic [1:0]    sync;
  logic [CW-1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync <= 2'b11;          // bus idles high
      cnt  <= '0;
      q_o  <= 1'b1;
    end else begin
      sync <= {sync[0], d_i};
      if (sync[1] == q_o) begin
        cnt <= '0;
      end else if (cnt == CW'(LEN - 1)) begin
        q_o <= sync[1];
        cnt <= '0;
      end else begin
        cnt <= cnt + 1'b1;
      end
    end
  end
endmodule
