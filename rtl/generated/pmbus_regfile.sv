// AUTO-GENERATED from regmap.yaml by gen/gen_regmap.py. Do not edit.
//
// Command decode, register storage, read mux and write-protect / value checks.
// The transaction layer (pmbus_core) owns byte counting and PEC; it asks this
// block what a command code means and pulses wr_en_i to commit a write.

module pmbus_regfile (
  input  logic        clk,
  input  logic        rst_n,

  // Lookup for the command currently addressed by the host
  input  logic [7:0]  cmd_i,
  output logic        cmd_valid_o,     // command is in the register map
  output logic        cmd_readable_o,
  output logic        cmd_writable_o,
  output logic [1:0]  cmd_size_o,      // data bytes: 0, 1 or 2
  output logic        cmd_wp_ok_o,     // write allowed at current WRITE_PROTECT level
  output logic        cmd_value_ok_o,  // wdata_i is a legal value for this command
  output logic [15:0] rdata_o,

  // Commit
  input  logic        wr_en_i,
  input  logic [15:0] wdata_i,

  // Stored registers
  output logic [7:0] operation_q,
  output logic [7:0] write_protect_q,
  output logic [15:0] vout_command_q,
  output logic [15:0] vout_ov_fault_limit_q,
  output logic [7:0] vout_ov_fault_response_q,
  output logic [15:0] vout_ov_warn_limit_q,
  output logic [15:0] vout_uv_warn_limit_q,
  output logic [15:0] vout_uv_fault_limit_q,
  output logic [7:0] vout_uv_fault_response_q,
  output logic [15:0] mfr_sim_vout_q,

  // Hardware-owned values
  input  logic [7:0] status_byte_i,
  input  logic [15:0] status_word_i,
  input  logic [7:0] status_vout_i,
  input  logic [7:0] status_cml_i,
  input  logic [15:0] read_vout_i,

  // Write strobes for hardware-owned commands (data on wdata_i)
  output logic        clear_faults_wr,
  output logic        status_vout_wr,
  output logic        status_cml_wr
);

  logic [7:0] wp_level;
  assign wp_level = write_protect_q;

  // ---------------------------------------------------------------------------
  // Decode
  // ---------------------------------------------------------------------------
  always_comb begin
    cmd_valid_o    = 1'b0;
    cmd_readable_o = 1'b0;
    cmd_writable_o = 1'b0;
    cmd_size_o     = 2'd0;
    cmd_wp_ok_o    = (wp_level == 8'h00);
    cmd_value_ok_o = 1'b1;
    rdata_o        = 16'hFFFF;
    case (cmd_i)
      // OPERATION (rw, 1 byte)
      8'h01: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        cmd_wp_ok_o    = (wp_level == 8'h00) || (wp_level == 8'h40) || (wp_level == 8'h20);
        cmd_value_ok_o = (wdata_i[7:0] == 8'h00) || (wdata_i[7:0] == 8'h40) || (wdata_i[7:0] == 8'h80);
        rdata_o        = {8'h00, operation_q};
      end
      // CLEAR_FAULTS (send, 0 bytes)
      8'h03: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b0;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd0;
      end
      // WRITE_PROTECT (rw, 1 byte)
      8'h10: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        cmd_wp_ok_o    = (wp_level == 8'h00) || (wp_level == 8'h80) || (wp_level == 8'h40) || (wp_level == 8'h20);
        cmd_value_ok_o = (wdata_i[7:0] == 8'h00) || (wdata_i[7:0] == 8'h20) || (wdata_i[7:0] == 8'h40) || (wdata_i[7:0] == 8'h80);
        rdata_o        = {8'h00, write_protect_q};
      end
      // CAPABILITY (ro_const, 1 byte)
      8'h19: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd1;
        rdata_o        = 16'h00B0;
      end
      // VOUT_MODE (ro_const, 1 byte)
      8'h20: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd1;
        rdata_o        = 16'h0017;
      end
      // VOUT_COMMAND (rw, 2 bytes)
      8'h21: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        cmd_wp_ok_o    = (wp_level == 8'h00) || (wp_level == 8'h20);
        rdata_o        = vout_command_q;
      end
      // VOUT_OV_FAULT_LIMIT (rw, 2 bytes)
      8'h40: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        rdata_o        = vout_ov_fault_limit_q;
      end
      // VOUT_OV_FAULT_RESPONSE (rw, 1 byte)
      8'h41: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        rdata_o        = {8'h00, vout_ov_fault_response_q};
      end
      // VOUT_OV_WARN_LIMIT (rw, 2 bytes)
      8'h42: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        rdata_o        = vout_ov_warn_limit_q;
      end
      // VOUT_UV_WARN_LIMIT (rw, 2 bytes)
      8'h43: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        rdata_o        = vout_uv_warn_limit_q;
      end
      // VOUT_UV_FAULT_LIMIT (rw, 2 bytes)
      8'h44: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        rdata_o        = vout_uv_fault_limit_q;
      end
      // VOUT_UV_FAULT_RESPONSE (rw, 1 byte)
      8'h45: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        rdata_o        = {8'h00, vout_uv_fault_response_q};
      end
      // STATUS_BYTE (ro_hw, 1 byte)
      8'h78: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd1;
        rdata_o        = {8'h00, status_byte_i};
      end
      // STATUS_WORD (ro_hw, 2 bytes)
      8'h79: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd2;
        rdata_o        = status_word_i;
      end
      // STATUS_VOUT (w1c_hw, 1 byte)
      8'h7A: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        rdata_o        = {8'h00, status_vout_i};
      end
      // STATUS_CML (w1c_hw, 1 byte)
      8'h7E: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd1;
        rdata_o        = {8'h00, status_cml_i};
      end
      // READ_VOUT (ro_hw, 2 bytes)
      8'h8B: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd2;
        rdata_o        = read_vout_i;
      end
      // PMBUS_REVISION (ro_const, 1 byte)
      8'h98: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b0;
        cmd_size_o     = 2'd1;
        rdata_o        = 16'h0033;
      end
      // MFR_SIM_VOUT (rw, 2 bytes)
      8'hD0: begin
        cmd_valid_o    = 1'b1;
        cmd_readable_o = 1'b1;
        cmd_writable_o = 1'b1;
        cmd_size_o     = 2'd2;
        rdata_o        = mfr_sim_vout_q;
      end
      default: ;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      operation_q <= 8'h00;
      write_protect_q <= 8'h00;
      vout_command_q <= 16'h0699;
      vout_ov_fault_limit_q <= 16'h0742;
      vout_ov_fault_response_q <= 8'h80;
      vout_ov_warn_limit_q <= 16'h06EE;
      vout_uv_warn_limit_q <= 16'h0645;
      vout_uv_fault_limit_q <= 16'h05F0;
      vout_uv_fault_response_q <= 8'h80;
      mfr_sim_vout_q <= 16'h0000;
    end else if (wr_en_i) begin
      case (cmd_i)
        8'h01: operation_q <= wdata_i[7:0];
        8'h10: write_protect_q <= wdata_i[7:0];
        8'h21: vout_command_q <= wdata_i[15:0];
        8'h40: vout_ov_fault_limit_q <= wdata_i[15:0];
        8'h41: vout_ov_fault_response_q <= wdata_i[7:0];
        8'h42: vout_ov_warn_limit_q <= wdata_i[15:0];
        8'h43: vout_uv_warn_limit_q <= wdata_i[15:0];
        8'h44: vout_uv_fault_limit_q <= wdata_i[15:0];
        8'h45: vout_uv_fault_response_q <= wdata_i[7:0];
        8'hD0: mfr_sim_vout_q <= wdata_i[15:0];
        default: ;
      endcase
    end
  end

  // Strobes
  assign clear_faults_wr = wr_en_i && (cmd_i == 8'h03);
  assign status_vout_wr = wr_en_i && (cmd_i == 8'h7A);
  assign status_cml_wr = wr_en_i && (cmd_i == 8'h7E);

endmodule
