`timescale 1ns/1ps
`define WIDTH 32
`define DEPTH 16
`define ADDR_WIDTH 4
`define WRITE_HALF_PERIOD 5
`define READ_HALF_PERIOD 5



module async_fifo_tb;
    logic async_rst;
    logic wr_clk;
    logic wr_en;
    logic [`WIDTH-1:0] wr_data;
    logic full;

    logic rd_clk;
    logic rd_en;
    logic empty;
    logic [`WIDTH-1:0] rd_data;
    logic rd_valid;

    logic did_write;
    logic did_read;
    logic [`WIDTH-1:0] read_data;

    clocking cb_wr @(posedge wr_clk);
        default input #0 output #1ns;   // sample at edge, drive 1ns after
        output wr_en, wr_data;
        input full;
    endclocking

    clocking cb_rd @(posedge rd_clk);
        default input #0 output #1ns;   // sample at edge, drive 1ns after
        output rd_en;
        input  empty, rd_valid, rd_data;
    endclocking


    async_fifo dut (
        .async_rst(async_rst),
        .wr_clk(wr_clk),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .rd_clk(rd_clk),
        .rd_en(rd_en),
        .empty(empty),
        .rd_data(rd_data),
        .rd_valid(rd_valid)
    );

    task automatic set_wr_clk(input integer half_period_ns);
        forever begin
            wr_clk = 1'b0;  #half_period_ns;
            wr_clk = 1'b1;  #half_period_ns;
        end
    endtask

    task automatic set_rd_clk(input integer half_period_ns);
        forever begin
            rd_clk = 1'b0;  #half_period_ns;
            rd_clk = 1'b1;  #half_period_ns;
        end
    endtask

    task automatic reset();
        async_rst = 1;
        #50;
        async_rst = 0;
    endtask

    task automatic write(input logic [`WIDTH-1:0] data, output logic did_write);
        @cb_wr;
        if (!cb_wr.full) begin
            cb_wr.wr_en <= 1'b1;
            cb_wr.wr_data <= data;
            did_write = 1'b1;
        end else begin
            cb_wr.wr_en <= 1'b0;
            did_write = 1'b0;
        end
        @cb_wr;
        cb_wr.wr_en <= 1'b0;
    endtask

    task automatic read(output logic [`WIDTH-1:0] data, output logic did_read);
        did_read = 1'b0;
        data = '0;

        // Request read (if not empty) after sampling empty at the edge
        @cb_rd;
        if (!cb_rd.empty) begin
            cb_rd.rd_en <= 1'b1;
            did_read = 1'b1;
        end else begin
            cb_rd.rd_en <= 1'b0;
            did_read = 1'b0;
        end

        @cb_rd;
        cb_rd.rd_en <= 1'b0;

        // If we requested a read, wait until rd_valid goes high on a clock edge
        if (did_read) begin
            while (!cb_rd.rd_valid) begin
                @cb_rd;
            end
            data = cb_rd.rd_data;
        end
    endtask


    initial begin
        async_rst = 1'b0;
        wr_clk = 1'b0;
        rd_clk = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        wr_data = '0;
    end

    initial begin
        set_wr_clk(`WRITE_HALF_PERIOD);
    end

    initial begin
        set_rd_clk(`READ_HALF_PERIOD);
    end

    initial begin
        reset();
        write(5, did_write);
        $display("[INFO]: %0d", did_write);
        #50;
        read(read_data, did_read);
        $display("[INFO]: %0d", did_read);
        $finish;
    end
endmodule