`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ = 25_000_000,
    parameter integer BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst,
    input wire rx,

    output reg [7:0] rx_data,
    output reg rx_valid
);

    localparam integer BIT_CYCLES = CLK_FREQ / BAUD_RATE;

    reg rx_meta;
    reg rx_sync;

    // Synchronize the asynchronous UART input.
    always @(posedge clk) begin
        if(rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    localparam integer IDLE = 2'd0;
    localparam integer START = 2'd1;
    localparam integer DATA = 2'd2;
    localparam integer STOP = 2'd3;

    reg [1:0] state = IDLE;
    reg [1:0] next_state = IDLE;
    reg [2:0] bit_index = 3'd0;
    reg [7:0] clk_cnt;
    reg [7:0] rx_shift;

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            clk_cnt <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    clk_cnt <= 8'd0;
                end

                START: begin
                    if(clk_cnt == BIT_CYCLES / 2 - 1) begin
                        clk_cnt <= 8'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA, STOP: begin
                    if (clk_cnt == BIT_CYCLES - 1) begin
                        clk_cnt <= 8'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: clk_cnt <= 8'd0;
            endcase
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (!rx_sync) begin
                    next_state = START;
                end 
            end

            START: begin
                if (clk_cnt == BIT_CYCLES / 2 - 1) begin
                    if (!rx_sync) begin
                        next_state = DATA;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            DATA: begin 
                if(clk_cnt == BIT_CYCLES - 1 &&
                   bit_index == 3'd7) begin
                    next_state = STOP;
                end
            end

            STOP: begin
                if(clk_cnt == BIT_CYCLES - 1) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Collect the eight data bits.
    always @(posedge clk) begin
        if(rst) begin
            bit_index <= 3'd0;
            rx_shift <= 8'd0;
        end else if(state == IDLE) begin
            bit_index <= 3'd0;
        end else if(state == DATA && clk_cnt == BIT_CYCLES - 1) begin
            rx_shift[bit_index] <= rx_sync;
            if(bit_index < 3'd7) begin
                bit_index <= bit_index + 1'b1;
            end
        end
    end

    // Publish the byte when the stop bit is valid
    always @(posedge clk) begin
        if (rst) begin
            rx_data <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (state == STOP &&
                clk_cnt == BIT_CYCLES - 1 &&
                rx_sync) begin
                rx_data <= rx_shift;
                rx_valid <= 1'b1;
            end
        end
    end
endmodule
