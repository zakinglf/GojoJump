`timescale 1ns / 1ps

module tb_top;
    localparam integer FRAME_PIXELS = 800 * 525;
    localparam integer FRAMES = 32;
    localparam integer TOTAL_PIXELS = FRAMES * FRAME_PIXELS;
    localparam real BIT_NS = 1_000_000_000.0 / 115200;
    // Independent expectations for the default top-level configuration.
    localparam integer PLAYER_W = 16;
    localparam integer PLAYER_H = 16;
    localparam integer PLAYER_STEP = 2;
    localparam integer PLATFORM_GAP = 30;
    localparam integer PLATFORM_H = 6;
    localparam integer JUMP_QUARTERS = -18;
    localparam integer SCROLL_LINE_QUARTERS = 320 * 4;
    localparam [99:0] PLATFORM_X = {
        10'd480, 10'd520, 10'd560, 10'd520, 10'd480,
        10'd440, 10'd400, 10'd360, 10'd320, 10'd280
    };

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rx = 1'b1;
    wire [3:0] red, green, blue;
    wire hsync, vsync;

    integer step;
    integer x, y;
    integer errors = 0;
    integer checked_pixels = 0;
    integer expected_player_x = 304;
    integer expected_y_quarters = 424 * 4;
    integer expected_vy_quarters = 0;
    integer predicted_y_quarters;
    integer landing_height;
    integer model_landings = 0;
    integer model_launches = 0;
    integer model_supported;
    integer camera_pixels = 0;
    integer frame_scroll;
    integer jump_pulses = 0;
    reg model_jump_down = 0;
    reg model_jump_pending = 0;
    reg decoder_jump_down = 0;
    integer sent_commands = 0;
    integer received_commands = 0;
    integer ticks_checked = 0;
    integer green_pixels = 0;
    integer gray_pixels = 0;
    integer expected_gray_pixels = 0;
    integer platform_index;
    integer reference_platform_x;
    integer reference_platform_y;
    reg [7:0] model_command = 8'h00;
    reg [7:0] transmitting_command = 8'h00;
    reg command_pending = 1'b0;
    reg stimulus_done = 1'b0;
    reg previous_rx_valid = 1'b0;
    reg expected_tick;
    reg [11:0] expected_rgb;
    reg [13:0] expected_outputs;
    time last_edge;
    realtime earliest_receive;
    realtime latest_receive;

    top dut (
        .clk(clk), .rst(rst), .rx(rx),
        .vga_red(red), .vga_green(green), .vga_blue(blue),
        .vga_hsync(hsync), .vga_vsync(vsync)
    );

    // Generate the actual 100 MHz board clock.
    always #5 clk = ~clk;

    task report_error;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("ERROR at %0t, sample %0d: %0s", $time, step, message);
        end
    endtask

    // Check platform initialization and retention independently of rendering.
    task check_platform_layout;
        integer p;
        integer layout_x;
        integer layout_y;
        begin
            if (dut.platform_active !== 10'b1111111111)
                report_error("All ten platforms must remain active");
            for (p = 0; p < 10; p = p + 1) begin
                layout_x = PLATFORM_X[p*10 +: 10];
                layout_y = 440 - p * PLATFORM_GAP + camera_pixels;
                if (dut.platform_x_bus[p*10 +: 10] !== layout_x[9:0] ||
                    dut.platform_y_bus[p*10 +: 10] !== layout_y[9:0] ||
                    dut.platform_width_bus[p*10 +: 10] !== 10'd64)
                    report_error("Platform position or width differs from the fixed layout");
            end
        end
    endtask

    // Drive the external UART pin using real baud timing and LSB-first data.
    task send_byte;
        input [7:0] payload;
        integer bit_number;
        begin
            transmitting_command = payload;
            command_pending = 1'b1;
            sent_commands = sent_commands + 1;
            earliest_receive = $realtime + 9.0 * BIT_NS;
            latest_receive = $realtime + 10.0 * BIT_NS;
            rx = 1'b0;
            #(BIT_NS);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                rx = payload[bit_number];
                #(BIT_NS);
            end
            rx = 1'b1;
            #(BIT_NS);
            // Reception and decoding must have finished by the end of the stop bit.
            if (payload[2] && !model_jump_down)
                model_jump_pending = 1;
            model_jump_down = payload[2];
            model_command = payload;
            command_pending = 1'b0;
            $display("COMMAND: frame %0d, byte %02h", checked_pixels / FRAME_PIXELS, payload);
        end
    endtask

    // Schedule commands using the independent testbench sample count.
    task send_in_frame;
        input integer frame_number;
        input [7:0] payload;
        begin
            while (checked_pixels < frame_number * FRAME_PIXELS + 1000)
                @(negedge clk);
            #13;
            send_byte(payload);
        end
    endtask

    initial begin
        repeat (4) @(posedge dut.pixel_clk);
        #1;
        if (dut.player_x !== 10'd304 || dut.player_y !== 10'd424 ||
            dut.move_left !== 1'b0 || dut.move_right !== 1'b0 ||
            dut.rx_valid !== 1'b0)
            report_error("Player, input decoder, or UART reset value is incorrect");
        check_platform_layout;
        @(negedge clk);
        rst = 1'b0;

        fork
            begin
                // Walk left, then jump right from the starting platform.
                send_in_frame(1, 8'h01);
                send_in_frame(2, 8'h06);
                send_in_frame(3, 8'h06);
                send_in_frame(4, 8'h02);
                // A second Space press in the air must not start another jump.
                send_in_frame(5, 8'h06);
                send_in_frame(6, 8'h02);
                send_in_frame(7, 8'h03);
                send_in_frame(8, 8'h00);
                send_in_frame(10, 8'h02);
                send_in_frame(26, 8'h00);
                stimulus_done = 1'b1;
            end

            begin
                for (step = 1; step <= TOTAL_PIXELS; step = step + 1) begin
                    @(posedge dut.pixel_clk);
                    if (step > 1 && ($time - last_edge) != 40)
                        report_error("Pixel clock period must be 40 ns");
                    last_edge = $time;
                    #1;

                    // Derive raster position and movement timing without reading DUT counters.
                    x = step % 800;
                    y = (step / 800) % 525;
                    expected_tick = (step % FRAME_PIXELS == 490 * 800);

                    if (dut.move_prepare !== expected_tick)
                        report_error("move_prepare must pulse once at the start of vertical sync");
                    if (dut.move_tick !== (step % FRAME_PIXELS == 490 * 800 + 1))
                        report_error("move_tick must pulse one pixel clock after move_prepare");
                    if (expected_tick)
                        ticks_checked = ticks_checked + 1;

                    // Apply the movement model at the commit edge.
                    if (step % FRAME_PIXELS == 490 * 800 + 2) begin
                        if (command_pending)
                            report_error("Stimulus overlaps the movement edge");
                        case (model_command[1:0])
                            2'b01: begin
                                expected_player_x = expected_player_x - PLAYER_STEP;
                                if (expected_player_x < 0)
                                    expected_player_x = 0;
                            end
                            2'b10: begin
                                expected_player_x = expected_player_x + PLAYER_STEP;
                                if (expected_player_x > 640 - PLAYER_W)
                                    expected_player_x = 640 - PLAYER_W;
                            end
                        endcase
                        // Use quarter-pixel units, independent of the RTL's 1/16 units.
                        predicted_y_quarters = expected_y_quarters + expected_vy_quarters;
                        landing_height = 1024;
                        model_supported = 0;
                        for (platform_index = 0; platform_index < 10;
                             platform_index = platform_index + 1) begin
                            reference_platform_x = PLATFORM_X[platform_index*10 +: 10];
                            reference_platform_y = 440 - platform_index * PLATFORM_GAP + camera_pixels;
                            if (expected_player_x < reference_platform_x + 64 &&
                                expected_player_x + PLAYER_W > reference_platform_x &&
                                expected_y_quarters + PLAYER_H * 4 == reference_platform_y * 4)
                                model_supported = 1;
                            if (expected_vy_quarters > 0 &&
                                expected_player_x < reference_platform_x + 64 &&
                                expected_player_x + PLAYER_W > reference_platform_x &&
                                expected_y_quarters + PLAYER_H * 4 <= reference_platform_y * 4 &&
                                predicted_y_quarters + PLAYER_H * 4 >= reference_platform_y * 4 &&
                                reference_platform_y < landing_height)
                                landing_height = reference_platform_y;
                        end
                        if (landing_height < 1024) begin
                            expected_y_quarters = (landing_height - PLAYER_H) * 4;
                            expected_vy_quarters = 0;
                            model_landings = model_landings + 1;
                        end
                        else if (model_supported && expected_vy_quarters == 0) begin
                            if (model_jump_pending) begin
                                expected_vy_quarters = JUMP_QUARTERS;
                                model_launches = model_launches + 1;
                            end
                        end
                        else begin
                            frame_scroll = 0;
                            if (expected_vy_quarters < 0 && predicted_y_quarters < SCROLL_LINE_QUARTERS)
                                frame_scroll = (SCROLL_LINE_QUARTERS - predicted_y_quarters + 3) / 4;
                            camera_pixels = camera_pixels + frame_scroll;
                            expected_y_quarters = predicted_y_quarters + frame_scroll * 4;
                            expected_vy_quarters = expected_vy_quarters + 1;
                        end
                        model_jump_pending = 0;
                    end

                    if (dut.player_x !== expected_player_x ||
                        dut.player_y !== (expected_y_quarters / 4) ||
                        $signed(dut.u_player_ctrl.y_fp) !== expected_y_quarters * 4 ||
                        $signed(dut.u_player_ctrl.vy_fp) !== expected_vy_quarters * 4)
                        report_error("Player position differs from the independent movement model");

                    // Check the command decoder once a whole frame has been transmitted.
                    if (!command_pending &&
                        {dut.move_right, dut.move_left} !== model_command[1:0])
                        report_error("Decoded movement flags do not match the transmitted command");

                    if (dut.rx_valid !== 1'b0 && dut.rx_valid !== 1'b1)
                        report_error("UART valid signal contains X or Z");
                    if (previous_rx_valid && dut.rx_valid !== 1'b0)
                        report_error("UART valid signal must last one pixel clock");
                    if (dut.rx_valid === 1'b1) begin
                        received_commands = received_commands + 1;
                        if (!command_pending ||
                            dut.rx_data !== transmitting_command ||
                            $realtime < earliest_receive ||
                            $realtime >= latest_receive)
                            report_error("Unexpected UART command value or reception time");
                    end
                    // The decoder consumes UART valid one clock after the receiver asserts it.
                    if (dut.jump_pressed !== (previous_rx_valid && transmitting_command[2] && !decoder_jump_down))
                        report_error("Jump decoder must pulse once per Space rising edge");
                    if (previous_rx_valid)
                        decoder_jump_down = transmitting_command[2];
                    if (dut.jump_pressed === 1'b1)
                        jump_pulses = jump_pulses + 1;
                    previous_rx_valid = dut.rx_valid;

                    // Build the reference image without reading DUT platform coordinates.
                    expected_rgb = 12'h000;
                    if (x < 640 && y < 480) begin
                        for (platform_index = 0; platform_index < 10;
                             platform_index = platform_index + 1) begin
                            reference_platform_x = PLATFORM_X[platform_index*10 +: 10];
                            reference_platform_y = 440 - platform_index * PLATFORM_GAP + camera_pixels;
                            if (x >= reference_platform_x && x < reference_platform_x + 64 &&
                                y >= reference_platform_y && y < reference_platform_y + PLATFORM_H)
                                expected_rgb = 12'h888;
                        end
                        // The player must cover any platform underneath it.
                        if (x >= expected_player_x && x < expected_player_x + PLAYER_W &&
                            y >= expected_y_quarters / 4 && y < expected_y_quarters / 4 + PLAYER_H)
                            expected_rgb = 12'h0F0;
                    end
                    expected_outputs = {
                        !((x >= 656) && (x < 752)),
                        !((y >= 490) && (y < 492)),
                        expected_rgb
                    };
                    if ({hsync, vsync, red, green, blue} !== expected_outputs)
                        report_error("VGA RGB or sync output mismatch");
                    if (green === 4'd15)
                        green_pixels = green_pixels + 1;
                    if ({red, green, blue} === 12'h888)
                        gray_pixels = gray_pixels + 1;
                    if (expected_rgb == 12'h888)
                        expected_gray_pixels = expected_gray_pixels + 1;

                    if (step % FRAME_PIXELS == 0) begin
                        if (green_pixels != PLAYER_W * PLAYER_H)
                            report_error("Each frame must contain exactly one complete player rectangle");
                        if (gray_pixels != expected_gray_pixels)
                            report_error("Visible platform pixel count differs from the reference image");
                        check_platform_layout;
                        $display("IMAGE: green=%0d, gray=%0d, expected gray=%0d",
                                 green_pixels, gray_pixels, expected_gray_pixels);
                        green_pixels = 0;
                        gray_pixels = 0;
                        expected_gray_pixels = 0;
                        $display("FRAME %0d: player_x=%0d, y_quarters=%0d, vy_quarters=%0d",
                                 step / FRAME_PIXELS - 1, expected_player_x,
                                 expected_y_quarters, expected_vy_quarters);
                    end
                    checked_pixels = step;
                end
            end
        join

        if (!stimulus_done || sent_commands != 10 || received_commands != 10)
            report_error("All ten UART commands must be sent and received");
        if (ticks_checked != FRAMES || expected_player_x != 344)
            report_error("Frame tick count or final reference position is incorrect");
        if (expected_y_quarters != 394 * 4 || expected_vy_quarters != 0 || camera_pixels != 0 ||
            model_landings != 1 || model_launches != 1 || jump_pulses != 2)
            report_error("Player must launch once and finish standing on the second platform");

        $display("COVERAGE: %0d pixels, %0d landings, %0d launches, %0d press pulses; UART manual jump",
                 checked_pixels, model_landings, model_launches, jump_pulses);

        if (errors == 0)
            $display("PASS: top checked %0d frames, %0d UART commands, 0 errors",
                     FRAMES, received_commands);
        else
            $display("FAIL: top checked %0d frames, %0d UART commands, %0d errors",
                     FRAMES, received_commands, errors);
        $finish;
    end

    initial begin
        #600_000_000;
        $display("FAIL: top integration simulation timed out");
        $finish;
    end
endmodule
