`timescale 1ns / 1ps

module tb_parameters;
    localparam [99:0] DEFAULT_PLATFORM_X = {
        10'd480, 10'd520, 10'd560, 10'd520, 10'd480,
        10'd440, 10'd400, 10'd360, 10'd320, 10'd280
    };
    reg clk = 0;
    reg top_rst = 1;
    wire [3:0] dr, dg, db, cr, cg, cb;
    wire dh, dv, ch, cv;
    integer errors = 0, pixel_samples = 0;
    integer step, x, y, n, expected_camera, raw_y;
    integer scroll_sum = 0;
    top default_top (
        .clk(clk), .rst(top_rst), .rx(1'b1),
        .vga_red(dr), .vga_green(dg), .vga_blue(db),
        .vga_hsync(dh), .vga_vsync(dv)
    );
    top #(
        .PLAYER_WIDTH(11), .PLAYER_HEIGHT(13),
        .PLAYER_START_X(5), .PLAYER_START_Y(287), .PLAYER_MOVE_STEP(3),
        .GRAVITY_FP(16'sd8), .JUMP_VELOCITY_FP(-16'sd80), .SCROLL_LINE_Y(270),
        .PLATFORM_COUNT(3), .PLATFORM_WIDTH(45), .PLATFORM_HEIGHT(3),
        .PLATFORM_BOTTOM_Y(300), .PLATFORM_GAP(24),
        .PLATFORM_START_X(3), .PLATFORM_X_GAP(47)
    ) custom_top (
        .clk(clk), .rst(top_rst), .rx(1'b1),
        .vga_red(cr), .vga_green(cg), .vga_blue(cb),
        .vga_hsync(ch), .vga_vsync(cv)
    );
    always #5 clk = ~clk;
    wire pixel_clk = default_top.pixel_clk;

    reg rst = 1, tick = 0, left_key = 0, right_key = 0, jump = 0;
    reg move_tick = 0;
    always @(posedge pixel_clk)
        move_tick <= !rst && tick;

    wire [9:0] px, py, scroll;
    wire [29:0] xs, ys, widths;
    wire [2:0] active;
    player_ctrl #(
        .PLATFORM_COUNT(3), .PLAYER_WIDTH(11), .PLAYER_HEIGHT(13),
        .START_X(626), .START_Y(287), .MOVE_STEP(3),
        .GRAVITY_FP(16'sd8), .JUMP_VELOCITY_FP(-16'sd80), .SCROLL_LINE_Y(270)
    ) player (
        .pixel_clk(pixel_clk), .rst(rst), .move_prepare(tick), .move_tick(move_tick),
        .move_left(left_key), .move_right(right_key), .jump_pressed(jump),
        .platform_x_bus(xs), .platform_y_bus(ys), .platform_width_bus(widths),
        .platform_active(active), .player_x(px), .player_y(py), .scroll_dy(scroll),
        .fell_off_screen()
    );
    platform_ctrl #(
        .PLATFORM_COUNT(3), .INITIAL_BOTTOM_Y(300), .INITIAL_Y_GAP(24),
        .INITIAL_WIDTH(640), .INITIAL_X(0), .INITIAL_X_GAP(0)
    ) platforms (
        .pixel_clk(pixel_clk), .rst(rst), .move_prepare(tick), .move_tick(move_tick), .scroll_dy(scroll),
        .platform_x_bus(xs), .platform_y_bus(ys), .platform_width_bus(widths),
        .platform_active(active),
        .platform_reward_claimed(1'b0), .platform_reward_index(2'd0)
    );
    reg [9:0] sample_x = 0, sample_y = 0;
    reg video_on = 1;
    wire [3:0] rr, rg, rb;
    renderer #(
        .PLATFORM_COUNT(3), .PLAYER_WIDTH(11), .PLAYER_HEIGHT(13), .PLATFORM_HEIGHT(3)
    ) draw (
        .pixel_x(sample_x), .pixel_y(sample_y), .video_on(video_on), .game_over(1'b0), .heal_scene_on(1'b0),
        .purple_scene_on(1'b0),
        .challenger_scene_on(1'b0),
        .score_digits(20'h00000), .hp(3'd5),
        .purple_active(1'b0), .purple_x(10'd0), .purple_y(12'sd0),
        .player_x(px), .player_y(py), .platform_x_bus(xs), .platform_y_bus(ys),
        .platform_width_bus(widths), .platform_active(active), .platform_reward_ready(3'b000),
        .enemy_x_bus(30'd0), .enemy_y_bus(33'd0), .enemy_active(3'd0),
        .bullet_x_bus(144'd0), .bullet_y_bus(144'd0), .bullet_active(12'd0),
        .red(rr), .green(rg), .blue(rb)
    );

    task fail;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 12) $display("ERROR at %0t: %0s", $time, message);
        end
    endtask
    task reset_player;
        begin
            @(negedge pixel_clk);
            rst = 1; tick = 0; jump = 0; left_key = 0; right_key = 0;
            repeat (2) @(posedge pixel_clk);
            #1;
            if (px !== 10'd626 || py !== 10'd287 ||
                xs !== 30'd0 || ys !== {10'd252,10'd276,10'd300} || active !== 3'b111 ||
                widths !== {10'd640,10'd640,10'd640})
                fail("Custom spawn, dimensions, count, gap, or platform width was not applied");
            scroll_sum = 0;
            @(negedge pixel_clk); rst = 0;
        end
    endtask
    task move_once;
        input l, r, j;
        integer before_x, before_y, before_vy;
        reg [29:0] before_platforms;
        begin
            @(negedge pixel_clk);
            left_key = l; right_key = r; jump = j; tick = 1;
            @(posedge pixel_clk); #1;
            scroll_sum = scroll_sum + scroll;
            @(negedge pixel_clk); tick = 0; jump = 0;
            @(posedge pixel_clk); #1;
            before_x = px; before_y = $signed(player.y_fp);
            before_vy = $signed(player.vy_fp); before_platforms = ys;
            repeat (2) begin
                @(posedge pixel_clk); #1;
                if (px !== before_x || $signed(player.y_fp) !== before_y ||
                    $signed(player.vy_fp) !== before_vy || ys !== before_platforms)
                    fail("Custom movement and scrolling must hold between movement ticks");
            end
        end
    endtask
    task sample_color;
        input integer sx, sy;
        input [11:0] expected;
        begin
            sample_x = sx; sample_y = sy; #1;
            if ({rr,rg,rb} !== expected) fail("Custom player/platform drawing dimensions mismatch");
            pixel_samples = pixel_samples + 1;
        end
    endtask

    function [11:0] expected_image;
        input integer sx, sy, custom;
        integer i, ox, oy;
        begin
            expected_image = 12'h000;
            if (sx < 640 && sy < 480) begin
                for (i = 0; i < (custom ? 3 : 10); i = i + 1) begin
                    ox = custom ? (3 + i*47) : DEFAULT_PLATFORM_X[i*10 +: 10];
                    oy = custom ? (300 - i*24) : (440 - i*30);
                    if (sx >= ox && sx < ox + (custom ? 45 : 64) &&
                        sy >= oy && sy < oy + (custom ? 3 : 6))
                        expected_image = 12'h888;
                end
                if (sx >= (custom ? 5 : 304) && sx < (custom ? 16 : 320) &&
                    sy >= (custom ? 287 : 424) && sy < (custom ? 300 : 440))
                    expected_image = 12'h0F0;
            end
        end
    endfunction

    initial begin
        repeat (4) @(posedge pixel_clk);
        #1;
        if (default_top.player_x !== 10'd304 || default_top.player_y !== 10'd424 ||
            default_top.platform_x_bus !== DEFAULT_PLATFORM_X ||
            custom_top.player_x !== 10'd5 || custom_top.player_y !== 10'd287 ||
            custom_top.platform_y_bus !== {10'd252,10'd276,10'd300} ||
            custom_top.platform_x_bus !== {10'd97,10'd50,10'd3} ||
            custom_top.platform_width_bus !== {10'd45,10'd45,10'd45})
            fail("Top-level parameter values did not reach the reset state and platform layout");

        reset_player;
        sample_color(626,287,12'h0F0);
        sample_color(636,299,12'h0F0);
        sample_color(637,287,12'h000);
        sample_color(626,300,12'h888);
        sample_color(0,302,12'h888);
        sample_color(0,303,12'h000);
        video_on = 0; sample_color(626,287,12'h000); video_on = 1;

        move_once(0,1,0);
        repeat (3) move_once(0,1,0);
        if (px !== 10'd629) fail("Width 11 must produce right boundary 629");
        repeat (210) move_once(1,0,0);
        if (px !== 10'd0 || py !== 10'd287)
            fail("Step three must clamp a partial left step without underflow");

        reset_player;
        move_once(0,0,1);
        if ($signed(player.vy_fp) !== -80) fail("Custom signed jump velocity was not applied");
        for (n = 1; n <= 10; n = n + 1) begin
            move_once(0,0,0);
            // Closed-form trajectory before camera compensation: y0+n*v0+g*n*(n-1)/2.
            raw_y = 287*16 - n*80 + 8*n*(n-1)/2;
            expected_camera = (raw_y < 270*16) ? (270*16 - raw_y + 15)/16 : 0;
            if ($signed(player.y_fp) !== raw_y + expected_camera*16 ||
                $signed(player.vy_fp) !== -80 + n*8 ||
                scroll_sum != expected_camera || ys[9:0] !== 300 + expected_camera)
                fail("Custom gravity, jump, scroll line, or synchronous platform scrolling mismatch");
        end
        if (scroll_sum != 11 || $signed(player.y_fp) != 4328)
            fail("Custom jump apex must be 270.5 screen pixels after 11 pixels of scrolling");
        repeat (20) move_once(0,0,0);
        if (py !== 10'd274 || $signed(player.vy_fp) !== 0 || ys[19:10] !== 10'd287)
            fail("Custom height must align the feet to the scrolled upper platform");

        // Scan both actual top-level VGA outputs before the first movement tick.
        @(negedge clk); top_rst = 0;
        for (step = 1; step <= 800*480; step = step + 1) begin
            @(posedge pixel_clk); #1;
            x = step % 800; y = step / 800;
            if ({dr,dg,db} !== expected_image(x,y,0) ||
                {cr,cg,cb} !== expected_image(x,y,1))
                fail("Actual top-level VGA output does not match its parameterized image");
            pixel_samples = pixel_samples + 2;
        end
        if (errors == 0)
            $display("PASS: parameters checked 3 configurations, %0d pixel samples, 0 errors", pixel_samples);
        else
            $display("FAIL: parameters checked 3 configurations, %0d pixel samples, %0d errors", pixel_samples, errors);
        $finish;
    end
    initial begin
        #20_000_000;
        $display("FAIL: parameter checks timed out");
        $finish;
    end
endmodule
