// PMBus transaction layer.
//
// Write:  S Addr+W Cmd [Data0 [Data1]] [PEC] P
// Read:   S Addr+W Cmd Sr Addr+R Data0 [Data1] [PEC] P
//
// Rules this block enforces:
//  * Writes are buffered and committed only on STOP, so an aborted or
//    malformed transaction never changes a register.
//  * Byte count after the command must equal the command size (no PEC) or
//    size + 1 (last byte is PEC). PEC is checked as crc(all bytes) == 0.
//  * Reads snapshot the register at the Addr+R phase, so a word cannot tear
//    between its two bytes. The byte after the data is the PEC; the host
//    decides whether to clock it out.
//  * Errors set STATUS_CML bits:
//      [7] invalid command  - unknown code, write to read-only, read of send-byte
//      [6] invalid data     - wrong byte count, illegal value, write-protected
//      [5] PEC failed
//      [1] other            - SMBus timeout during a transaction

module pmbus_core (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [6:0]  own_addr_i,

  // Byte events from pmbus_i2c_target
  input  logic        start_i,
  input  logic        stop_i,
  input  logic        addr_hit_i,
  input  logic        rw_i,
  input  logic        rx_valid_i,
  input  logic [7:0]  rx_data_i,
  input  logic        tx_req_i,
  output logic [7:0]  tx_data_o,
  input  logic        timeout_i,

  // Register file lookup / commit
  output logic [7:0]  cmd_o,
  input  logic        cmd_valid_i,
  input  logic        cmd_readable_i,
  input  logic        cmd_writable_i,
  input  logic [1:0]  cmd_size_i,
  input  logic        cmd_wp_ok_i,
  input  logic        cmd_value_ok_i,
  input  logic [15:0] rdata_i,
  output logic        wr_en_o,
  output logic [15:0] wdata_o,

  // STATUS_CML
  input  logic        clear_faults_i,
  input  logic        cml_w1c_i,        // write-1-to-clear strobe, mask on wdata_o[7:0]
  output logic [7:0]  status_cml_o
);

  // ---------------------------------------------------------------------------
  // Transaction state
  // ---------------------------------------------------------------------------
  logic        in_txn;       // our address was hit since the last START
  logic        rd_phase;     // current transfer is a read
  logic        sr_cmd_ok;    // repeated START came right after a lone command byte
  logic [2:0]  wr_cnt;       // bytes after Addr+W, including command, saturates at 7
  logic [7:0]  buf0, buf1;
  logic [7:0]  crc;
  logic        rd_ok;
  logic [15:0] rd_shadow;
  logic [1:0]  rd_size;
  logic [1:0]  rd_idx;       // saturates at 3

  assign wdata_o = {buf1, buf0};

  // ---------------------------------------------------------------------------
  // Registered register-file lookup. The command byte and data bytes arrive at
  // least one SCL period before they are used (at Addr+R or STOP), so one
  // pipeline stage costs nothing and takes the decode off the critical path.
  // ---------------------------------------------------------------------------
  logic        cmd_valid, cmd_readable, cmd_writable, cmd_wp_ok, cmd_value_ok;
  logic [1:0]  cmd_size;
  logic [15:0] rdata;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_valid    <= 1'b0;
      cmd_readable <= 1'b0;
      cmd_writable <= 1'b0;
      cmd_wp_ok    <= 1'b0;
      cmd_value_ok <= 1'b0;
      cmd_size     <= '0;
      rdata        <= '0;
    end else begin
      cmd_valid    <= cmd_valid_i;
      cmd_readable <= cmd_readable_i;
      cmd_writable <= cmd_writable_i;
      cmd_wp_ok    <= cmd_wp_ok_i;
      cmd_value_ok <= cmd_value_ok_i;
      cmd_size     <= cmd_size_i;
      rdata        <= rdata_i;
    end
  end

  // ---------------------------------------------------------------------------
  // CRC datapath (one byte per event)
  // ---------------------------------------------------------------------------
  logic [7:0] crc_base, crc_data, crc_next;
  logic [7:0] tx_byte;

  // Next read byte: data, then PEC, then 0xFF
  always_comb begin
    if (!rd_ok)                     tx_byte = 8'hFF;
    else if (rd_idx < rd_size)      tx_byte = rd_idx[0] ? rd_shadow[15:8] : rd_shadow[7:0];
    else if (rd_idx == rd_size)     tx_byte = crc;
    else                            tx_byte = 8'hFF;
  end

  always_comb begin
    crc_base = crc;
    crc_data = rx_data_i;
    if (addr_hit_i) begin
      crc_base = (rw_i && sr_cmd_ok) ? crc : 8'h00;
      crc_data = {own_addr_i, rw_i};
    end else if (tx_req_i) begin
      crc_data = tx_byte;
    end
  end

  pmbus_crc8 u_crc (.crc_i(crc_base), .data_i(crc_data), .crc_o(crc_next));

  // ---------------------------------------------------------------------------
  // Write evaluation at STOP
  // ---------------------------------------------------------------------------
  logic [2:0] n_data;
  logic       len_exact, len_pec, do_commit;
  logic       err_cmd, err_data, err_pec;

  assign n_data    = wr_cnt - 3'd1;
  assign len_exact = (n_data == {1'b0, cmd_size});
  assign len_pec   = (n_data == {1'b0, cmd_size} + 3'd1);

  always_comb begin
    err_cmd  = 1'b0;
    err_data = 1'b0;
    err_pec  = 1'b0;
    if (!cmd_valid || !cmd_writable)       err_cmd  = 1'b1;
    else if (!len_exact && !len_pec)           err_data = 1'b1;
    else if (len_pec && crc != 8'h00)          err_pec  = 1'b1;
    else if (!cmd_wp_ok || !cmd_value_ok)  err_data = 1'b1;
  end

  wire write_done = stop_i && in_txn && !rd_phase && (wr_cnt != 3'd0);
  assign do_commit = write_done && !err_cmd && !err_data && !err_pec;

  // ---------------------------------------------------------------------------
  // Sequencing
  // ---------------------------------------------------------------------------
  logic set_cmd, set_data, set_pec, set_other;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_txn    <= 1'b0;
      rd_phase  <= 1'b0;
      sr_cmd_ok <= 1'b0;
      wr_cnt    <= '0;
      buf0      <= '0;
      buf1      <= '0;
      crc       <= '0;
      cmd_o     <= '0;
      rd_ok     <= 1'b0;
      rd_shadow <= '0;
      rd_size   <= '0;
      rd_idx    <= '0;
      tx_data_o <= 8'hFF;
      wr_en_o   <= 1'b0;
      set_cmd   <= 1'b0;
      set_data  <= 1'b0;
      set_pec   <= 1'b0;
      set_other <= 1'b0;
    end else begin
      wr_en_o   <= do_commit;
      set_cmd   <= 1'b0;
      set_data  <= 1'b0;
      set_pec   <= 1'b0;
      set_other <= 1'b0;

      if (timeout_i) begin
        set_other <= in_txn;
        in_txn    <= 1'b0;
        rd_phase  <= 1'b0;
        sr_cmd_ok <= 1'b0;
        wr_cnt    <= '0;
      end else if (start_i) begin
        // A repeated START keeps the command only if exactly one byte
        // (the command) was written. Anything else is discarded.
        sr_cmd_ok <= in_txn && !rd_phase && (wr_cnt == 3'd1);
        in_txn    <= 1'b0;
      end else if (addr_hit_i) begin
        in_txn    <= 1'b1;
        rd_phase  <= rw_i;
        crc       <= crc_next;
        sr_cmd_ok <= 1'b0;
        if (rw_i) begin
          rd_ok     <= sr_cmd_ok && cmd_valid && cmd_readable;
          rd_shadow <= rdata;
          rd_size   <= cmd_size;
          rd_idx    <= '0;
          set_cmd   <= sr_cmd_ok && !(cmd_valid && cmd_readable);
        end else begin
          wr_cnt    <= '0;
        end
      end else if (rx_valid_i && in_txn && !rd_phase) begin
        crc <= crc_next;
        case (wr_cnt)
          3'd0:    cmd_o <= rx_data_i;
          3'd1:    buf0  <= rx_data_i;
          3'd2:    buf1  <= rx_data_i;
          default: ;   // PEC or overflow, only feeds the CRC
        endcase
        if (wr_cnt == 3'd1) buf1 <= 8'h00;
        if (wr_cnt != 3'd7) wr_cnt <= wr_cnt + 3'd1;
      end else if (tx_req_i && in_txn && rd_phase) begin
        tx_data_o <= tx_byte;
        if (rd_ok && rd_idx < rd_size) crc <= crc_next;
        if (rd_idx != 2'd3) rd_idx <= rd_idx + 2'd1;
      end else if (stop_i) begin
        if (write_done) begin
          set_cmd  <= err_cmd;
          set_data <= err_data;
          set_pec  <= err_pec;
        end
        in_txn    <= 1'b0;
        rd_phase  <= 1'b0;
        sr_cmd_ok <= 1'b0;
        wr_cnt    <= '0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // STATUS_CML (sticky, set wins over clear)
  // ---------------------------------------------------------------------------
  logic [7:0] cml_set, cml_clr;
  assign cml_set = {set_cmd, set_data, set_pec, 3'b000, set_other, 1'b0};
  assign cml_clr = clear_faults_i ? 8'hFF : (cml_w1c_i ? wdata_o[7:0] : 8'h00);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) status_cml_o <= '0;
    else        status_cml_o <= (status_cml_o & ~cml_clr) | cml_set;
  end

endmodule
