// AUTO-GENERATED from regmap.yaml by gen/gen_regmap.py. Do not edit.
package pmbus_regmap_pkg;

  localparam logic [6:0] DEFAULT_ADDR = 7'h40;

  // Command codes
  localparam logic [7:0] CMD_OPERATION = 8'h01;
  localparam logic [7:0] CMD_CLEAR_FAULTS = 8'h03;
  localparam logic [7:0] CMD_WRITE_PROTECT = 8'h10;
  localparam logic [7:0] CMD_CAPABILITY = 8'h19;
  localparam logic [7:0] CMD_VOUT_MODE = 8'h20;
  localparam logic [7:0] CMD_VOUT_COMMAND = 8'h21;
  localparam logic [7:0] CMD_VOUT_OV_FAULT_LIMIT = 8'h40;
  localparam logic [7:0] CMD_VOUT_OV_FAULT_RESPONSE = 8'h41;
  localparam logic [7:0] CMD_VOUT_OV_WARN_LIMIT = 8'h42;
  localparam logic [7:0] CMD_VOUT_UV_WARN_LIMIT = 8'h43;
  localparam logic [7:0] CMD_VOUT_UV_FAULT_LIMIT = 8'h44;
  localparam logic [7:0] CMD_VOUT_UV_FAULT_RESPONSE = 8'h45;
  localparam logic [7:0] CMD_STATUS_BYTE = 8'h78;
  localparam logic [7:0] CMD_STATUS_WORD = 8'h79;
  localparam logic [7:0] CMD_STATUS_VOUT = 8'h7A;
  localparam logic [7:0] CMD_STATUS_CML = 8'h7E;
  localparam logic [7:0] CMD_READ_VOUT = 8'h8B;
  localparam logic [7:0] CMD_PMBUS_REVISION = 8'h98;
  localparam logic [7:0] CMD_MFR_SIM_VOUT = 8'hD0;

  // Reset / constant values
  localparam logic [7:0] RST_OPERATION = 8'h00;
  localparam logic [7:0] RST_WRITE_PROTECT = 8'h00;
  localparam logic [7:0] RST_CAPABILITY = 8'hB0;
  localparam logic [7:0] RST_VOUT_MODE = 8'h17;
  localparam logic [15:0] RST_VOUT_COMMAND = 16'h0699;
  localparam logic [15:0] RST_VOUT_OV_FAULT_LIMIT = 16'h0742;
  localparam logic [7:0] RST_VOUT_OV_FAULT_RESPONSE = 8'h80;
  localparam logic [15:0] RST_VOUT_OV_WARN_LIMIT = 16'h06EE;
  localparam logic [15:0] RST_VOUT_UV_WARN_LIMIT = 16'h0645;
  localparam logic [15:0] RST_VOUT_UV_FAULT_LIMIT = 16'h05F0;
  localparam logic [7:0] RST_VOUT_UV_FAULT_RESPONSE = 8'h80;
  localparam logic [7:0] RST_PMBUS_REVISION = 8'h33;
  localparam logic [15:0] RST_MFR_SIM_VOUT = 16'h0000;

  // Fault response encodings (bits 7:6 of *_FAULT_RESPONSE)
  localparam logic [1:0] RESP_IGNORE  = 2'b00;
  localparam logic [1:0] RESP_HICCUP  = 2'b11;  // off while fault present
  // 2'b01 and 2'b10 both mean shut down and latch off

endpackage
