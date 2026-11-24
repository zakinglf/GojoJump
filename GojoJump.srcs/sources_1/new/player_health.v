`timescale 1ns / 1ps

module player_health (
    input  wire       pixel_clk,
    input  wire       rst,
    input  wire       hit_tick,
    input  wire       hit_player,
    input  wire       black_flash_hit,
    input  wire       platform_reward_request,
    input  wire       heal_request,
    input  wire       domain_request,
    input  wire       purple_request,
    output reg  [2:0] hp,
    output reg  [2:0] cursed_energy,
    output wire       invincible,
    output reg        heal_applied,
    output wire       domain_fire,
    output wire       purple_fire,
    output wire       platform_reward_claimed
);
    localparam [2:0] MAX_HP = 3'd5;
    localparam [2:0] MAX_CURSED_ENERGY = 3'd6;
    localparam [2:0] DOMAIN_COST = 3'd6;
    localparam [2:0] PURPLE_COST = 3'd4;
    localparam [3:0] INVINCIBLE_FRAMES = 4'd10;
    localparam [2:0] INITIAL_CURSED_ENERGY = 3'd2;

    reg [3:0] invincible_left;
    wire spend_energy = !invincible && hit_player && (cursed_energy != 1'd0);
    wire [2:0] energy_after_hit = spend_energy ? cursed_energy - 3'd1 : cursed_energy;
    assign domain_fire = !rst && hit_tick && (hp != 3'd0) &&
                         domain_request && (energy_after_hit == DOMAIN_COST);
    wire [2:0] energy_after_domain = domain_fire ? 3'd0 : energy_after_hit;
    assign purple_fire = !rst && hit_tick && (hp != 3'd0) &&
                         purple_request && (energy_after_domain >= PURPLE_COST);
    wire [2:0] energy_after_purple = purple_fire ? energy_after_domain - PURPLE_COST
                                                 : energy_after_domain;
    wire heal_now = heal_request && !purple_fire && (hp < MAX_HP) &&
                    (energy_after_purple != 3'd0);
    wire [2:0] energy_after_heal = heal_now ? energy_after_purple - 3'd1
                                          : energy_after_purple;

    wire [2:0] energy_after_black_flash =
        (black_flash_hit && energy_after_heal < MAX_CURSED_ENERGY)
        ? energy_after_heal + 3'd1 : energy_after_heal;
    assign platform_reward_claimed = !rst && hit_tick && (hp != 3'd0) &&
                                     platform_reward_request &&
                                     (energy_after_black_flash < MAX_CURSED_ENERGY);

    // Start at full health when the FPGA is configured.
    initial hp = MAX_HP;

    assign invincible = (invincible_left != 4'd0);

    always @(posedge pixel_clk) begin
        heal_applied <= 1'b0;
        if (rst) begin
            hp              <= MAX_HP;
            invincible_left <= 4'd0;
            cursed_energy   <= INITIAL_CURSED_ENERGY;
        end else if (hit_tick && hp != 3'd0) begin
            if (invincible) begin
                invincible_left <= invincible_left - 4'd1;
            end else if (hit_player) begin
                if (cursed_energy == 3'd0)
                    hp <= hp - 3'd1;

                invincible_left <= INVINCIBLE_FRAMES;
            end

            if (heal_now) begin
                hp <= MAX_HP;
                heal_applied <= 1'b1;
            end

            cursed_energy <= platform_reward_claimed ? energy_after_black_flash + 3'd1
                                                    : energy_after_black_flash;
        end
    end
endmodule
