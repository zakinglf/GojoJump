`timescale 1ns / 1ps

module platform_collision #(
    parameter integer PLATFORM_COUNT = 10,
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLATFORM_INDEX_WIDTH = (PLATFORM_COUNT > 1) ? $clog2(PLATFORM_COUNT) : 1
)(
    input wire [9:0] next_player_x,
    input wire signed [15:0] feet_fp,
    input wire signed [15:0] next_feet_fp,
    input wire falling,

    input wire [PLATFORM_COUNT*10-1:0] platform_x_bus,
    input wire [PLATFORM_COUNT*10-1:0] platform_y_bus,
    input wire [PLATFORM_COUNT*10-1:0] platform_width_bus,
    input wire [PLATFORM_COUNT-1:0] platform_active,

    output wire landed,
    output wire [9:0] landing_y,
    output wire [PLATFORM_INDEX_WIDTH-1:0] landing_platform_index,
    output reg supported
);

    localparam integer LEAF_COUNT = 1 << $clog2(PLATFORM_COUNT);
    localparam integer NO_LANDING = 11'h7FF ;
    integer i;
    integer platform_x;
    integer platform_y;
    integer platform_width;
    reg signed [15:0] platform_top_fp;

    wire [10:0] landing_tree [1:2*LEAF_COUNT-1];
    wire [PLATFORM_INDEX_WIDTH-1:0] landing_index_tree [1:2*LEAF_COUNT-1];
    reg [10:0] landing_candidate [0:PLATFORM_COUNT - 1];

    genvar leaf, node;
    generate
        for(leaf = 0; leaf < LEAF_COUNT; leaf = leaf + 1) begin : gen_landing_leaf
            if(leaf < PLATFORM_COUNT) begin : gen_platform
                assign landing_tree[LEAF_COUNT + leaf] = landing_candidate[leaf];
                assign landing_index_tree[LEAF_COUNT + leaf] = leaf[PLATFORM_INDEX_WIDTH-1:0];
            end else begin : gen_padding
                assign landing_tree[LEAF_COUNT + leaf] = NO_LANDING;
                assign landing_index_tree[LEAF_COUNT + leaf] = 0;
            end
        end

        for(node = 1; node < LEAF_COUNT; node = node + 1) begin : gen_landing_node
            wire choose_left = (landing_tree[2*node] < landing_tree[2*node+1]);
            assign landing_tree[node] = choose_left ? landing_tree[2*node] : landing_tree[2*node+1];
            assign landing_index_tree[node] = choose_left ? landing_index_tree[2*node] : landing_index_tree[2*node+1];
        end
    endgenerate

    assign landed = (landing_tree[1] != NO_LANDING);
    assign landing_y = landed ? landing_tree[1][9:0] : 10'd0;
    assign landing_platform_index = landing_index_tree[1];
    // Detect landing on the highest crossed platform.
    always @(*) begin
        supported = 1'b0;

        platform_x = 0;
        platform_y = 0;
        platform_width = 0;
        platform_top_fp = 16'sd0;

        for (i = 0; i < PLATFORM_COUNT; i = i + 1) begin
            // Extract this platform's data.
            platform_x = platform_x_bus[i*10 +: 10];
            platform_y = platform_y_bus[i*10 +: 10];
            platform_width = platform_width_bus[i*10 +: 10];

            // Convert pixels to the same units as the player's feet.
            platform_top_fp = platform_y * 16;

            // Check support using the predicted horizontal position.
            if (platform_active[i] &&
                (next_player_x < platform_x + platform_width) &&
                (next_player_x + PLAYER_WIDTH > platform_x) &&
                (feet_fp == platform_top_fp)) begin
                supported = 1'b1;
            end           

            landing_candidate[i] = NO_LANDING;

            if (platform_active[i] && falling &&
                (next_player_x < platform_x + platform_width) &&
                (next_player_x + PLAYER_WIDTH > platform_x) &&
                (feet_fp <= platform_top_fp) &&
                (next_feet_fp >= platform_top_fp)) begin
                    landing_candidate[i] = {1'b0 ,platform_y[9:0]};
                end
        end
    end
endmodule
