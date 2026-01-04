`define WIDTH 32
`define DEPTH 16
`define ADDR_WIDTH 4

module write_controller (
    input logic wr_clk,
    input logic async_rst,
    input logic wr_en,

    input logic [`ADDR_WIDTH:0] rptr_gray_sync,
    
    output logic full_q, // Synchronous
    output logic [`ADDR_WIDTH-1:0] wr_addr, // Combinational (latched by fifo module)
    output logic wr_fire, // Combinational (latched by fifo module)
    output logic [`ADDR_WIDTH:0] wptr_gray // Synchronous
);

    logic full_d;
    logic [`ADDR_WIDTH:0] wptr_bin;
    logic [`ADDR_WIDTH:0] wptr_next_bin;
    logic [`ADDR_WIDTH:0] wptr_next_gray;
    logic [`ADDR_WIDTH:0] rptr_gray_sync_inv;

    always_comb begin
        wr_fire = wr_en && !full_q;
        wr_addr = wptr_bin[`ADDR_WIDTH-1:0];

        wptr_next_bin = wptr_bin + wr_fire;
        wptr_next_gray = (wptr_next_bin >> 1) ^ wptr_next_bin;

        rptr_gray_sync_inv = {~rptr_gray_sync[`ADDR_WIDTH:`ADDR_WIDTH-1], rptr_gray_sync[`ADDR_WIDTH-2:0]};

        full_d = (wptr_next_gray == rptr_gray_sync_inv);
    end

    always_ff @(posedge wr_clk) begin
        if (async_rst) begin
            wptr_bin <= '0;
            wptr_gray <= '0;
            full_q <= 1'b0;
        end else begin
            wptr_bin <= wptr_next_bin;
            wptr_gray <= wptr_next_gray;
            full_q <= full_d;
        end
    endå
endmodule

module read_controller (
    input logic rd_clk,
    input logic async_rst,
    input logic rd_en,

    input logic [`ADDR_WIDTH:0] wptr_gray_sync,

    output logic empty_q, // registered
    output logic [`ADDR_WIDTH-1:0] rd_addr, // combinational
    output logic rd_fire, // combinational
    output logic [`ADDR_WIDTH:0] rptr_gray // registered
);
    logic empty_d;
    logic [`ADDR_WIDTH:0] rptr_bin;
    logic [`ADDR_WIDTH:0] rptr_next_bin;
    logic [`ADDR_WIDTH:0] rptr_next_gray;

    always_comb begin
        rd_fire = rd_en && !empty_q;
        rd_addr = rptr_bin[`ADDR_WIDTH-1:0];

        rptr_next_bin  = rptr_bin + rd_fire;
        rptr_next_gray = (rptr_next_bin >> 1) ^ rptr_next_bin;

        empty_d = (rptr_next_gray == wptr_gray_sync);
    end

    always_ff @(posedge rd_clk) begin
        if (async_rst) begin
            rptr_bin <= '0;
            rptr_gray <= '0;
            empty_q  <= 1'b1; 
        end else begin
            rptr_bin <= rptr_next_bin;
            rptr_gray <= rptr_next_gray;
            empty_q <= empty_d;
        end
    end
endmodule


module fifo (
    input logic async_rst,

    input logic wr_clk,
    input logic wr_fire,
    input logic [`ADDR_WIDTH-1:0] wr_addr,
    input logic [`WIDTH-1:0] wr_data,

    input logic rd_clk,
    input logic rd_fire,
    input logic [`ADDR_WIDTH-1:0] rd_addr,
    output logic [`WIDTH-1:0] rd_data,
    output logic rd_valid
);
    logic [`WIDTH-1:0] fifo_regs [`DEPTH-1:0];

    always_ff @(posedge wr_clk) begin
        if (wr_fire) begin
            fifo_regs[wr_addr] <= wr_data;
        end
    end

    always_ff @(posedge rd_clk) begin
        if (async_rst) begin
            rd_valid <= 0;
            rd_data <= '0;
        end else begin
            rd_valid <= rd_fire;
            if (rd_fire) begin
                rd_data <= fifo_regs[rd_addr];
            end
        end
    end
endmodule

module synchronizers (
    input logic async_rst,
    input logic wr_clk,
    input logic rd_clk,

    input logic [`ADDR_WIDTH:0] wptr_gray,
    output logic [`ADDR_WIDTH:0] wptr_gray_sync,

    input logic [`ADDR_WIDTH:0] rptr_gray,
    output logic [`ADDR_WIDTH:0] rptr_gray_sync
);
    logic [`ADDR_WIDTH:0] wptr_gray_1;
    always_ff @(posedge rd_clk) begin
        if (async_rst) begin
            wptr_gray_1 <= '0;
            wptr_gray_sync <= '0;
        end else begin
            wptr_gray_1 <= wptr_gray;
            wptr_gray_sync <= wptr_gray_1;
        end
    end

    logic [`ADDR_WIDTH:0] rptr_gray_1;
    always_ff @(posedge wr_clk) begin
        if (async_rst) begin
            rptr_gray_1 <= '0;
            rptr_gray_sync <= '0;
        end else begin
            rptr_gray_1 <= rptr_gray;
            rptr_gray_sync <= rptr_gray_1;
        end
    end
endmodule

module async_fifo (
    input  logic async_rst,

    input  logic wr_clk,
    input  logic wr_en,
    input  logic [`WIDTH-1:0] wr_data,
    output logic full,

    input  logic rd_clk,
    input  logic rd_en,
    output logic empty,
    output logic [`WIDTH-1:0] rd_data,
    output logic rd_valid
);
    // Pointers (Gray)
    logic [`ADDR_WIDTH:0] wptr_gray;
    logic [`ADDR_WIDTH:0] rptr_gray;

    // Synchronized pointers
    logic [`ADDR_WIDTH:0] wptr_gray_sync;
    logic [`ADDR_WIDTH:0] rptr_gray_sync;

    // Local control
    logic [`ADDR_WIDTH-1:0] wr_addr;
    logic [`ADDR_WIDTH-1:0] rd_addr;
    logic wr_fire;
    logic rd_fire;

    logic full_q;
    logic empty_q;

    // Sync pointers across domains
    synchronizers u_sync (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .wptr_gray(wptr_gray),
        .wptr_gray_sync(wptr_gray_sync),
        .rptr_gray(rptr_gray),
        .rptr_gray_sync(rptr_gray_sync)
    );

    // Write side controller
    write_controller u_wr (
        .wr_clk(wr_clk),
        .async_rst(async_rst),
        .wr_en(wr_en),
        .rptr_gray_sync(rptr_gray_sync),
        .full_q(full_q),
        .wr_addr(wr_addr),
        .wr_fire(wr_fire),
        .wptr_gray(wptr_gray)
    );

    // Read side controller
    read_controller u_rd (
        .rd_clk(rd_clk),
        .async_rst(async_rst),
        .rd_en(rd_en),
        .wptr_gray_sync(wptr_gray_sync),
        .empty_q(empty_q),
        .rd_addr(rd_addr),
        .rd_fire(rd_fire),
        .rptr_gray(rptr_gray)
    );

    // Memory
    fifo u_mem (
        .async_rst(async_rst),
        .wr_clk(wr_clk),
        .wr_fire(wr_fire),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk(rd_clk),
        .rd_fire(rd_fire),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid)
    );

    // Top outputs
    assign full  = full_q;
    assign empty = empty_q;

endmodule
