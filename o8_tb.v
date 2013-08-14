module o8_tb;
    reg clk, rst, int, ack, err;
    wire [15:0] addr;
    reg  [ 7:0] data_rd;
    wire [ 7:0] data_wr;
    wire rd, wr;
    
    reg [7:0] ram [0:65535];

    initial begin
        $display("time\tc r addr di do rd wr IP   IR       A  B  IX   SP   IPSOCZ | St AC Res AR l r R T");
        $monitor("%h\t%b %b %h %h %h %b  %b  %h %b %h %h %h %h %b | %h %b%b %h %h %h %h %h %b", 
            $time, clk, rst, addr, data_rd, data_wr, rd, wr, cpu.ip, cpu.ir, cpu.ra, cpu.rb, cpu.ix, cpu.sp, cpu.cc, 
                cpu.state, cpu.autocarry, cpu.autocarry_subtract, cpu.res, cpu.alu_res, cpu.left_sel, cpu.right_sel, cpu.write_sel, cpu.cond_true);

        clk = 0;
        rst = 1;
        ram[0]  <= 8'b100_0011_0; // LDIA 3
        ram[1]  <= 8'b100_0010_1; // LDIB 2
        ram[2]  <= 8'b00000_010;  // ADDABA
        ram[3]  <= 8'b00001_100;  // SUBBAA
        ram[4]  <= 8'b100_0001_0; // LDIA 1
        ram[5]  <= 8'b100_1000_1; // LDIB 8
        ram[6]  <= 8'b0010_001_0; // ORA
        ram[7]  <= 8'b00000_000;  // SHLAA
        ram[8]  <= 8'b100_0010_1; // LDIB 2
        ram[9]  <= 8'b0010_000_0; // ANDA
        ram[10] <= 8'b0010_010_0; // XORA
        ram[11] <= 8'b0010_10_00; // NOTAA
        ram[12] <= 8'b0011_1_101; // STI
        ram[13] <= 8'b0100_00_01; // MOVAB
        ram[14] <= 8'b0101_1_000; // MOVAIL
        ram[15] <= 8'b0101_1_101; // MOVBIH
        ram[16] <= 8'b0100_01_01; // MOVIS
        ram[17] <= 8'b1100_000_0; // LDA
        ram[18] <= 8'b0100_11_01; // SHRAB
        ram[19] <= 8'b1100_001_1; // STB
        ram[20] <= 8'b1100_000_0; // LDA
        ram[21] <= 8'b1010_010_0; // MOVABI
        ram[22] <= 8'b1100_1000;  // CALLI
        ram['h1111] <= 8'b1100_0110; // RET
        ram[23] <= 8'b1100_1001;  // CALL.L 0xDFFF
        ram[24] <= 8'hFF;
        ram[25] <= 8'hDF;
        ram['hDFFF] <= 8'b1100_1001;  // CALL.L 26
        ram['hE000] <= 26;
        ram['hE001] <= 0;
        ram[26] <= 8'b0110_0000;  // JMPL 0x22FF
        ram[27] <= 8'hFF;
        ram[28] <= 8'h22;

        ram['h22FF] <= 8'b0110_0000;  // JMPL 0x23FE
        ram['h2300] <= 8'hFE;
        ram['h2301] <= 8'h23;

        ram['h23FE] <= 8'b0110_0000; // JMPL 0x24FE
        ram['h23FF] <= 8'hFE;
        ram['h2400] <= 8'h24;

        ram['h24FE] <= 8'b0110_0010; // JZ 0x25FE (not taken)
        ram['h24FF] <= 8'hFE;
        ram['h2500] <= 8'h25;
        ram['h2501] <= 8'b0110_0011; // JNZ 0x25FE (taken)
        ram['h2502] <= 8'hFE;
        ram['h2503] <= 8'h25;

        ram['h25FE] <= 8'b1010_000_0; // LDIA 0x27
        ram['h25FF] <= 8'h27;
        ram['h2600] <= 8'b1010_000_1; // LDIB 0x00
        ram['h2601] <= 8'h00;
        ram['h2602] <= 8'b0111_0011; // JNZAB

        ram['h2700] <= 8'b1010_0010; // LDII 0xFFFF
        ram['h2701] <= 8'hFF;
        ram['h2702] <= 8'hFF;
        ram['h2703] <= 8'b1100_000_0; // LDA
        ram['h2704] <= 8'b0110_0000; // JMP 0x0000
        ram['h2705] <= 8'h00;
        ram['h2706] <= 8'h00;
        

        ram[65535] <= 8'h22;

        #3 rst = 0;

        #200 $finish();
    end

    always begin
        #1 clk = ~clk;
    end

    always @(negedge clk) begin
        data_rd = ram[addr];
        if(wr) begin
            ram[addr] = data_wr;
        end

        ack = rd | wr;
        err = 0;
    end

    o8_cpu cpu(
        .clk_i(clk),
        .rst_i(rst),
        .int_i(int),

        .addr_o(addr),
        .data_i(data_rd),
        .data_o(data_wr),

        .rd_o(rd),
        .wr_o(wr),
        .ack_i(ack),
        .err_i(err)
    );
endmodule