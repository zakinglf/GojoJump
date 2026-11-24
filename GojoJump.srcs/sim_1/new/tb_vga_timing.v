`timescale 1ns / 1ps

module tb_vga_timing;

    reg pixel_clk = 0;
    reg rst = 1;

    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire video_on;
    wire hsync;
    wire vsync;

    integer step;
    integer x;
    integer y;
    integer errors = 0;

    reg expected_hsync;
    reg expected_vsync;
    reg expected_video_on;

    vga_timing dut (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .video_on(video_on),
        .hsync(hsync),
        .vsync(vsync)
    );

    // Generate a 25 MHz pixel clock.
    always #20 pixel_clk = ~pixel_clk;

    initial begin
        // Hold reset for four clock cycles and allow the outputs to settle.
        repeat (4) @(posedge pixel_clk);
        #1;

        if ((pixel_x !== 10'd0) ||
            (pixel_y !== 10'd0)) begin
            errors = errors + 1;
            $display("FAIL: reset did not clear coordinates");
        end

        // Release reset on the falling edge to avoid the active clock edge.
        @(negedge pixel_clk);
        rst = 0;

        // Check two frames, with 800 * 525 clock cycles per frame.
        for (step = 1; step <= 840000; step = step + 1) begin
            @(posedge pixel_clk);
            #1;  // Wait for the outputs to settle after this clock edge.

            // Independently calculate the expected scan position from elapsed clock cycles.
            x = step % 800;
            y = (step / 800) % 525;

            expected_hsync = !((x >= 656) && (x < 752));
            expected_vsync = !((y >= 490) && (y < 492));
            expected_video_on = (x < 640) && (y < 480);

            // Check both sync signals and the active video flag.
            if ({hsync, vsync, video_on} !==
                {expected_hsync, expected_vsync,
                 expected_video_on}) begin

                errors = errors + 1;

                // Print only the first ten errors to limit console output.
                if (errors <= 10)
                    $display(
                        "FAIL t=%0t x=%0d y=%0d: HS/VS/ON expected=%b%b%b actual=%b%b%b",
                        $time, x, y,
                        expected_hsync, expected_vsync,
                        expected_video_on,
                        hsync, vsync, video_on
                    );
            end

            // Check pixel coordinates within the active display area.
            if (expected_video_on &&
                ((pixel_x !== x[9:0]) ||
                 (pixel_y !== y[9:0]))) begin

                errors = errors + 1;

                if (errors <= 10)
                    $display(
                        "FAIL t=%0t: XY expected=(%0d,%0d) actual=(%0d,%0d)",
                        $time, x, y, pixel_x, pixel_y
                    );
            end
        end

        if (errors == 0)
            $display("PASS: checked 2 frames, 0 errors");
        else
            $display("FAIL: total errors=%0d", errors);

        $finish;
    end

    // Stop the simulation if the test exceeds the time limit.
    initial begin
        #40000000;
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule
