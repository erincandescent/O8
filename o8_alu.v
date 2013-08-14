module o8_alu(
    op,

    left,
    right,
    result,

    cf_in,
    not_left,
    not_right,
    not_result,

    zf_out,
    cf_out,
    of_out,
    sf_out,
    pf_out,
);

parameter ALU_LEFT  = 0;   // Pass left
parameter ALU_RIGHT = 1;   // Pass right
parameter ALU_ADD   = 2;   // Add
parameter ALU_AND   = 3;   // And
parameter ALU_XOR   = 4;   // Exclusive or
parameter ALU_SHRL  = 5;   // Shift right value on left bus
parameter ALU_ADDL  = 6;

parameter ALU_LRX   = ALU_LEFT;

input  wire [2:0] op;

input  wire [7:0] left;
input  wire [7:0] right;
output wire [7:0] result;

input wire cf_in, not_left, not_right, not_result;

output wire zf_out, cf_out, of_out, sf_out, pf_out;

wire [8:0] lx, rx;
reg  [8:0] rsx;

assign lx       = { 1'b0, (not_left  ? ~left  : left)  };
assign rx       = { 1'b0, (not_right ? ~right : right) };
assign sxcarry  = { 8'b0, cf_in };
assign negone   = { 1'b0, {8{alu_not_right}} };
assign result   = not_result ? ~rsx : rsx;

always @* begin
    case(op)
        ALU_LEFT:       rsx <= lx;
        ALU_RIGHT:      rsx <= rx;
        ALU_ADD:        rsx <= lx + rx + { 8'b0, cf_in };
        ALU_AND:        rsx <= lx & rx;
        ALU_XOR:        rsx <= lx ^ rx;
        ALU_SHRL:       rsx <= lx >> 1;
        ALU_ADDL:       rsx <= lx + negone + sxcarry;
    endcase
end

assign cf_out = rsx[8];
assign zf_out = !(|result);
assign of_out = result[7] != left[7] && left[7] == right[7];
assign sf_out = result[7];
assign pf_out = ^result[7];

endmodule