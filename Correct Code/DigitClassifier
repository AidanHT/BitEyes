module DigitClassifier(
    input clk,
    input reset,        // Right click or Global Reset
    input enable,       // Active drawing (Left click)
    input [8:0] x,
    input [7:0] y,
    output reg [6:0] hex_output
);

    // =========================================================================
    // 1. DIRECTION TRACKING
    // =========================================================================
    
    localparam DIR_NONE = 3'd0;
    localparam DIR_UP   = 3'd1;
    localparam DIR_DOWN = 3'd2;
    localparam DIR_LEFT = 3'd3;
    localparam DIR_RIGHT= 3'd4;

    reg [8:0] prev_x;
    reg [7:0] prev_y;
    reg has_started;

    // History Buffer: Increased to 8 to capture long sequences (like Digit 8)
    // moves[0] is the most recent move.
    reg [2:0] moves [7:0]; 
    reg [3:0] move_count; // Expanded counter for 8 slots

    // Threshold (squared): ~15 pixels movement required to register a new segment
    integer DIST_THRESHOLD_SQ = 15 * 15; 

    always @(posedge clk) begin
        if (reset) begin
            prev_x <= 0;
            prev_y <= 0;
            has_started <= 0;
            
            // Clear history
            moves[0] <= DIR_NONE; moves[1] <= DIR_NONE; moves[2] <= DIR_NONE; 
            moves[3] <= DIR_NONE; moves[4] <= DIR_NONE; moves[5] <= DIR_NONE;
            moves[6] <= DIR_NONE; moves[7] <= DIR_NONE;
            move_count <= 0;
        end
        else if (enable) begin
            if (!has_started) begin
                prev_x <= x;
                prev_y <= y;
                has_started <= 1;
            end
            else begin
                reg [17:0] dx, dy, dist_sq;
                reg [2:0] current_dir;
                
                dx = (x > prev_x) ? (x - prev_x) : (prev_x - x);
                dy = (y > prev_y) ? (y - prev_y) : (prev_y - y);
                dist_sq = (dx*dx) + (dy*dy);

                if (dist_sq > DIST_THRESHOLD_SQ) begin
                    // Determine direction
                    if (dx > dy) begin
                        current_dir = (x > prev_x) ? DIR_RIGHT : DIR_LEFT;
                    end
                    else begin
                        current_dir = (y > prev_y) ? DIR_DOWN : DIR_UP;
                    end

                    // Only register if direction CHANGED
                    if (current_dir != moves[0]) begin
                        // Shift history (Manually unrolled for Verilog compatibility)
                        moves[7] <= moves[6];
                        moves[6] <= moves[5];
                        moves[5] <= moves[4];
                        moves[4] <= moves[3];
                        moves[3] <= moves[2];
                        moves[2] <= moves[1];
                        moves[1] <= moves[0];
                        moves[0] <= current_dir;
                        
                        if (move_count < 8) move_count <= move_count + 1;
                        
                        prev_x <= x;
                        prev_y <= y;
                    end
                end
            end
        end
    end

    // =========================================================================
    // 2. PATTERN MATCHING
    // =========================================================================
    
    // 7-segment encoding (Active Low: 0 is ON)
    // 0: 1000000
    // 1: 1111001
    // 2: 0100100
    // 3: 0110000
    // 4: 0011001
    // 5: 0010010
    // 6: 0000010
    // 7: 1111000
    // 8: 0000000
    // 9: 0010000

    always @(*) begin
        hex_output = 7'b1111111; // Default Blank

        if (move_count > 0) begin
            case (moves[0]) // Check the LAST move made
                
                // -------------------------------------------------------
                // ENDS IN UP (Candidates: 0, 8)
                // -------------------------------------------------------
                DIR_UP: begin
                    // 0: Left -> Down -> Right -> Up
                    //    History: [Up, Right, Down, Left...]
                    // 8: ... Left -> Up -> Right -> Up
                    //    History: [Up, Right, Up, Left...]
                    
                    if (moves[1] == DIR_RIGHT && moves[2] == DIR_UP)
                        hex_output = 7'b0000000; // "8" (End sequence Up, Right, Up)
                    else if (moves[1] == DIR_RIGHT && moves[2] == DIR_DOWN) 
                        hex_output = 7'b1000000; // "0" (End sequence Up, Right, Down)
                    else 
                        hex_output = 7'b1000000; // Default to 0 for loops ending up
                end

                // -------------------------------------------------------
                // ENDS IN DOWN (Candidates: 1, 4, 7, 9)
                // -------------------------------------------------------
                DIR_DOWN: begin
                    // 1: Down
                    // 4: Down -> Right -> Up -> Down
                    // 7: Right -> Down
                    // 9: Left -> Up -> Right -> Down
                    
                    if (moves[1] == DIR_UP && moves[2] == DIR_RIGHT) 
                        hex_output = 7'b0011001; // "4" (Down, Up, Right...)
                    else if (moves[1] == DIR_RIGHT && moves[2] == DIR_UP) 
                        hex_output = 7'b0010000; // "9" (Down, Right, Up...)
                    else if (moves[1] == DIR_RIGHT) 
                        hex_output = 7'b1111000; // "7" (Down, Right...)
                    else 
                        hex_output = 7'b1111001; // "1" (Just Down or unknown)
                end

                // -------------------------------------------------------
                // ENDS IN RIGHT (Candidates: 2)
                // -------------------------------------------------------
                DIR_RIGHT: begin
                    // 2: Right -> Down -> Left -> Down -> Right
                    //    History: [Right, Down, Left, Down, Right]
                    
                    if (moves[1] == DIR_DOWN && moves[2] == DIR_LEFT)
                        hex_output = 7'b0100100; // "2"
                end

                // -------------------------------------------------------
                // ENDS IN LEFT (Candidates: 3, 5, 6)
                // -------------------------------------------------------
                DIR_LEFT: begin
                    // 3: ... Right -> Down -> Left (moves[3] should be Right)
                    // 5: ... Down -> Left (moves[3] should be Down)
                    // 6: Down -> Right -> Up -> Left
                    
                    if (moves[1] == DIR_UP && moves[2] == DIR_RIGHT && moves[3] == DIR_DOWN && moves[4] == DIR_LEFT) 
                        hex_output = 7'b0000010; // "6" (Left, Up, Right...)
                    else if (moves[1] == DIR_DOWN && moves[2] == DIR_RIGHT) begin
                        // Both 3 and 5 end in Left, Down, Right. 
                        // Check moves[3]
                        if (moves[3] == DIR_LEFT) 
                            hex_output = 7'b0110000; // "3" (Left, Down, Right, Left...)
                        else 
                            hex_output = 7'b0010010; // "5" (Left, Down, Right, Down...)
                    end
                    else if (moves[1] == DIR_DOWN) 
                        hex_output = 7'b0010010; // "5" loose match
                end

                default: hex_output = 7'b1111111;
            endcase
        end
    end

endmodule
