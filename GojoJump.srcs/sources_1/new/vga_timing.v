`timescale 1ns / 1ps

module vga_timing(
    input pixel_clk,
    input rst,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y,
    output wire video_on,
    output wire hsync,
    output wire vsync
    );

    localparam integer H_TOTAL = 800;
    localparam integer V_TOTAL = 525;

    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT = 16;
    localparam integer H_SYNC = 96;

    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT = 10;
    localparam integer V_SYNC = 2;

    reg [9:0] v_cnt;
    reg [9:0] h_cnt;

    always @(posedge pixel_clk) begin
        if(rst)
            h_cnt <= 10'b0;
        else if(h_cnt == H_TOTAL - 1)
            h_cnt <= 10'b0;
        else 
            h_cnt <= h_cnt + 1;
    end

    always @(posedge pixel_clk) begin
        if(rst)
            v_cnt <= 10'd0;
        else if(h_cnt == H_TOTAL - 1) begin
            if(v_cnt == V_TOTAL - 1)
                v_cnt <= 10'd0; 
            else
                v_cnt <= v_cnt + 10'd1;
        end 
    end

    assign hsync = !(
        h_cnt >= H_ACTIVE + H_FRONT &&
        h_cnt < H_ACTIVE + H_FRONT + H_SYNC
    );
    assign vsync = !(
        v_cnt >= V_ACTIVE + V_FRONT &&
        v_cnt < V_ACTIVE + V_FRONT + V_SYNC
    );
    assign video_on = (h_cnt < H_ACTIVE)&&(v_cnt < V_ACTIVE);
    
    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;
    
endmodule
