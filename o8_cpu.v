module o8_cpu(
    clk_i,
    rst_i,
    int_i,

    addr_o,
    data_i,
    data_o,

    rd_o,
    wr_o,
    ack_i,
    err_i,
);

task  error;
input msg;
begin
    $display(msg);
    #1 $finish();
end
endtask

input  wire clk_i;              // Clock
input  wire rst_i;              // Synchrnonous reset
input  wire int_i;              // Interrupt

output wire [15:0] addr_o;      // Address
input  wire [ 7:0] data_i;      // Data in
output reg  [ 7:0] data_o;      // Data out

output reg  rd_o;               // Read output
output reg  wr_o;               // Write output
input  wire ack_i;              // Acknowledge input
input  wire err_i;              // Error input

reg [ 7:0]   ra;        // A register
reg [ 7:0]   rb;        // B register
reg [15:0]   ix;        // I register
reg [15:0]   sp;        // SP register
reg [ 5:0]   cc;        // CC register
reg [15:0]   ip;        // IP register
reg [ 7:0]   ir;        // Current instruction register

parameter IN_ZERO = 4'b0000;
parameter IN_BIT  = 4'b0001;
parameter IN_A    = 4'b0010;
parameter IN_B    = 4'b0011;
parameter IN_I    = 4'b0100;
parameter IN_S    = 4'b0101;
parameter IN_CC   = 4'b0110;
parameter IN_IP   = 4'b0111;
parameter IN_IRLIT= 4'b1000;

parameter IN_ABX  = IN_A;
parameter IN_ISX  = IN_I;

parameter DATA_A   = 3'b000;
parameter DATA_B   = 3'b001;
parameter DATA_IL  = 3'b010;
parameter DATA_IH  = 3'b011;
parameter DATA_IPL = 3'b100;
parameter DATA_IPH = 3'b101;
parameter DATA_CC  = 3'b110;

parameter DATA_ABX = DATA_A;

parameter WR_IGNORE = 4'b0000;
parameter WR_A      = 4'b0010;
parameter WR_B      = 4'b0011;
parameter WR_IL     = 4'b0100;
parameter WR_SL     = 4'b0101;
parameter WR_IH     = 4'b0110;
parameter WR_SH     = 4'b0111;
parameter WR_IPH    = 4'b1000;
parameter WR_IR     = 4'b1001;

parameter WR_ABX    = WR_A;
parameter WR_ISLX   = WR_IL;
parameter WR_ISHX   = WR_IH;

parameter WRIPL_DONT = 2'b00;
parameter WRIPL_IR   = 2'b10;
parameter WRIPL_ALU  = 2'b11;

reg [3:0]    left_sel;
reg [3:0]    right_sel;
reg [3:0]    data_sel;
reg [3:0]    write_sel;
reg [1:0]    write_ipl;

reg  [7:0]    left;      // Left bus
reg  [7:0]    right;     // Right bus
wire [7:0]    res;       // Result bus

// ALU immediate outputs
wire op_zf, op_cf, op_of, op_sf, op_pf;

// Previous op ALU outputs
reg prev_zf, prev_cf, prev_of, prev_sf, prev_pf;

// Program ALU flags
wire pg_zf, pg_cf, pg_of, pg_sf, pg_pf, pg_if;

// Flag updates
parameter CC_IGNORE = 0;
parameter CC_RES    = 1;
parameter CC_ZSP    = 2;
parameter CC_ALL    = 3;
reg [1:0] cc_sel;

// Conditional branches
parameter CN_ALWAYS     = 0;
parameter CN_O          = 1;
parameter CN_Z          = 2;
parameter CN_NZ         = 3;
parameter CN_C          = 4;
parameter CN_NC         = 5;
parameter CN_LEU        = 6;
parameter CN_GU         = 7;
parameter CN_LS         = 8;
parameter CN_GES        = 9;
parameter CN_LES        = 10;
parameter CN_GS         = 11;
parameter CN_S          = 12;
parameter CN_NS         = 13;
parameter CN_P          = 14;
parameter CN_NP         = 15;
wire [3:0] cond;
reg        cond_true;

// Active (ALU input) flags
reg alu_cf;

// ALU source control
parameter FS_PREV = 0;  // Previous op
parameter FS_PG   = 1;  // Program values
parameter FS_ZERO = 2;  // Zero
parameter FS_ONE  = 3;  // One
reg [1:0] flag_src;

// ALU operation
reg  [2:0] alu_op;
reg        alu_not_left;
reg        alu_not_right;
reg        alu_not_out;
wire [7:0] alu_res;

// State
parameter SS_NEXT   = 0;
parameter SS_INCR   = 1;
parameter SS_BRANCH = 2;
parameter SS_HOLD   = 3;

reg  [4:0]  state;
reg  [1:0]  state_sel;
wire [4:0]  next_state;

// Autocarry
parameter   AC_NONE = 0;
parameter   AC_I    = 1;
parameter   AC_S    = 2;
parameter   AC_IP   = 3; 
reg [1:0]   ac_sel;
reg [1:0]   ac_which;
reg         ac_subtract;
wire        autocarry_next;
reg         autocarry;
reg         autocarry_subtract;

// Memory access
assign addr_o = { right, left };

// Result
assign res = rd_o ? data_i : alu_res;

// Autocarry
assign autocarry_next = (op_cf != ac_subtract) && (ac_sel != AC_NONE);

always @(posedge clk_i) begin
    ac_which <= ac_sel;
    autocarry_subtract <= ac_subtract;
    autocarry <= autocarry_next;
end

// Previous instruction flag updates
always @(posedge clk_i) begin
    prev_zf <= op_zf;
    prev_cf <= op_cf;
    prev_of <= op_of;
    prev_sf <= op_sf;
    prev_pf <= op_pf;
end

// State movement
always @(posedge clk_i) begin
    case(state_sel)
        SS_NEXT:        state <= 0;
        SS_INCR:        state <= state + 1;
        SS_BRANCH:      state <= 5;
    endcase
end

// Flag source selection
always @* begin
    case(flag_src)
        FS_PREV: alu_cf <= prev_cf;
        FS_PG:   alu_cf <= pg_cf;
        FS_ZERO: alu_cf <= 0;
        FS_ONE:  alu_cf <= 1;
    endcase
end

// Input bus data selection
always @* begin
    case(left_sel)
        IN_ZERO:        left <= 0;
        IN_BIT:         left <= 1 << ir[2:0];
        IN_A:           left <= ra;
        IN_B:           left <= rb;
        IN_I:           left <= ix[7:0];
        IN_S:           left <= sp[7:0];
        IN_CC:          left <= { 2'b00, cc };
        IN_IP:          left <= ip[7:0];
        IN_IRLIT:       left <= { 4'b000, ir[5:1] };
    endcase

    case(right_sel)
        IN_ZERO:        right <= 0;
        IN_BIT:         right <= 1 << ir[2:0];
        IN_A:           right <= ra;
        IN_B:           right <= rb;
        IN_I:           right <= ix[15:8];
        IN_S:           right <= sp[15:8];
        IN_CC:          right <= { 2'b00, cc };
        IN_IP:          right <= ip[18:8];
        IN_IRLIT:       right <= { 4'b000, ir[5:1] };
    endcase

    case(data_sel)
        DATA_A:         data_o <= ra;
        DATA_B:         data_o <= rb;
        DATA_IL:        data_o <= ix[7:0];
        DATA_IH:        data_o <= ix[15:8];
        DATA_IPL:       data_o <= ip[7:0];
        DATA_IPH:       data_o <= ip[15:8];
        DATA_CC:        data_o <= { 2'b00, cc };
    endcase
end

// Writeback selection
always @(posedge clk_i) begin
    case(write_sel)
        WR_IGNORE:                     ;
        WR_A:           ra       <= res;
        WR_B:           rb       <= res;
        WR_IL:          ix[7:0]  <= res;
        WR_SL:          sp[7:0]  <= res;
        WR_IH:          ix[15:8] <= res;
        WR_SH:          sp[15:8] <= res;
        WR_IPH:         ip[15:8] <= res;
        WR_IR:          ir       <= res;
    endcase

    case(write_ipl)
        WRIPL_DONT:     ;
        WRIPL_IR:       ip[7:0] <= ir;
        WRIPL_ALU:      ip[7:0] <= alu_res;
    endcase

    case(cc_sel)
        CC_IGNORE:      ;
        CC_RES:         cc <= res;
        CC_ZSP:         cc <= { pg_if, op_pf, op_sf, pg_of, pg_cf, op_zf };
        CC_ALL:         cc <= { pg_if, op_pf, op_sf, op_of, op_cf, op_zf };
    endcase
end

// Flags
assign pg_zf = cc[0];
assign pg_cf = cc[1];
assign pg_of = cc[2];
assign pg_sf = cc[3];
assign pg_pf = cc[4];
assign pg_if = cc[5];

// Conditional branches
assign cond = ir[3:0];
always @* begin
    case(cond)
        CN_ALWAYS:      cond_true <= 1;
        CN_O:           cond_true <= pg_of;
        CN_Z:           cond_true <= pg_zf;
        CN_NZ:          cond_true <= !pg_zf;
        CN_C:           cond_true <= pg_cf;
        CN_NC:          cond_true <= !pg_cf;
        CN_LEU:         cond_true <= pg_cf || pg_zf;
        CN_GU:          cond_true <= !(pg_cf || pg_zf);
        CN_LS:          cond_true <= pg_sf != pg_of;
        CN_GES:         cond_true <= pg_sf == pg_of;
        CN_LES:         cond_true <= pg_zf || (pg_sf != pg_of);
        CN_GS:          cond_true <= !(pg_zf || (pg_sf != pg_of));
        CN_S:           cond_true <= pg_sf;
        CN_NS:          cond_true <= !pg_sf;
        CN_P:           cond_true <= pg_pf;
        CN_NP:          cond_true <= !pg_pf;
    endcase
end


always @* begin
    // Instruction decode
    alu_op        <= alu.ALU_LEFT;
    alu_not_left  <= 0;
    alu_not_right <= 0;
    alu_not_out   <= 0;
    flag_src      <= FS_ZERO;
    rd_o          <= 0;
    wr_o          <= 0;
    left_sel      <= IN_ZERO;
    right_sel     <= IN_ZERO;
    data_sel      <= DATA_A;
    write_sel     <= WR_IGNORE;
    write_ipl     <= WRIPL_DONT;
    state_sel     <= SS_NEXT;
    cc_sel        <= CC_IGNORE;
    ac_sel        <= AC_NONE;
    ac_subtract   <= 0;

    if(rst_i) begin
        ip        <= 16'h0000;
        sp        <= 16'h0000;
        ix        <= 16'h0000;
        ra        <= 8'h00;
        rb        <= 8'h00;
        ir        <= 8'h00;
        cc        <= 6'h00;
        state_sel <= SS_NEXT;
    end else if(autocarry) begin
        alu_op          <= alu.ALU_ADD;
        left_sel        <= IN_ZERO;
        flag_src        <= FS_PREV;
        alu_not_left    <= autocarry_subtract;
        case(ac_which)
            AC_I:  right_sel <= IN_I;
            AC_S:  right_sel <= IN_S;
            AC_IP: right_sel <= IN_IP;
        endcase

        case(ac_which)
            AC_I:  write_sel <= WR_IH;
            AC_S:  write_sel <= WR_SH;
            AC_IP: write_sel <= WR_IPH;
        endcase

        state_sel <= SS_HOLD;
    end else if(state == 0) begin
        // Fetch
        left_sel  <= IN_IP;
        right_sel <= IN_IP;
        write_ipl <= WRIPL_ALU;
        write_sel <= WR_IR;
        rd_o      <= 1;
        alu_op    <= alu.ALU_ADDL;
        flag_src  <= FS_ONE;
        state_sel <= SS_INCR;
        ac_sel    <= AC_IP;
    
    end else if(state == 1) begin
        // Execute
        if(ir[7:3] == 5'b00000) begin
            // 0000 0xyz ADDxyz
            alu_op              <= alu.ALU_ADD;
            flag_src            <= FS_ZERO;
            left_sel            <= IN_ABX | ir[2];
            right_sel           <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:3] == 5'b00001) begin
            // 0000 1xyz SUBxyz
            alu_op              <= alu.ALU_ADD;
            alu_not_right       <= 1;
            flag_src            <= FS_ONE;
            left_sel            <= IN_ABX | ir[2];
            right_sel           <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:3] == 5'b00010) begin
            // 0001 0xyz ADCxyz
            alu_op              <= alu.ALU_ADD;
            flag_src            <= FS_PG;
            left_sel            <= IN_ABX | ir[2];
            right_sel           <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:3] == 5'b00011) begin
            // 0001 0xyz SBCxyz
            alu_op              <= alu.ALU_ADD;
            alu_not_right       <= 1;
            flag_src            <= FS_PG;
            left_sel            <= IN_ABX | ir[2];
            right_sel           <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:1] == 7'b0010000) begin
            // 0010 000z ANDz
            alu_op              <= alu.ALU_AND;
            left_sel            <= IN_A;
            right_sel           <= IN_B;
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ZSP;
        end else if(ir[7:1] == 7'b0010001) begin
            // 0010 000z ORz
            alu_op              <= alu.ALU_AND;
            alu_not_left        <= 1;
            alu_not_right       <= 1;
            alu_not_out         <= 1;
            left_sel            <= IN_A;
            right_sel           <= IN_B;
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ZSP;
        end else if(ir[7:1] == 7'b0010010) begin
            // 0010 010z XOR
            alu_op              <= alu.ALU_XOR;
            left_sel            <= IN_A;
            right_sel           <= IN_B;
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ZSP;
        end else if(ir[7:1] == 7'b0010011) begin
            // 0010 011z XNORz
            alu_op              <= alu.ALU_XOR;
            alu_not_out         <= 1;
            left_sel            <= IN_A;
            right_sel           <= IN_B;
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ZSP;
        end else if(ir[7:2] == 7'b001010) begin
            // 0010 10xz NOTxz
            alu_op              <= alu.ALU_LEFT;
            alu_not_out         <= 1;
            left_sel            <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ZSP;
        end else if(ir[7:2] == 7'b001011) begin
            // 0010 11xz ADCxz
            alu_op              <= alu.ALU_ADD;
            alu_not_out         <= 1;
            flag_src            <= FS_PG;
            left_sel            <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:4] == 4'b0011) begin
            // 0011 sbbb CLs/STx
            alu_op              <= alu.ALU_AND;
            alu_not_left        <= ir[3];
            alu_not_right       <= ir[3];
            alu_not_out         <= ir[3];
            left_sel            <= IN_CC;
            right_sel           <= IN_BIT;
            cc_sel              <= CC_RES;
        end else if(ir[7:2] == 6'b010000) begin
            // 0100 00xz MOVxz
            left_sel            <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
        end else if(ir[7:2] == 6'b010001) begin
            // 0100 01xz MOVpr
            alu_op              <= alu.ALU_LEFT;
            left_sel            <= IN_ISX | ir[1];
            write_sel           <= WR_ISLX | ir[0];
            state_sel           <= SS_INCR;
        end else if(ir[7:1] == 7'b0100100) begin
            // 0100 100z MOVCCz
            left_sel            <= IN_CC;
            write_sel           <= WR_ABX | ir[0];
        end else if(ir[7:1] == 7'b0100101) begin
            // 0100 101x MOVxCC
            left_sel            <= IN_ABX | ir[0];
            cc_sel              <= CC_RES;
        end else if(ir[7:2] == 6'b010011) begin
            // 0100 11xz SHRxz
            alu_op              <= alu.ALU_SHRL;
            left_sel            <= IN_ABX | ir[1];
            write_sel           <= WR_ABX | ir[0];
            cc_sel              <= CC_ALL;
        end else if(ir[7:3] == 5'b01010) begin
            // 0101 0spz MOVspz
            alu_op              <= alu.ALU_LRX | ir[2];
            left_sel            <= IN_ISX | ir[1];
            right_sel           <= IN_ISX | ir[1];
            write_sel           <= WR_ABX | ir[0];
        end else if(ir[7:3] == 5'b01011) begin
            // 0101 1spx MOVxsp
            alu_op              <= alu.ALU_LEFT;
            left_sel            <= IN_ABX | ir[0];
            if(ir[2])
                write_sel       <= WR_ISHX | ir[1];
            else
                write_sel       <= WR_ISLX | ir[1];
        end else if(ir[7:4] == 4'b0110) begin
            // 0110 cccc Jcc.L
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_IP;
            right_sel           <= IN_IP;
            flag_src            <= FS_ONE;
            write_ipl           <= WRIPL_ALU;
            rd_o                <= 1;
            ac_sel              <= AC_IP;
            if(cond_true) begin
                write_sel       <= WR_IR;
                state_sel       <= SS_BRANCH;
            end else begin
                state_sel       <= SS_INCR; 
            end
        end else if(ir[7:4] == 4'b0111) begin
            // 0111 cccc Jcc.I
            alu_op              <= alu.ALU_LEFT;
            left_sel            <= IN_A;
            if(cond_true) begin
                write_sel       <= WR_IPH;
                state_sel       <= SS_INCR;
            end
        end else if(ir[7:5] == 3'b100) begin
            // 100i iiiz LDIz.I
            left_sel            <= IN_IRLIT;
            write_sel           <= WR_ABX | ir[0];
        end else if(ir[7:1] == 7'b1010000) begin
            // 1010 000z LDIz.L
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_IP;
            right_sel           <= IN_IP;
            flag_src            <= FS_ONE;
            write_sel           <= WR_ABX | ir[0];
            write_ipl           <= WRIPL_ALU;
            rd_o                <= 1;
            ac_sel              <= AC_IP;
        end else if(ir[7:1] == 7'b1010001) begin
            // 1010 001r LDIr.L
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_IP;
            right_sel           <= IN_IP;
            flag_src            <= FS_ONE;
            write_sel           <= WR_ISLX | ir[0];
            write_ipl           <= WRIPL_ALU;
            rd_o                <= 1;
            ac_sel              <= AC_IP;
            state_sel           <= SS_INCR;
        end else if(ir[7:1] == 7'b1010010) begin
            //1010 010r MOVABr
            left_sel            <= IN_A;
            write_sel           <= WR_ISHX | ir[0];
            state_sel           <= SS_INCR;
        end else if(ir[7:1] == 7'b1010011) begin
            // 1010 011x TESTx
            left_sel            <= IN_A;
            cc_sel              <= CC_ZSP;
        end else if(ir[7:1] == 7'b1010011) begin
            // 1010 1000 CMP
            alu_op              <= alu.ALU_ADD;
            alu_not_right       <= 1;
            flag_src            <= FS_ONE;
            left_sel            <= IN_A;
            right_sel           <= IN_B;
            cc_sel              <= CC_ALL;
        end else if(ir[7:1] == 7'b1100000) begin
            // 1100 000z LDz
            left_sel            <= IN_I;
            right_sel           <= IN_I;
            write_sel           <= IN_ABX | ir[0];
            rd_o                <= 1;
        end else if(ir[7:1] == 7'b1100001) begin
            // 1100 001x STx
            left_sel            <= IN_I;
            right_sel           <= IN_I;
            data_sel            <= DATA_ABX | ir[0];
            wr_o                <= 1;
        end else if(ir[7:0] == 8'b11000110) begin
            // 1100 0110 RET
            left_sel            <= IN_I;
            write_ipl           <= WRIPL_ALU;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11000111) begin
            // 1100 0111 IRET
            error("IRET unsupported");
        end else if(ir[7:0] == 8'b11001000) begin
            // 1100 1000 CALL.I 
            left_sel            <= IN_IP;
            write_sel           <= WR_IL;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001001) begin
            // 1100 1001 CALL.L
            left_sel            <= IN_IP;
            right_sel           <= IN_BIT;
            alu_op              <= alu.ALU_ADD;
            write_sel           <= WR_IL;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001010) begin
            // 1100 1010 PUSHI
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_S;
            right_sel           <= IN_S;
            write_sel           <= WR_SL;
            flag_src            <= FS_ONE;
            alu_not_right       <= 1;
            data_sel            <= DATA_IH;

            ac_sel              <= AC_S;
            ac_subtract         <= 1;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001011) begin
            // 1100 1011 POPI
            error("POPI unsupported");
        end else if(ir[7:3] == 5'b11100) begin
            //1110 0drz LDrzd
            error("LDrzd unsupported");
        end else if(ir[7:3] == 5'b11101) begin
            //1110 1drz LDrdz
            error("LDrdz unsupported");
        end else if(ir[7:3] == 5'b11110) begin
            //1111 0drx STxrd
            error("LDxrd unsupported");
        end else if(ir[7:3] == 5'b11111) begin
            //1111 1drx STxdr
            error("LDxdr unsupported");
        end else begin
            $display("Invalid instruction");
            $finish;
        end
    end else if(state == 2) begin
        if(ir[7:2] == 6'b010001) begin
            // 0100 01xz MOVpr
            alu_op              <= alu.ALU_RIGHT;
            right_sel           <= IN_ISX | ir[1];
            write_sel           <= WR_ISHX | ir[0];
        end else if(ir[7:4] == 4'b0110) begin
            // 0110 cccc Jcc.L
            alu_op              <= alu.ALU_ADDL;
            flag_src            <= FS_ONE;
            left_sel            <= IN_IP;
            right_sel           <= IN_ZERO;
            write_ipl           <= WRIPL_ALU;
            ac_sel              <= AC_IP;
        end else if(ir[7:4] == 4'b0111) begin
            // 0111 cccc Jcc.I
            alu_op              <= alu.ALU_RIGHT;
            right_sel           <= IN_B;
            write_ipl           <= WRIPL_ALU;
        end else if(ir[7:1] == 7'b1010001) begin
            // 1010 001r LDIr.L
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_IP;
            right_sel           <= IN_IP;
            flag_src            <= FS_ONE;
            write_sel           <= WR_ISHX | ir[0];
            write_ipl           <= WRIPL_ALU;
            rd_o                <= 1;
            ac_sel              <= AC_IP;
        end else if(ir[7:1] == 7'b1010010) begin
            //1010 010r MOVABr
            alu_op              <= alu.ALU_RIGHT;
            right_sel           <= IN_B;
            write_sel           <= WR_ISLX | ir[0];
        end else if(ir[7:0] == 8'b11000110) begin
            // 1100 0110 RET
            alu_op              <= alu.ALU_RIGHT;
            right_sel           <= IN_I;
            write_sel           <= WR_IPH;
        end else if(ir[7:0] == 8'b11001000) begin
            // 1100 1000 CALL.I 
            alu_op              <= alu.ALU_RIGHT;
            right_sel           <= IN_IP;
            write_sel           <= WR_IH;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001001) begin
            // 1100 1001 CALL.L
            left_sel            <= IN_ZERO;
            right_sel           <= IN_IP;
            flag_src            <= FS_PREV;
            alu_op              <= alu.ALU_ADD;
            write_sel           <= WR_IH;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001010) begin
            // 1100 1010 PUSHI
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_S;
            right_sel           <= IN_S;
            write_sel           <= WR_SL;
            flag_src            <= FS_ONE;
            alu_not_right       <= 1;
            data_sel            <= DATA_IL;

            ac_sel              <= AC_S;
            ac_subtract         <= 1;
        end else begin
            $display("Invalid instruction for S2");
            $finish;
        end
    end else if(state == 3) begin
        if(ir[7:0] == 8'b11001000) begin
            // 1100 1000 CALL.I 
            alu_op              <= alu.ALU_LEFT;
            left_sel            <= IN_A;
            write_sel           <= WR_IPH;
            state_sel           <= SS_INCR;
        end else if(ir[7:0] == 8'b11001001) begin
            // 1100 1001 CALL.L
            alu_op              <= alu.ALU_ADDL;
            left_sel            <= IN_IP;
            right_sel           <= IN_IP;
            flag_src            <= FS_ONE;
            write_ipl           <= WRIPL_ALU;
            write_sel           <= WR_IR;
            state_sel           <= SS_BRANCH;
            rd_o                <= 1;
            ac_sel              <= AC_IP;
        end else begin
            $display("Invalid instruction for S3");
            $finish;
        end
    end else if(state == 4) begin
        if(ir[7:0] == 8'b11001000) begin
            // 1100 1000 CALL.I 
            alu_op              <= alu.ALU_LEFT;
            left_sel            <= IN_B;
            write_ipl           <= WRIPL_ALU;
        end else begin
            $display("Invalid instruction for S4");
            $finish;
        end
    end else if(state == 5) begin
        // Branch
        alu_op                  <= alu.ALU_ADDL;
        left_sel                <= IN_IP;
        right_sel               <= IN_IP;
        flag_src                <= FS_ONE;
        write_ipl               <= WRIPL_IR;
        write_sel               <= WR_IPH;
        rd_o                    <= 1;
        ac_sel                  <= AC_IP;   
    end else begin
        $display("Invalid state");
        $finish;
    end
end

o8_alu alu(
    .op(alu_op),

    .left(left),
    .right(right),
    .result(alu_res),

    .cf_in(alu_cf),
    .not_left(alu_not_left),
    .not_right(alu_not_right),
    .not_result(alu_not_out),

    .zf_out(op_zf),
    .cf_out(op_cf),
    .of_out(op_of),
    .sf_out(op_sf),
    .pf_out(op_pf)
);

endmodule