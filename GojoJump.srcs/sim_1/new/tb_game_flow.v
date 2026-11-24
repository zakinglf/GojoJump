`timescale 1ns / 1ps

module tb_game_flow;
    localparam real BIT_NS = 1_000_000_000.0 / 115200;
    localparam integer PLATFORM_COUNT = 13;
    localparam integer PLATFORM_BUS_WIDTH = PLATFORM_COUNT * 10;
    localparam [9:0] PLATFORM_WIDTH = 10'd40;
    localparam integer PLATFORM_START_X = 280;
    localparam integer OPENING_X_STEP = 68;
    localparam integer OPENING_Y_STEP = 28;
    localparam integer OPENING_BOTTOM_Y = 440;
    localparam integer LOSS_PLATFORM_Y = 476;
    localparam integer SPAWN_X = PLATFORM_START_X + PLATFORM_WIDTH - 2;
    localparam integer SPAWN_Y = LOSS_PLATFORM_Y - 16;
    localparam integer X_MAX = 640 - PLATFORM_WIDTH;
    localparam [PLATFORM_BUS_WIDTH-1:0] OPENING_X = {
        10'd8, 10'd76, 10'd144, 10'd212, 10'd280, 10'd348, 10'd416,
        10'd484, 10'd552, 10'd484, 10'd416, 10'd348, 10'd280
    };
    // Each entry packs a 6-bit rise and a 7-bit horizontal edge gap.
    localparam [129:0] GAP_PAIRS = {
        6'd36, 7'd104, 6'd36, 7'd100, 6'd35, 7'd92, 6'd36, 7'd72, 6'd36, 7'd60,
        6'd35, 7'd48, 6'd32, 7'd20, 6'd28, 7'd24, 6'd28, 7'd20, 6'd24, 7'd16
    };

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rx = 1'b1;
    wire [3:0] red, green, blue;
    wire hsync, vsync;
    integer errors = 0;
    integer recycles = 0;
    integer left_reflections = 0;
    integer right_reflections = 0;

    // Start at the edge of a low platform to reach the loss boundary quickly.
    top #(
        .PLAYER_START_X(SPAWN_X), .PLAYER_START_Y(SPAWN_Y),
        .PLATFORM_COUNT(PLATFORM_COUNT), .PLATFORM_WIDTH(PLATFORM_WIDTH),
        .PLATFORM_START_X(PLATFORM_START_X), .PLATFORM_X_GAP(OPENING_X_STEP),
        .PLATFORM_Y_GAP(OPENING_Y_STEP), .PLATFORM_BOTTOM_Y(LOSS_PLATFORM_Y),
        .GRAVITY_FP(16'sd32)
    ) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .vga_red(red), .vga_green(green), .vga_blue(blue),
        .vga_hsync(hsync), .vga_vsync(vsync)
    );
    always #5 clk = ~clk;

    // Drive the game's platform layout independently of the VGA frame clock.
    reg platform_rst = 1'b1;
    reg platform_tick = 1'b0;
    reg [9:0] scroll = 10'd0;
    wire [PLATFORM_BUS_WIDTH-1:0] xs, ys, widths;
    wire [PLATFORM_COUNT-1:0] active;
    platform_ctrl #(
        .PLATFORM_COUNT(PLATFORM_COUNT), .INITIAL_WIDTH(PLATFORM_WIDTH),
        .INITIAL_X(PLATFORM_START_X), .INITIAL_X_GAP(OPENING_X_STEP),
        .INITIAL_Y_GAP(OPENING_Y_STEP), .INITIAL_BOTTOM_Y(OPENING_BOTTOM_Y)
    ) platforms (
        .pixel_clk(clk), .rst(platform_rst), .move_prepare(1'b0), .move_tick(platform_tick), .scroll_dy(scroll),
        .platform_x_bus(xs), .platform_y_bus(ys), .platform_width_bus(widths),
        .platform_active(active),
        .platform_reward_claimed(1'b0), .platform_reward_index(0)
    );

    reg score_rst = 1'b1;
    reg score_tick = 1'b0;
    reg [9:0] score_scroll = 10'd0;
    wire [15:0] score_value;
    wire [19:0] score_digits;
    score_ctrl score_probe (
        .pixel_clk(clk), .rst(score_rst), .move_tick(score_tick), .scroll_dy(score_scroll),
        .kill_bonus(16'd0),
        .score(score_value), .score_digits(score_digits)
    );

    task check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("ERROR at %0t: %0s", $time, message);
            end
        end
    endtask

    task scroll_once;
        input [9:0] dy;
        begin
            @(negedge clk);
            scroll = dy;
            platform_tick = 1'b1;
            @(posedge clk); #1;
            platform_tick = 1'b0;
        end
    endtask

    task recycle_and_check;
        input integer slot, overshoot;
        integer previous_top, remaining, last_scroll, other_slot;
        integer selector, rise, gap, expected_x, expected_y, step_x;
        reg [7:0] old_rng;
        reg [12:0] selected_gaps;
        reg [PLATFORM_BUS_WIDTH-1:0] before_xs, before_ys;
        begin
            old_rng = platforms.rng;
            before_xs = xs;
            remaining = 480 - ys[slot*10 +: 10];
            check(remaining > 0, "The next slot must start above the recycle threshold");
            while (remaining > 4) begin
                scroll_once(4);
                remaining = remaining - 4;
                check(xs == before_xs && platforms.rng == old_rng,
                      "Ordinary scrolling must preserve X and the RNG state");
            end

            before_ys = ys;
            last_scroll = remaining + overshoot;
            previous_top = (slot == 0) ? PLATFORM_COUNT - 1 : slot - 1;
            selector = old_rng[3:0];
            if (selector >= 10)
                selector = selector % 4;
            selected_gaps = GAP_PAIRS[selector*13 +: 13];
            rise = selected_gaps[12:7];
            gap = selected_gaps[6:0];

            step_x = PLATFORM_WIDTH + gap;
            if (old_rng[4])
                step_x = -step_x;
            expected_x = before_xs[previous_top*10 +: 10] + step_x;
            if (expected_x < 0 || expected_x > X_MAX) begin
                if (expected_x < 0)
                    left_reflections = left_reflections + 1;
                else
                    right_reflections = right_reflections + 1;
                expected_x = before_xs[previous_top*10 +: 10] - step_x;
            end
            expected_y = before_ys[previous_top*10 +: 10] + last_scroll - rise;

            scroll_once(last_scroll);
            check(expected_x >= 0 && expected_x <= X_MAX && expected_y >= 0 && expected_y < 480,
                  "Recycled platform must fit within the visible area");
            check(xs[slot*10 +: 10] == expected_x && ys[slot*10 +: 10] == expected_y,
                  "Recycled platform must honor the selected rise, edge gap and direction");
            for (other_slot = 0; other_slot < PLATFORM_COUNT; other_slot = other_slot + 1) begin
                if (other_slot != slot)
                    check(xs[other_slot*10 +: 10] == before_xs[other_slot*10 +: 10] &&
                          ys[other_slot*10 +: 10] == before_ys[other_slot*10 +: 10] + last_scroll,
                          "The other slots must scroll without being replaced");
            end
            check(platforms.rng != old_rng, "Recycling must advance the RNG");
            check(widths == {PLATFORM_COUNT{PLATFORM_WIDTH}} && active == {PLATFORM_COUNT{1'b1}},
                  "Recycling must preserve platform widths and active flags");
            recycles = recycles + 1;
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            rx = 1'b0;
            #(BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx = value[bit_index];
                #(BIT_NS);
            end
            rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    task check_opening;
        begin
            check(dut.game_over == 1'b0 && dut.player_x == SPAWN_X && dut.player_y == SPAWN_Y,
                  "Reset must clear Game Over and restore the spawn point");
            check(dut.platform_x_bus == OPENING_X && dut.platform_y_bus[9:0] == LOSS_PLATFORM_Y,
                  "Reset must restore the opening platform layout");
            check(dut.score == 16'd0 && dut.score_digits == 20'h00000,
                  "Reset must clear both the score and its rendered digits");
        end
    endtask

    task accrue_score;
        input integer amount;
        integer remaining;
        begin
            remaining = amount;
            while (remaining > 0) begin
                @(negedge clk);
                score_scroll = (remaining > 1023) ? 10'd1023 : remaining;
                remaining = remaining - score_scroll;
                score_tick = 1'b1;
                @(negedge clk); score_tick = 1'b0;
                repeat (16) @(posedge clk);
                #1;
            end
        end
    endtask

    function zero_score_pixel;
        input integer x, y;
        integer digit_x, digit_y;
        begin
            zero_score_pixel = 1'b0;
            if (x >= 16 && x < 92 && y >= 16 && y < 36) begin
                digit_x = (x - 16) % 16;
                digit_y = y - 16;
                zero_score_pixel = digit_x < 12 &&
                    (digit_y < 4 || digit_y >= 16 || digit_x < 4 || digit_x >= 8);
            end
        end
    endfunction

    initial begin
        fork
            begin : test_score
                @(negedge clk); score_rst = 1'b0;
                accrue_score(9);
                check(score_value == 16'd9 && score_digits == 20'h00009,
                      "Single-digit score must have four leading zeros");
                accrue_score(1);
                check(score_value == 16'd10 && score_digits == 20'h00010,
                      "Decimal score must carry from nine to ten");
                accrue_score(1224);
                check(score_value == 16'd1234 && score_digits == 20'h01234,
                      "All digit positions must match the accumulated scroll");
                accrue_score(55555);
                check(score_value == 16'd56789 && score_digits == 20'h56789,
                      "The displayed score must support five nonzero digits");
                repeat (20) @(posedge clk); #1;
                check(score_value == 16'd56789 && score_digits == 20'h56789,
                      "Scroll input must only accumulate on a movement tick");
                accrue_score(10000);
                check(score_value == 16'hFFFF && score_digits == 20'h65535,
                      "Score and display must saturate together");
                @(negedge clk); score_rst = 1'b1;
                @(posedge clk); #1;
                check(score_value == 16'd0 && score_digits == 20'h00000,
                      "Reset must clear the score display after saturation");
            end

            begin : test_platforms
                integer event_number;
                reg [255:0] seen_rng;
                seen_rng = 256'd0;
                repeat (2) @(posedge clk);
                @(negedge clk);
                platform_rst = 1'b0;
                check(xs == OPENING_X && ys[9:0] == OPENING_BOTTOM_Y && platforms.rng == 8'hA1,
                      "Reset must set the opening layout and the RNG seed");

                repeat (13) scroll_once(3);
                check(xs == OPENING_X && ys[9:0] == 479, "Platform recycled before reaching row 480");
                @(negedge clk); scroll = 5;
                @(posedge clk); #1;
                check(xs == OPENING_X && ys[9:0] == 479 && platforms.rng == 8'hA1,
                      "Platform and RNG state must hold without a movement tick");

                // Exercise every nonzero RNG state and multiple wraps of the slot ring.
                for (event_number = 0; event_number < 255; event_number = event_number + 1) begin
                    check(!seen_rng[platforms.rng] && platforms.rng != 8'd0,
                          "RNG state must be nonzero and unique within one period");
                    seen_rng[platforms.rng] = 1'b1;
                    recycle_and_check(event_number % PLATFORM_COUNT, 0);
                    if (event_number == 0)
                        check(xs[9:0] == 68 && ys[9:0] == 116 && platforms.rng == 8'h42,
                              "First recycle must match the fixed-seed reference");
                end
                check(seen_rng == ~256'd1 && platforms.rng == 8'hA1,
                      "The full RNG period must return to the reset seed");
                check(left_reflections > 0 && right_reflections > 0,
                      "The generated route must exercise both boundary reflections");

                @(negedge clk); platform_rst = 1'b1;
                @(posedge clk); #1;
                check(xs == OPENING_X && ys[9:0] == OPENING_BOTTOM_Y && platforms.rng == 8'hA1,
                      "Reset must restore the route and seed after recycling");
                @(negedge clk); platform_rst = 1'b0;
                repeat (13) scroll_once(3);
                recycle_and_check(0, 3);
                check(xs[9:0] == 68 && ys[9:0] == 119 && platforms.rng == 8'h42,
                      "Restart must reproduce the first platform and account for scroll overshoot");
            end

            begin : test_game_over
                integer frame_number, sample, expected_y;
                integer red_pixels, green_pixels, hsync_low, vsync_low;
                reg [PLATFORM_BUS_WIDTH-1:0] held_xs, held_ys;
                reg [9:0] held_player_x, held_player_y;

                repeat (4) @(posedge dut.pixel_clk); #1;
                check_opening;
                @(negedge clk); rst = 1'b0;
                #100;
                send_byte(8'h02);

                // The right command walks off the platform. The top edge reaches row 480 on frame five.
                for (frame_number = 1; frame_number <= 5; frame_number = frame_number + 1) begin
                    @(negedge vsync);
                    @(posedge dut.pixel_clk); #1;
                    expected_y = SPAWN_Y + frame_number * (frame_number - 1);
                    check(dut.player_x == SPAWN_X + 2 * frame_number && dut.player_y == expected_y,
                          "Right command or falling trajectory is incorrect");
                    check(dut.game_over == (frame_number == 5),
                          "Game Over must start when the player's top edge reaches row 480");
                end

                held_player_x = dut.player_x;
                held_player_y = dut.player_y;
                held_xs = dut.platform_x_bus;
                held_ys = dut.platform_y_bus;
                red_pixels = 0;
                green_pixels = 0;
                hsync_low = 0;
                vsync_low = 0;
                for (sample = 0; sample < 800 * 525; sample = sample + 1) begin
                    @(posedge dut.pixel_clk); #1;
                    check(dut.move_tick == 1'b0 && dut.game_over == 1'b1 && dut.move_right == 1'b1,
                          "Game movement must stay frozen while the right command remains held");
                    if (dut.pixel_x < 640 && dut.pixel_y < 480) begin
                        check({red, green, blue} ==
                              (zero_score_pixel(dut.pixel_x, dut.pixel_y) ? 12'h0F0 : 12'h600),
                              "Game Over must render the score over the dark red background");
                        if ({red, green, blue} == 12'h600)
                            red_pixels = red_pixels + 1;
                        if ({red, green, blue} == 12'h0F0)
                            green_pixels = green_pixels + 1;
                    end else begin
                        check({red, green, blue} == 12'h000, "RGB must be black during blanking");
                    end
                    if (!hsync) hsync_low = hsync_low + 1;
                    if (!vsync) vsync_low = vsync_low + 1;
                end
                check(green_pixels == 960 && red_pixels == 640 * 480 - 960 &&
                      hsync_low == 96 * 525 && vsync_low == 2 * 800,
                      "Game Over must keep generating a complete VGA frame with both sync pulses");
                check(dut.player_x == held_player_x && dut.player_y == held_player_y &&
                      dut.platform_x_bus == held_xs && dut.platform_y_bus == held_ys,
                      "Player and platform state changed after Game Over");

                @(negedge clk); rst = 1'b1;
                repeat (2) @(posedge dut.pixel_clk); #1;
                check_opening;
                check({red, green, blue} == 12'h000, "Restart must remove the red screen");
                @(negedge clk); rst = 1'b0;
                @(negedge vsync); #1;
                check(dut.move_prepare == 1'b1, "Restart must enable movement preparation again");
                @(posedge dut.pixel_clk); #1;
                check(dut.move_tick == 1'b1, "Restart must commit movement after preparation");
                @(posedge dut.pixel_clk); #1;
                check_opening;
            end
        join

        if (errors == 0)
            $display("PASS: game flow checked %0d recycles, score, Game Over, VGA frame and restart, 0 errors", recycles);
        else
            $display("FAIL: game flow checked %0d recycles, %0d errors", recycles, errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: game flow timed out");
        $finish;
    end
endmodule
