// AUTO-GENERATED from regmap.yaml by gen/gen_regmap.py. Do not edit.
// Register map data for the testbench. Included inside tb_pmbus.

localparam int ACC_RW       = 0;
localparam int ACC_RO_CONST = 1;
localparam int ACC_RO_HW    = 2;
localparam int ACC_W1C_HW   = 3;
localparam int ACC_SEND     = 4;

localparam int NUM_REGS = 19;

function automatic [7:0] reg_code_at(input int i);
  case (i)
    0: return 8'h01;
    1: return 8'h03;
    2: return 8'h10;
    3: return 8'h19;
    4: return 8'h20;
    5: return 8'h21;
    6: return 8'h40;
    7: return 8'h41;
    8: return 8'h42;
    9: return 8'h43;
    10: return 8'h44;
    11: return 8'h45;
    12: return 8'h78;
    13: return 8'h79;
    14: return 8'h7A;
    15: return 8'h7E;
    16: return 8'h8B;
    17: return 8'h98;
    18: return 8'hD0;
    default: return 8'h00;
  endcase
endfunction

function automatic bit reg_known(input [7:0] c);
  case (c)
8'h01, 8'h03, 8'h10, 8'h19, 8'h20, 8'h21, 8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h78, 8'h79, 8'h7A, 8'h7E, 8'h8B, 8'h98, 8'hD0: return 1'b1;
    default: return 1'b0;
  endcase
endfunction

function automatic string reg_name(input [7:0] c);
  case (c)
    8'h01: return "OPERATION";
    8'h03: return "CLEAR_FAULTS";
    8'h10: return "WRITE_PROTECT";
    8'h19: return "CAPABILITY";
    8'h20: return "VOUT_MODE";
    8'h21: return "VOUT_COMMAND";
    8'h40: return "VOUT_OV_FAULT_LIMIT";
    8'h41: return "VOUT_OV_FAULT_RESPONSE";
    8'h42: return "VOUT_OV_WARN_LIMIT";
    8'h43: return "VOUT_UV_WARN_LIMIT";
    8'h44: return "VOUT_UV_FAULT_LIMIT";
    8'h45: return "VOUT_UV_FAULT_RESPONSE";
    8'h78: return "STATUS_BYTE";
    8'h79: return "STATUS_WORD";
    8'h7A: return "STATUS_VOUT";
    8'h7E: return "STATUS_CML";
    8'h8B: return "READ_VOUT";
    8'h98: return "PMBUS_REVISION";
    8'hD0: return "MFR_SIM_VOUT";
    default: return "UNSUPPORTED";
  endcase
endfunction

function automatic int reg_access(input [7:0] c);
  case (c)
    8'h01: return 0;
    8'h03: return 4;
    8'h10: return 0;
    8'h19: return 1;
    8'h20: return 1;
    8'h21: return 0;
    8'h40: return 0;
    8'h41: return 0;
    8'h42: return 0;
    8'h43: return 0;
    8'h44: return 0;
    8'h45: return 0;
    8'h78: return 2;
    8'h79: return 2;
    8'h7A: return 3;
    8'h7E: return 3;
    8'h8B: return 2;
    8'h98: return 1;
    8'hD0: return 0;
    default: return -1;
  endcase
endfunction

function automatic int reg_size(input [7:0] c);
  case (c)
    8'h01: return 1;
    8'h03: return 0;
    8'h10: return 1;
    8'h19: return 1;
    8'h20: return 1;
    8'h21: return 2;
    8'h40: return 2;
    8'h41: return 1;
    8'h42: return 2;
    8'h43: return 2;
    8'h44: return 2;
    8'h45: return 1;
    8'h78: return 1;
    8'h79: return 2;
    8'h7A: return 1;
    8'h7E: return 1;
    8'h8B: return 2;
    8'h98: return 1;
    8'hD0: return 2;
    default: return 0;
  endcase
endfunction

function automatic [15:0] reg_reset(input [7:0] c);
  case (c)
    8'h01: return 16'h0000;
    8'h03: return 16'h0000;
    8'h10: return 16'h0000;
    8'h19: return 16'h00B0;
    8'h20: return 16'h0017;
    8'h21: return 16'h0699;
    8'h40: return 16'h0742;
    8'h41: return 16'h0080;
    8'h42: return 16'h06EE;
    8'h43: return 16'h0645;
    8'h44: return 16'h05F0;
    8'h45: return 16'h0080;
    8'h78: return 16'h0000;
    8'h79: return 16'h0000;
    8'h7A: return 16'h0000;
    8'h7E: return 16'h0000;
    8'h8B: return 16'h0000;
    8'h98: return 16'h0033;
    8'hD0: return 16'h0000;
    default: return 16'h0000;
  endcase
endfunction

function automatic int reg_num_test_values(input [7:0] c);
  case (c)
    8'h01: return 3;
    8'h03: return 0;
    8'h10: return 4;
    8'h19: return 2;
    8'h20: return 2;
    8'h21: return 2;
    8'h40: return 2;
    8'h41: return 2;
    8'h42: return 2;
    8'h43: return 2;
    8'h44: return 2;
    8'h45: return 2;
    8'h78: return 2;
    8'h79: return 2;
    8'h7A: return 2;
    8'h7E: return 2;
    8'h8B: return 2;
    8'h98: return 2;
    8'hD0: return 2;
    default: return 0;
  endcase
endfunction

function automatic [15:0] reg_test_value(input [7:0] c, input int i);
  case (c)
    8'h01: case (i)
        0: return 16'h0080;
        1: return 16'h0040;
        2: return 16'h0000;
        default: return 16'h0000;
      endcase
    8'h10: case (i)
        0: return 16'h0080;
        1: return 16'h0040;
        2: return 16'h0020;
        3: return 16'h0000;
        default: return 16'h0000;
      endcase
    8'h19: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h20: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h21: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h40: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h41: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h42: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h43: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h44: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h45: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h78: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h79: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h7A: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h7E: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'h8B: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    8'h98: case (i)
        0: return 16'h0055;
        1: return 16'h00AA;
        default: return 16'h0000;
      endcase
    8'hD0: case (i)
        0: return 16'h5555;
        1: return 16'hAAAA;
        default: return 16'h0000;
      endcase
    default: return 16'h0000;
  endcase
endfunction

// Coverage bins that apply to each command. Kinds are defined in tb_pmbus.
function automatic bit cov_applicable(input [7:0] c, input int kind);
  int acc;
  acc = reg_access(c);
  if (acc < 0) return (kind == K_UNSUP_RD) || (kind == K_UNSUP_WR);
  case (kind)
    K_RD, K_RD_PEC:                  return acc != ACC_SEND;
    K_WR, K_WR_PEC, K_WR_BADPEC,
    K_WR_BADLEN:                     return acc == ACC_RW || acc == ACC_W1C_HW || acc == ACC_SEND;
    K_WR_REJECT:                     return acc == ACC_RO_CONST || acc == ACC_RO_HW;
    K_RD_REJECT:                     return acc == ACC_SEND;
    default:                         return 1'b0;
  endcase
endfunction
