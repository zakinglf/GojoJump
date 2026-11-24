`timescale 1ns / 1ps

module tb_player_ctrl;
    reg pixel_clk = 0;
    reg rst = 1;
    reg move_prepare = 0;
    reg move_tick = 0;

    always @(posedge pixel_clk)
        move_tick <= !rst && move_prepare;
    reg move_left = 0;
    reg move_right = 0;
    reg direct_jump = 0, tick_jump = 0, use_decoder = 0;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0;
    wire decoded_left, decoded_right, decoded_jump;
    wire jump_input = use_decoder ? decoded_jump : direct_jump;
    reg model_pending = 0, decoder_down = 0;
    integer launches = 0, case_launches, request_pulses = 0;
    integer supported_now;
    reg [99:0] xs = 0, ys = 0, widths = 0;
    reg [9:0] active = 0;
    wire [9:0] player_x, player_y;
    wire [9:0] scroll_dy;
    wire fell_off_screen;
    integer layout_x [0:9];
    integer layout_y [0:9];
    integer layout_width [0:9];
    integer model_x, model_y, model_vy;
    integer predicted_x, predicted_y, selected_top;
    integer expected_hit;
    integer errors = 0, cases_checked = 0, ticks_checked = 0;
    integer hold_edges = 0, landings = 0, case_landings;
    integer first_landing, first_landing_tick, case_ticks;
    integer upper_landings, upward_crossings;
    integer n, p;

    // Explicit baseline settings check that overrides reach control and collision.
    player_ctrl #(
        .PLATFORM_COUNT(10), .PLAYER_WIDTH(20), .PLAYER_HEIGHT(20),
        .JUMP_VELOCITY_FP(-16'sd96), .SCROLL_LINE_Y(0)
    ) dut (
        .pixel_clk(pixel_clk), .rst(rst),
        .move_prepare(move_prepare), .move_tick(move_tick),
        .pause_game(1'b0), .dash_pressed(1'b0), .black_flash_hit(1'b0),
        .move_left(move_left), .move_right(move_right),
        .jump_pressed(jump_input),
        .platform_x_bus(xs), .platform_y_bus(ys),
        .platform_width_bus(widths), .platform_active(active),
        .player_x(player_x), .player_y(player_y), .scroll_dy(scroll_dy),
        .fell_off_screen(fell_off_screen)
    );
    always #20 pixel_clk = ~pixel_clk;

    input_ctrl decoder (
        .clk(pixel_clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .move_left(decoded_left), .move_right(decoded_right), .jump_pressed(decoded_jump)
    );

    task fail;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERROR: case %0d, tick %0d: %0s", cases_checked, case_ticks, message);
        end
    endtask

    task clear_layout;
        integer j;
        begin
            xs = 0; ys = 0; widths = 0; active = 0;
            for (j = 0; j < 10; j = j + 1) begin
                layout_x[j] = 0; layout_y[j] = 0; layout_width[j] = 0;
            end
        end
    endtask

    task set_platform;
        input integer slot, x, y, width, enabled;
        begin
            layout_x[slot] = x; layout_y[slot] = y; layout_width[slot] = width;
            xs[slot*10 +: 10] = x;
            ys[slot*10 +: 10] = y;
            widths[slot*10 +: 10] = width;
            active[slot] = enabled;
        end
    endtask

    task check_state;
        begin
            if (player_x !== model_x || player_y !== (model_y / 4) ||
                $signed(dut.y_fp) !== model_y * 4 ||
                $signed(dut.vy_fp) !== model_vy * 4)
                fail("Position or fixed-point velocity differs from the quarter-pixel model");
            if (scroll_dy !== 10'd0) fail("The baseline configuration must not scroll");
            if (fell_off_screen !== (model_y >= 480 * 4))
                fail("Fall-out status differs from the quarter-pixel model");
        end
    endtask

    task reset_case;
        begin
            @(negedge pixel_clk);
            rst = 1; move_prepare = 0; move_left = 0; move_right = 0;
            direct_jump = 0; tick_jump = 0; rx_valid = 0;
            model_pending = 0; decoder_down = 0; case_launches = 0;
            model_x = 100; model_y = 800; model_vy = 0;
            case_landings = 0; case_ticks = 0;
            first_landing = -1; first_landing_tick = -1;
            upper_landings = 0; upward_crossings = 0;
            repeat (2) begin @(posedge pixel_clk); #1; check_state; end
            if (dut.jump_pending !== 1'b0 || decoded_jump !== 1'b0)
                fail("Reset must clear both pending and decoded jump requests");
            @(negedge pixel_clk); rst = 0;
        end
    endtask

    task queue_jump;
        begin
            @(negedge pixel_clk); direct_jump = 1;
            @(posedge pixel_clk); #1;
            model_pending = 1;
            check_state;
            if (dut.jump_pending !== 1'b1) fail("A short off-tick pulse must be retained");
            @(negedge pixel_clk); direct_jump = 0;
            repeat (2) begin
                @(posedge pixel_clk); #1; check_state;
                if (dut.jump_pending !== 1'b1) fail("Pending request must survive idle cycles");
            end
            request_pulses = request_pulses + 1;
        end
    endtask

    // Feed a complete keyboard-state byte to the actual input decoder.
    task keyboard_packet;
        input [7:0] payload;
        reg press;
        begin
            press = payload[2] && !decoder_down;
            @(negedge pixel_clk); rx_data = payload; rx_valid = 1;
            @(posedge pixel_clk); #1;
            if ({decoded_right, decoded_left} !== payload[1:0] || decoded_jump !== press)
                fail("Input decoder must emit one pulse on a Space rising edge");
            decoder_down = payload[2];
            @(negedge pixel_clk); rx_valid = 0;
            @(posedge pixel_clk); #1;
            if (decoded_jump !== 1'b0) fail("Decoded jump pulse must last one clock");
            if (press) begin model_pending = 1; request_pulses = request_pulses + 1; end
            if (dut.jump_pending !== model_pending)
                fail("Decoder pulse must reach the player request buffer");
            check_state;
        end
    endtask

    // Model physical motion in quarter-pixel units, without using RTL predictions.
    task step_player;
        input left_key, right_key;
        integer j;
        begin
            @(negedge pixel_clk);
            move_left = left_key; move_right = right_key; move_prepare = 1;
            direct_jump = tick_jump;
            predicted_x = model_x;
            if (left_key && !right_key && model_x > 0) predicted_x = model_x - 1;
            if (right_key && !left_key && model_x < 620) predicted_x = model_x + 1;
            predicted_y = model_y + model_vy;
            selected_top = 1024;
            supported_now = 0;
            for (j = 0; j < 10; j = j + 1) begin
                if (active[j] && predicted_x < layout_x[j] + layout_width[j] &&
                    predicted_x + 20 > layout_x[j] && model_y + 80 == layout_y[j] * 4)
                    supported_now = 1;
                if (active[j] && model_vy > 0 &&
                    predicted_x < layout_x[j] + layout_width[j] &&
                    predicted_x + 20 > layout_x[j] &&
                    model_y + 80 <= layout_y[j] * 4 &&
                    predicted_y + 80 >= layout_y[j] * 4 &&
                    layout_y[j] < selected_top)
                    selected_top = layout_y[j];
            end
            expected_hit = (selected_top < 1024);
            if (model_vy < 0 && model_y + 80 >= 800 && predicted_y + 80 < 800)
                upward_crossings = upward_crossings + 1;
            @(posedge pixel_clk); #1;
            @(negedge pixel_clk); move_prepare = 0; direct_jump = 0;
            #1;
            if (dut.landed !== (expected_hit != 0))
                fail("Landing decision differs from the reference geometry");
            if (expected_hit && dut.landing_y !== selected_top)
                fail("Landing must select the first crossed platform");
            if (dut.supported !== (supported_now != 0))
                fail("Support must follow exact foot contact and predicted horizontal overlap");
            model_x = predicted_x;
            case_ticks = case_ticks + 1;
            if (expected_hit) begin
                model_y = (selected_top - 20) * 4;
                model_vy = 0;
                case_landings = case_landings + 1; landings = landings + 1;
                if (first_landing < 0) begin
                    first_landing = selected_top; first_landing_tick = case_ticks;
                end
                if (selected_top == 200) upper_landings = upper_landings + 1;
            end
            else if (supported_now && model_vy == 0) begin
                if (model_pending || tick_jump) begin
                    model_vy = -24;
                    launches = launches + 1; case_launches = case_launches + 1;
                end
            end
            else begin
                model_y = predicted_y;
                model_vy = model_vy + 1;
            end
            model_pending = 0;
            @(posedge pixel_clk); #1;
            check_state;
            if (expected_hit && ($signed(dut.y_fp) + 320 != selected_top * 16 ||
                                 $signed(dut.vy_fp) != 0))
                fail("Landing must align the feet exactly and stop vertical motion");
            if (dut.jump_pending !== 1'b0) fail("Each movement tick must consume a pending request");
            ticks_checked = ticks_checked + 1;
            @(negedge pixel_clk); tick_jump = 0;
            // Change controls while the tick is low; state must still hold.
            move_left = !left_key; move_right = !right_key;
            repeat (3) begin
                @(posedge pixel_clk); #1;
                check_state; hold_edges = hold_edges + 1;
            end
        end
    endtask

    // A separate collision probe checks boundary cases using only module ports.
    reg [9:0] probe_x = 100;
    reg signed [15:0] probe_feet = 0, probe_next_feet = 0;
    reg probe_falling = 1;
    reg [99:0] probe_xs = 0, probe_ys = 0, probe_widths = 0;
    reg [9:0] probe_active = 0;
    wire probe_landed;
    wire probe_supported;
    wire [9:0] probe_landing_y;
    platform_collision #(.PLAYER_WIDTH(20)) probe (
        .next_player_x(probe_x), .feet_fp(probe_feet),
        .next_feet_fp(probe_next_feet), .falling(probe_falling),
        .platform_x_bus(probe_xs), .platform_y_bus(probe_ys),
        .platform_width_bus(probe_widths), .platform_active(probe_active),
        .landed(probe_landed), .landing_y(probe_landing_y), .supported(probe_supported)
    );
    task expect_collision;
        input integer hit, top;
        begin
            #2;
            if (probe_landed !== (hit != 0) || probe_landing_y !== top)
                fail("Directed collision boundary case failed");
            cases_checked = cases_checked + 1;
        end
    endtask

    initial begin
        clear_layout;
        reset_case;
        repeat (10) begin @(posedge pixel_clk); #1; check_state; end
        for (n = 0; n < 12; n = n + 1) step_player(0, 0);
        if (model_y != 866 || model_vy != 12 || case_landings != 0)
            fail("After 12 free-fall ticks: y=216.5, vy=3, no landing");
        cases_checked = cases_checked + 1;

        clear_layout;
        for (p = 0; p < 10; p = p + 1)
            set_platform(p, (p % 2 == 0) ? 80 : 160, 440 - p * 40, 64, 1);
        reset_case;
        for (n = 0; n < 180; n = n + 1) step_player(0, 0);
        if (first_landing != 280 || first_landing_tick != 23 || case_landings != 1 ||
            model_y != 1040 || model_vy != 0 || case_launches != 0)
            fail("Default layout must land at y=280 on tick 23 and remain standing");
        cases_checked = cases_checked + 1;

        tick_jump = 1;
        step_player(0, 0);
        if (model_vy != -24 || case_launches != 1)
            fail("A jump pulse coinciding with move_tick must launch immediately");
        repeat (60) step_player(0, 0);
        if (model_y != 1040 || model_vy != 0 || case_launches != 1)
            fail("After a manual jump the player must land and remain standing");
        cases_checked = cases_checked + 1;

        queue_jump;
        step_player(0, 0);
        if (model_vy != -24 || case_launches != 2)
            fail("A short pulse between movement ticks must launch on the next tick");
        cases_checked = cases_checked + 1;
        queue_jump;
        step_player(0, 0);
        repeat (60) step_player(0, 0);
        if (case_launches != 2 || model_vy != 0 || model_y != 1040)
            fail("An airborne request must be consumed without a double jump or delayed launch");
        cases_checked = cases_checked + 1;

        // Walking completely off the platform removes support on that same tick.
        repeat (45) step_player(0, 1);
        if (model_x != 145 || model_vy != 2 || model_y != 1041)
            fail("Walking off the edge must restart gravity without hovering");
        cases_checked = cases_checked + 1;

        clear_layout;
        set_platform(0, 0, 220, 640, 1);
        reset_case;
        repeat (4) step_player(0, 0);
        active[0] = 0;
        repeat (3) step_player(0, 0);
        if (model_vy != 3 || model_y != 803)
            fail("Removing the supporting platform must make the player fall");
        cases_checked = cases_checked + 1;

        // Test the actual decoder and player together with held state packets.
        clear_layout;
        set_platform(0, 0, 220, 640, 1);
        use_decoder = 1;
        reset_case;
        keyboard_packet(8'h04);
        step_player(0, 0);
        for (n = 0; n < 60; n = n + 1) begin
            if (n == 10 || n == 55) keyboard_packet(8'h04);
            step_player(0, 0);
        end
        if (case_launches != 1 || model_y != 800 || model_vy != 0)
            fail("Holding Space across landing must not repeat the jump");
        cases_checked = cases_checked + 1;
        keyboard_packet(8'h00);
        keyboard_packet(8'h04);
        step_player(0, 0);
        if (case_launches != 2 || model_vy != -24)
            fail("Releasing and pressing Space must permit a second grounded jump");
        keyboard_packet(8'h00);
        keyboard_packet(8'h04);
        step_player(0, 0);
        repeat (60) step_player(0, 0);
        if (case_launches != 2 || model_vy != 0)
            fail("A new Space press in the air must not cause a later automatic jump");
        cases_checked = cases_checked + 1;
        keyboard_packet(8'h00);
        keyboard_packet(8'h04);
        reset_case;
        repeat (3) step_player(0, 0);
        if (case_launches != 0 || model_vy != 0)
            fail("Reset must cancel a queued jump while restoring standing state");
        cases_checked = cases_checked + 1;
        use_decoder = 0;

        clear_layout;
        set_platform(0, 80, 280, 64, 1);
        reset_case;
        queue_jump;
        repeat (80) step_player(0, 0);
        if (case_launches != 0 || model_y != 1040 || model_vy != 0)
            fail("An initial airborne press must expire before landing");
        cases_checked = cases_checked + 1;

        clear_layout;
        set_platform(0, 80, 260, 64, 1);
        set_platform(9, 80, 200, 64, 1);
        reset_case;
        repeat (25) step_player(0, 0);
        queue_jump;
        step_player(0, 0);
        for (n = 0; n < 120; n = n + 1) step_player(0, 0);
        if (first_landing != 260 || upward_crossings == 0 || upper_landings == 0)
            fail("Player must rise through the upper platform, then land on it while falling");
        cases_checked = cases_checked + 1;

        clear_layout;
        set_platform(0, 80, 240, 64, 0);
        set_platform(9, 80, 280, 64, 1);
        reset_case;
        for (n = 0; n < 80; n = n + 1) step_player(0, 0);
        if (first_landing != 280 || case_landings != 1)
            fail("Inactive platforms must be ignored");
        cases_checked = cases_checked + 1;

        clear_layout;
        set_platform(0, 400, 240, 64, 1);
        reset_case;
        for (n = 0; n < 30; n = n + 1) step_player(0, 0);
        if (case_landings != 0) fail("Horizontally separated platforms must not catch the player");
        cases_checked = cases_checked + 1;

        // On tick two, only the predicted X overlaps the platform.
        clear_layout;
        set_platform(0, 121, 220, 64, 1);
        reset_case;
        step_player(0, 1);
        step_player(0, 1);
        if (model_x != 102 || first_landing != 220 || first_landing_tick != 2)
            fail("Moving into a platform edge must use the new horizontal position");
        cases_checked = cases_checked + 1;

        // The old X overlaps, but the new X only touches the right edge.
        clear_layout;
        set_platform(0, 80, 220, 21, 1);
        reset_case;
        step_player(0, 0);
        step_player(0, 1);
        if (model_x != 101 || case_landings != 0)
            fail("Moving out of a platform edge must not land using stale X");
        cases_checked = cases_checked + 1;

        clear_layout;
        set_platform(0, 0, 440, 640, 1);
        reset_case;
        for (n = 0; n < 550; n = n + 1) step_player(0, 1);
        if (model_x != 620) fail("Right boundary must clamp at 620");
        for (n = 0; n < 650; n = n + 1) step_player(1, 0);
        if (model_x != 0) fail("Left boundary must clamp at zero");
        repeat (8) step_player(1, 1);
        repeat (8) step_player(0, 0);
        if (model_x != 0) fail("Both directions or neither direction must preserve X");
        cases_checked = cases_checked + 1;
        // Reassert reset during motion, then verify the next free-fall update.
        reset_case;
        step_player(0, 0);
        if (model_y != 800 || model_vy != 1) fail("Reset must restore the full vertical state");
        cases_checked = cases_checked + 1;

        probe_xs[9:0] = 80; probe_ys[9:0] = 280;
        probe_widths[9:0] = 64; probe_active = 1;
        probe_feet = 279 * 16; probe_next_feet = 281 * 16;
        expect_collision(1, 280);
        probe_active = 0; expect_collision(0, 0);
        probe_active = 1; probe_falling = 0; expect_collision(0, 0);
        probe_falling = 1;
        probe_x = 60; expect_collision(0, 0);
        probe_x = 61; expect_collision(1, 280);
        probe_x = 144; expect_collision(0, 0);
        probe_x = 143; expect_collision(1, 280);
        probe_x = 100;
        probe_feet = 280 * 16; probe_next_feet = 281 * 16;
        expect_collision(1, 280);
        probe_feet = 279 * 16; probe_next_feet = 280 * 16;
        expect_collision(1, 280);
        probe_feet = 281 * 16; probe_next_feet = 282 * 16;
        expect_collision(0, 0);
        probe_feet = 280 * 16; probe_next_feet = 280 * 16;
        probe_falling = 0; expect_collision(0, 0);
        if (probe_supported !== 1'b1) fail("Stationary foot contact must provide support");
        probe_active = 0; #2;
        if (probe_supported !== 1'b0) fail("Inactive platform must not provide support");
        cases_checked = cases_checked + 1;
        probe_active = 1; probe_x = 144; #2;
        if (probe_supported !== 1'b0) fail("Touching a side edge must not provide support");
        cases_checked = cases_checked + 1;
        probe_x = 100;
        // Higher platform has a larger slot number, exercising geometric selection.
        probe_falling = 1;
        probe_xs[99:90] = 80; probe_ys[99:90] = 279;
        probe_widths[99:90] = 64; probe_active = 10'b1000000001;
        probe_feet = 278 * 16; probe_next_feet = 282 * 16;
        expect_collision(1, 279);
        probe_ys[99:90] = 281; expect_collision(1, 280);
        probe_active = 1; probe_ys[9:0] = 0;
        probe_feet = -16; probe_next_feet = 16;
        expect_collision(1, 0);
        probe_ys[9:0] = 1023;
        probe_feet = 1022 * 16; probe_next_feet = 1023 * 16;
        expect_collision(1, 1023);

        $display("COVERAGE: %0d landings, %0d launches, %0d requests, %0d hold edges; manual jump and support",
                 landings, launches, request_pulses, hold_edges);
        if (errors == 0)
            $display("PASS: player_ctrl checked %0d cases, %0d movement ticks, 0 errors",
                     cases_checked, ticks_checked);
        else
            $display("FAIL: player_ctrl checked %0d cases, %0d movement ticks, %0d errors",
                     cases_checked, ticks_checked, errors);
        $finish;
    end
    initial begin
        #2_000_000;
        $display("FAIL: player control simulation timed out");
        $finish;
    end
endmodule
