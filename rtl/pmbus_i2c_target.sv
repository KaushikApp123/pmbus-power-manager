// I2C / SMBus target, bit level.
//
// Turns SCL/SDA into byte events for pmbus_core. It ACKs its own address and
// every write byte, shifts out read bytes on request, and never stretches the
// clock. All SDA changes are delayed by SDA_HOLD_CYCLES after SCL falls so the
// SMBus 300 ns data hold time is met.
//
// The SMBus timeout resets the state machine and releases SDA if SCL stays low
// for TIMEOUT_CYCLES (25 ms minimum per SMBus, 1.2M cycles at 48 MHz).

module pmbus_i2c_target #(
  parameter int FILTER_LEN      = 3,
  parameter int SDA_HOLD_CYCLES = 16,
  parameter int TIMEOUT_CYCLES  = 1_200_000
)(
  input  logic       clk,
  input  logic       rst_n,
  input  logic [6:0] own_addr_i,

  input  logic       scl_i,
  input  logic       sda_i,
  output logic       sda_oe_o,     // 1 = pull SDA low

  output logic       start_o,      // START or repeated START seen
  output logic       stop_o,       // STOP seen
  output logic       addr_hit_o,   // our address was received (pulse)
  output logic       rw_o,         // direction of the current transfer, 1 = read
  output logic       rx_valid_o,   // write byte received (pulse)
  output logic [7:0] rx_data_o,
  output logic       tx_req_o,     // need the next read byte on tx_data_i
  input  logic [7:0] tx_data_i,    // must be valid within one SCL low period
  output logic       timeout_o     // SCL low timeout (pulse)
);

  // ---------------------------------------------------------------------------
  // Input conditioning
  // ---------------------------------------------------------------------------
  logic scl, sda, scl_d, sda_d;

  pmbus_glitch_filter #(.LEN(FILTER_LEN)) u_scl_flt (.clk, .rst_n, .d_i(scl_i), .q_o(scl));
  pmbus_glitch_filter #(.LEN(FILTER_LEN)) u_sda_flt (.clk, .rst_n, .d_i(sda_i), .q_o(sda));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_d <= 1'b1;
      sda_d <= 1'b1;
    end else begin
      scl_d <= scl;
      sda_d <= sda;
    end
  end

  wire scl_rise  =  scl & ~scl_d;
  wire scl_fall  = ~scl &  scl_d;
  wire start_det =  scl &  scl_d & ~sda &  sda_d;
  wire stop_det  =  scl &  scl_d &  sda & ~sda_d;

  // ---------------------------------------------------------------------------
  // SMBus timeout
  // ---------------------------------------------------------------------------
  localparam int TW = $clog2(TIMEOUT_CYCLES + 1);
  logic [TW-1:0] to_cnt;
  wire  to_hit = ~scl && (to_cnt == TW'(TIMEOUT_CYCLES - 1));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                                 to_cnt <= '0;
    else if (scl)                               to_cnt <= '0;
    else if (to_cnt != TW'(TIMEOUT_CYCLES))     to_cnt <= to_cnt + 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Byte state machine
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE, S_ADDR, S_ADDR_ACK, S_RX, S_RX_ACK, S_TX, S_TX_ACK
  } state_t;

  state_t     state;
  logic [3:0] bit_cnt;
  logic [7:0] shreg;
  logic       drive_req;   // what we want on SDA (1 = low), applied after hold delay
  logic       master_ack;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= S_IDLE;
      bit_cnt    <= '0;
      shreg      <= '0;
      drive_req  <= 1'b0;
      master_ack <= 1'b0;
      rw_o       <= 1'b0;
      rx_data_o  <= '0;
      start_o    <= 1'b0;
      stop_o     <= 1'b0;
      addr_hit_o <= 1'b0;
      rx_valid_o <= 1'b0;
      tx_req_o   <= 1'b0;
      timeout_o  <= 1'b0;
    end else begin
      start_o    <= 1'b0;
      stop_o     <= 1'b0;
      addr_hit_o <= 1'b0;
      rx_valid_o <= 1'b0;
      // First read byte is requested the cycle after the address hit so the
      // core sees the two events separately.
      tx_req_o   <= addr_hit_o & rw_o;
      timeout_o  <= 1'b0;

      if (to_hit) begin
        state     <= S_IDLE;
        drive_req <= 1'b0;
        timeout_o <= 1'b1;
      end else if (start_det) begin
        state     <= S_ADDR;
        bit_cnt   <= '0;
        drive_req <= 1'b0;
        start_o   <= 1'b1;
      end else if (stop_det) begin
        state     <= S_IDLE;
        drive_req <= 1'b0;
        stop_o    <= 1'b1;
      end else begin
        case (state)
          S_IDLE: ;

          S_ADDR: begin
            if (scl_rise) begin
              shreg   <= {shreg[6:0], sda};
              bit_cnt <= bit_cnt + 1'b1;
            end
            if (scl_fall && bit_cnt == 4'd8) begin
              if (shreg[7:1] == own_addr_i) begin
                rw_o       <= shreg[0];
                addr_hit_o <= 1'b1;
                drive_req  <= 1'b1;            // ACK
                state      <= S_ADDR_ACK;
              end else begin
                state      <= S_IDLE;          // not us, wait for next START
              end
            end
          end

          S_ADDR_ACK: begin
            if (scl_fall) begin
              bit_cnt <= rw_o ? 4'd1 : 4'd0;
              if (rw_o) begin
                shreg     <= tx_data_i;
                drive_req <= ~tx_data_i[7];
                state     <= S_TX;
              end else begin
                drive_req <= 1'b0;
                state     <= S_RX;
              end
            end
          end

          S_RX: begin
            if (scl_rise) begin
              shreg   <= {shreg[6:0], sda};
              bit_cnt <= bit_cnt + 1'b1;
            end
            if (scl_fall && bit_cnt == 4'd8) begin
              rx_data_o  <= shreg;
              rx_valid_o <= 1'b1;
              drive_req  <= 1'b1;              // ACK
              state      <= S_RX_ACK;
            end
          end

          S_RX_ACK: begin
            if (scl_fall) begin
              drive_req <= 1'b0;
              bit_cnt   <= '0;
              state     <= S_RX;
            end
          end

          S_TX: begin
            if (scl_fall) begin
              if (bit_cnt == 4'd8) begin
                drive_req <= 1'b0;             // release for master ACK
                tx_req_o  <= 1'b1;             // fetch next byte early
                state     <= S_TX_ACK;
              end else begin
                drive_req <= ~shreg[3'd7 - bit_cnt[2:0]];
                bit_cnt   <= bit_cnt + 1'b1;
              end
            end
          end

          S_TX_ACK: begin
            if (scl_rise) master_ack <= ~sda;
            if (scl_fall) begin
              if (master_ack) begin
                shreg     <= tx_data_i;
                drive_req <= ~tx_data_i[7];
                bit_cnt   <= 4'd1;
                state     <= S_TX;
              end else begin
                state     <= S_IDLE;           // NACK ends the read
              end
            end
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // SDA output with hold delay
  // ---------------------------------------------------------------------------
  localparam int HW = $clog2(SDA_HOLD_CYCLES + 1);
  logic [HW-1:0] hold_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sda_oe_o <= 1'b0;
      hold_cnt <= '0;
    end else if (drive_req == sda_oe_o) begin
      hold_cnt <= '0;
    end else if (hold_cnt == HW'(SDA_HOLD_CYCLES)) begin
      sda_oe_o <= drive_req;
      hold_cnt <= '0;
    end else begin
      hold_cnt <= hold_cnt + 1'b1;
    end
  end

endmodule
