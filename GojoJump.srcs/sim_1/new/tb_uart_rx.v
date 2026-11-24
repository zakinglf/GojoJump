`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/01 15:35:52
// Design Name: 
// Module Name: tb_uart_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_uart_rx;
    localparam integer CLK_FREQ = 25_000_000;
    localparam integer BAUD_RATE = 115200;
    localparam integer CLK_PERIOD_NS = 40;
    // Use the actual baud period, independently of the DUT's integer divider.
    localparam real BIT_NS = 1_000_000_000.0 / BAUD_RATE;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rx = 1'b1;
    wire [7:0] rx_data;
    wire rx_valid;

    integer errors = 0;
    integer expected_count = 0;
    integer received_count = 0;
    integer cases_run = 0;
    integer pattern;
    reg previous_valid = 1'b0;
    reg [7:0] previous_data = 8'd0;
    reg [7:0] expected_data [0:511];
    realtime earliest_valid [0:511];
    realtime latest_valid [0:511];

    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    task report_error;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 12)
                $display("ERROR at %0t: %0s", $time, message);
        end
    endtask

    // Check public outputs after nonblocking assignments have settled.
    always @(posedge clk) begin
        #1;
        if (rst) begin
            if (rx_valid !== 1'b0 || rx_data !== 8'd0)
                report_error("Outputs must be zero during reset");
            previous_valid = 1'b0;
            previous_data = 8'd0;
        end else begin
            if (rx_valid !== 1'b0 && rx_valid !== 1'b1)
                report_error("rx_valid contains X or Z");

            if (previous_valid && rx_valid !== 1'b0)
                report_error("rx_valid must last exactly one clock cycle");

            if (rx_valid === 1'b1) begin
                if (received_count >= expected_count) begin
                    report_error("Unexpected byte, duplicate byte, or invalid frame accepted");
                end else begin
                    if (rx_data !== expected_data[received_count]) begin
                        $display("Byte %0d: expected %02h, received %02h",
                                 received_count, expected_data[received_count], rx_data);
                        report_error("Received byte mismatch");
                    end
                    if ($realtime < earliest_valid[received_count] ||
                        $realtime >= latest_valid[received_count])
                        report_error("rx_valid must occur within the expected stop bit");
                    received_count = received_count + 1;
                end
            end else if (rx_data !== previous_data) begin
                report_error("rx_data changed without rx_valid");
            end
            previous_valid = rx_valid;
            previous_data = rx_data;
        end
    end

    // Send 8N1, least significant bit first, with optional stop-bit corruption.
    task send_frame;
        input [7:0] payload;
        input stop_level;
        input realtime bit_time_ns;
        input expect_byte;
        integer bit_number;
        begin
            cases_run = cases_run + 1;
            if (expect_byte) begin
                expected_data[expected_count] = payload;
                earliest_valid[expected_count] = $realtime + 9.0 * bit_time_ns;
                latest_valid[expected_count] = $realtime + 10.0 * bit_time_ns;
                expected_count = expected_count + 1;
            end
            rx = 1'b0;
            #(bit_time_ns);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                rx = payload[bit_number];
                #(bit_time_ns);
            end
            rx = stop_level;
            #(bit_time_ns);
            rx = 1'b1;
        end
    endtask

    task check_drained;
        begin
            repeat (20) @(negedge clk);
            if (received_count != expected_count)
                report_error("An expected byte was not received before its deadline");
        end
    endtask

    initial begin
        // Reset and idle must not generate a received byte.
        repeat (5) @(negedge clk);
        rst = 1'b0;
        #(2.0 * BIT_NS + 137.0);

        $display("TEST: isolated byte and bit ordering");
        send_frame(8'hA5, 1'b1, BIT_NS, 1'b1);
        check_drained;

        $display("TEST: all 256 values with only one stop bit between frames");
        #13;
        for (pattern = 0; pattern < 256; pattern = pattern + 1)
            send_frame(pattern[7:0], 1'b1, BIT_NS, 1'b1);
        check_drained;

        $display("TEST: transmitter bit times at -2%% and +2%%");
        #7;
        send_frame(8'h00, 1'b1, BIT_NS * 0.98, 1'b1);
        send_frame(8'hFF, 1'b1, BIT_NS * 0.98, 1'b1);
        send_frame(8'h96, 1'b1, BIT_NS * 0.98, 1'b1);
        check_drained;
        #11;
        send_frame(8'h00, 1'b1, BIT_NS * 1.02, 1'b1);
        send_frame(8'hFF, 1'b1, BIT_NS * 1.02, 1'b1);
        send_frame(8'h69, 1'b1, BIT_NS * 1.02, 1'b1);
        check_drained;

        $display("TEST: reject a short false start and recover");
        cases_run = cases_run + 1;
        rx = 1'b0;
        #(BIT_NS / 4.0);
        rx = 1'b1;
        #(12.0 * BIT_NS);
        check_drained;
        send_frame(8'h3C, 1'b1, BIT_NS, 1'b1);
        check_drained;

        $display("TEST: reject a low stop bit and recover after idle");
        send_frame(8'h96, 1'b0, BIT_NS, 1'b0);
        #(12.0 * BIT_NS);
        check_drained;
        send_frame(8'hC3, 1'b1, BIT_NS, 1'b1);
        check_drained;

        $display("TEST: reset aborts a partial frame and reception recovers");
        cases_run = cases_run + 1;
        rx = 1'b0;
        #(BIT_NS);
        rx = 1'b1;
        #(BIT_NS);
        rx = 1'b0;
        #(BIT_NS);
        rx = 1'b1;
        #(BIT_NS);
        @(negedge clk);
        rst = 1'b1;
        rx = 1'b1;
        repeat (5) @(negedge clk);
        rst = 1'b0;
        #(12.0 * BIT_NS + 19.0);
        check_drained;
        send_frame(8'h5A, 1'b1, BIT_NS, 1'b1);
        check_drained;

        // Keep checking for late, duplicate, or spurious output pulses.
        #(12.0 * BIT_NS);
        check_drained;
        if (errors == 0)
            $display("PASS: uart_rx checked %0d cases, %0d bytes, 0 errors",
                     cases_run, received_count);
        else
            $display("FAIL: uart_rx checked %0d cases, received %0d/%0d bytes, %0d errors",
                     cases_run, received_count, expected_count, errors);
        $finish;
    end

    initial begin
        #40_000_000;
        $display("FAIL: uart_rx simulation timed out");
        $finish;
    end
endmodule
