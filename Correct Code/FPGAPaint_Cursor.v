module BitEyesCanvas (
    input [9:0] SW,
    input [3:0] KEY,
    input CLOCK_50,
    
    output [9:0] LEDR,

    inout PS2_CLK,
    inout PS2_DAT,
    
    // VGA outputs
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output VGA_HS,
    output VGA_VS,
    output VGA_BLANK_N,
    output VGA_SYNC_N,
    output VGA_CLK,
    
    // HEX displays
    output [6:0] HEX5,
    output [6:0] HEX4,
    output [6:0] HEX3,
    output [6:0] HEX2,
    output [6:0] HEX1,
    output [6:0] HEX0
);

    parameter SCREEN_WIDTH = 320;
    parameter SCREEN_HEIGHT = 240;

    // Color definitions (9-bit: 3 bits R, 3 bits G, 3 bits B)
    parameter COLOR_BACKGROUND = 9'b000_000_000; // Black background
    parameter COLOR_DRAW = 9'b111_111_111;       // White drawing color
    parameter COLOR_ERASE = 9'b000_000_000;      // Black (for erasing)
    parameter COLOR_CANVAS = 9'b111_111_111;     // White canvas background
    parameter COLOR_CURSOR = 9'b111_000_000;     // Red cursor color

    // FOR COLORS
    wire [8:0] pen_colors;
    assign pen_colors = {SW[9], SW[9], SW[9], 
                         SW[9], SW[9], SW[9], 
                         SW[9], SW[9], SW[9]};

    wire reset;
    assign reset = ~KEY[0];

    // Mode Selection: 0 = Shape, 1 = Digit
    wire mode_digit_detect;
    assign mode_digit_detect = SW[1]; 

    wire [7:0] ps2_received_data;
    wire ps2_received_data_en;

    wire mouse_left_button;
    wire mouse_right_button;
    wire mouse_middle_button;
    wire [8:0] mouse_delta_x; // First bit is the direction of movement
    wire [8:0] mouse_delta_y;
    wire mouse_data_valid;

    // ============================================
    // MOUSE POSITION ACCUMULATORS (Precision Mode)
    // ============================================
    // To slow down the mouse, we use fixed-point arithmetic.
    // The top bits are the integer pixel position.
    // The bottom 2 bits are the fractional part.
    // This effectively divides the mouse speed by 4 (2^2).
    reg [10:0] mouse_x_accum; // 9 bits Integer + 2 bits Fraction
    reg [9:0]  mouse_y_accum; // 8 bits Integer + 2 bits Fraction

    // Helper wires to get the actual integer pixel coordinate
    wire [8:0] mouse_x_pos = mouse_x_accum[10:2];
    wire [7:0] mouse_y_pos = mouse_y_accum[9:2];

    wire drawing_enabled;
    assign drawing_enabled = SW[0];

    // VGA drawing signals
    reg [8:0] vga_color;
    reg [8:0] vga_x;  // 9 bits for X (0-319)
    reg [7:0] vga_y;  // 8 bits for Y (0-239)
    reg vga_write;

    // Drawing state
    wire drawing_active;
    assign drawing_active = drawing_enabled && mouse_left_button;

    // ============================================
    // BACKGROUND IMAGE ROM
    // ============================================
    wire [8:0] bg_rom_q;
    
    // Address calculator for 320x240: Address = y * 320 + x
    reg [16:0] clear_address; 
    
    BackgroundROM bg_rom (
        .clock(CLOCK_50),
        .address(clear_address),
        .q(bg_rom_q)
    );

    // ============================================
    // SCREEN MANAGER (CLEARING / RESTORING)
    // ============================================
    localparam IDLE = 2'b00;
    localparam CLEARING_WHITE = 2'b01; // Wiping screen to white
    localparam RESTORING_IMG  = 2'b10; // Writing image back to screen

    reg [1:0] screen_state;
    reg [8:0] scan_x;  
    reg [7:0] scan_y;  
    reg screen_job_active; // 1 if we are currently wiping/restoring
    
    // Track the current visual state of the screen
    // 1 = Screen is White (Ready for drawing)
    // 0 = Screen has Background Image
    reg is_screen_white; 

    always @(posedge CLOCK_50) begin
        if (reset) begin
            // Initialize based on switch position
            if (drawing_enabled) begin
                screen_state <= CLEARING_WHITE;
                is_screen_white <= 1'b1; // Assume white after this job
            end
            else begin
                screen_state <= RESTORING_IMG;
                is_screen_white <= 1'b0; // Assume image after this job
            end
            
            scan_x <= 0; scan_y <= 0; clear_address <= 0;
            screen_job_active <= 1;
        end
        else begin
            if (screen_state == IDLE) begin
                // ROBUST STATE CHECK:
                // Check for Mismatch between Switch and Screen State
                
                // CASE 1: Switch is ON (Draw), but Screen is Image -> WIPE IT
                if (drawing_enabled && !is_screen_white) begin
                    screen_state <= CLEARING_WHITE;
                    scan_x <= 0; scan_y <= 0; clear_address <= 0;
                    screen_job_active <= 1;
                end
                // CASE 2: Switch is OFF (View), but Screen is White -> RESTORE IT
                else if (!drawing_enabled && is_screen_white) begin
                    screen_state <= RESTORING_IMG;
                    scan_x <= 0; scan_y <= 0; clear_address <= 0;
                    screen_job_active <= 1;
                end
                else begin
                    screen_job_active <= 0;
                end
            end
            else begin
                // WORKER LOOP: Iterate through all pixels
                screen_job_active <= 1;
                
                // Increment Address for next cycle
                clear_address <= clear_address + 1;

                if (scan_x == SCREEN_WIDTH - 1) begin
                    scan_x <= 0;
                    if (scan_y == SCREEN_HEIGHT - 1) begin
                        scan_y <= 0;
                        clear_address <= 0; 
                        
                        // JOB COMPLETE: Update status register
                        if (screen_state == CLEARING_WHITE) 
                            is_screen_white <= 1'b1;
                        else 
                            is_screen_white <= 1'b0;
                            
                        screen_state <= IDLE; 
                    end
                    else begin
                        scan_y <= scan_y + 1;
                    end
                end
                else begin
                    scan_x <= scan_x + 1;
                end
            end
        end
    end

    // ============================================
    // MOUSE MOVEMENT LOGIC
    // ============================================
    // Latch movement indicators
    reg move_left_latched, move_right_latched, move_up_latched, move_down_latched;
    wire move_left_detect = mouse_data_valid && (mouse_delta_x[8] == 1) && (mouse_delta_x[7:0] != 0);
    wire move_right_detect = mouse_data_valid && (mouse_delta_x[8] == 0) && (mouse_delta_x[7:0] != 0);
    wire move_up_detect = mouse_data_valid && (mouse_delta_y[8] == 1) && (mouse_delta_y[7:0] != 0);
    wire move_down_detect = mouse_data_valid && (mouse_delta_y[8] == 0) && (mouse_delta_y[7:0] != 0);

    reg [7:0] corrected_delta_x;
    reg [7:0] corrected_delta_y;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            move_left_latched <= 1'b0;
            move_right_latched <= 1'b0;
            move_up_latched <= 1'b0;
            move_down_latched <= 1'b0;
        end
        else begin
            if (move_left_detect) 
                move_left_latched <= 1'b1;
            if (move_right_detect) 
                move_right_latched <= 1'b1;
            if (move_up_detect) 
                move_up_latched <= 1'b1;
            if (move_down_detect) 
                move_down_latched <= 1'b1;
        end
    end

    // PS2 Instantiation
    PS2_Controller #(.INITIALIZE_MOUSE(1)) ps2_controller_inst (
        .CLOCK_50(CLOCK_50), 
        .reset(reset), 
        .the_command(8'h00), 
        .send_command(1'b0),
        .PS2_CLK(PS2_CLK), 
        .PS2_DAT(PS2_DAT),
        .received_data(ps2_received_data), 
        .received_data_en(ps2_received_data_en)
    );

    PS2_Mouse_Parser mouse_parser_inst (
        .CLOCK_50(CLOCK_50), 
        .reset(reset),
        .ps2_received_data(ps2_received_data), 
        .ps2_received_data_en(ps2_received_data_en),
        .left_button(mouse_left_button), 
        .right_button(mouse_right_button), 
        .middle_button(mouse_middle_button),
        .mouse_delta_x(mouse_delta_x), 
        .mouse_delta_y(mouse_delta_y), 
        .mouse_data_valid(mouse_data_valid)
    );

    // Mouse Position Update Logic (With Precision/Slow-down)
    always @(posedge CLOCK_50) begin
        if (reset) begin
            // Initialize accumulators to center screen
            // Shift left by 2 to set the integer part
            mouse_x_accum <= { (SCREEN_WIDTH/2), 2'b00 };
            mouse_y_accum <= { (SCREEN_HEIGHT/2), 2'b00 };
        end
        else begin
            if (mouse_data_valid) begin
                // Handle Negative/Positive Encoding for X
                if (mouse_delta_x[7:0] >= 128) 
                    corrected_delta_x = 8'd256 - mouse_delta_x[7:0];
                else 
                    corrected_delta_x = mouse_delta_x[7:0];
                    
                // Handle Negative/Positive Encoding for Y
                if (mouse_delta_y[7:0] >= 128) 
                    corrected_delta_y = 8'd256 - mouse_delta_y[7:0];
                else 
                    corrected_delta_y = mouse_delta_y[7:0];
                
                // Update X Accumulator
                if (corrected_delta_x != 0) begin
                    if (mouse_delta_x[7:0] < 128) begin // Positive (Right)
                        if (mouse_x_accum + corrected_delta_x < {9'd320, 2'b00})
                            mouse_x_accum <= mouse_x_accum + corrected_delta_x;
                        else
                            mouse_x_accum <= {9'd319, 2'b11}; // Max X
                    end
                    else begin // Negative (Left)
                        if (mouse_x_accum >= corrected_delta_x)
                            mouse_x_accum <= mouse_x_accum - corrected_delta_x;
                        else
                            mouse_x_accum <= {9'd0, 2'b00}; // Min X
                    end
                end
                
                // Update Y Accumulator
                if (corrected_delta_y != 0) begin
                    if (mouse_delta_y[7:0] > 128) begin // Positive (Down)
                        if (mouse_y_accum + corrected_delta_y < {8'd240, 2'b00})
                            mouse_y_accum <= mouse_y_accum + corrected_delta_y;
                        else
                            mouse_y_accum <= {8'd239, 2'b11}; // Max Y
                    end
                    else begin // Negative (Up)
                        if (mouse_y_accum >= corrected_delta_y)
                            mouse_y_accum <= mouse_y_accum - corrected_delta_y;
                        else
                            mouse_y_accum <= {8'd0, 2'b00}; // Min Y
                    end
                end
            end
        end
    end

    // ============================================
    // DRAWING LOGIC (With 4x4 Brush)
    // ============================================

    // Counter to cycle through 64 offsets (8x8 block for Eraser)
    reg [5:0] brush_counter;
    always @(posedge CLOCK_50) begin
        brush_counter <= brush_counter + 1;
    end

    // Calculate offsets for 4x4 Brush (0-3, 0-3)
    wire [8:0] brush_4x4_x = {7'b0, brush_counter[1:0]};
    wire [7:0] brush_4x4_y = {6'b0, brush_counter[3:2]};

    // Calculate offsets for 8x8 Eraser (0-7, 0-7)
    wire [8:0] brush_8x8_x = {6'b0, brush_counter[2:0]};
    wire [7:0] brush_8x8_y = {5'b0, brush_counter[5:3]};

    always @(posedge CLOCK_50) begin
        if (reset) begin
            vga_x <= 9'd0;
            vga_y <= 8'd0;
            vga_color <= COLOR_CANVAS;
            vga_write <= 1'b0;
        end
        else begin
            // Default: no write
            vga_write <= 1'b0;
            
            // Priority 1: Screen Manager (Wiping or Restoring Image)
            if (screen_job_active) begin
                vga_write <= 1'b1;
                vga_x <= scan_x;
                vga_y <= scan_y;
                
                if (screen_state == CLEARING_WHITE)
                    vga_color <= COLOR_CANVAS; // White
                else
                    vga_color <= bg_rom_q; // From ROM Image
            end
            // Priority 2: User Drawing (Only if SW[0] is ON and not clearing)
            else if (drawing_enabled) begin
                if (mouse_right_button) begin
                    // ERASER: Uses 8x8 Brush
                    vga_write <= 1'b1;
                    vga_x <= mouse_x_pos + brush_8x8_x;
                    vga_y <= mouse_y_pos + brush_8x8_y;
                    vga_color <= COLOR_DRAW; 
                end
                else if (mouse_left_button) begin
                    // DRAWING: Uses 4x4 Brush
                    vga_write <= 1'b1;
                    vga_x <= mouse_x_pos + brush_4x4_x;
                    vga_y <= mouse_y_pos + brush_4x4_y;
                    vga_color <= pen_colors;
                end
            end
        end
    end

    // VGA Adapter
    // Note: We use white as default background image here since we handle the ROM manually
    vga_adapter #(
        .RESOLUTION("320x240"),
        .COLOR_DEPTH(9),
        .BACKGROUND_IMAGE("./white_320_240_9.mif")
    ) vga_adapter_inst (
        .resetn(~reset),
        .clock(CLOCK_50),
        .color(vga_color),
        .x(vga_x),
        .y(vga_y),
        .write(vga_write),

        .overlay_enable(1'b1),
        .overlay_x(mouse_x_pos),
        .overlay_y(mouse_y_pos),
        .overlay_color(COLOR_CURSOR),

        .VGA_R(VGA_R), 
        .VGA_G(VGA_G), 
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), 
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N), 
        .VGA_SYNC_N(VGA_SYNC_N), 
        .VGA_CLK(VGA_CLK)
    );

    // ============================================
    // SHAPE AND DIGIT DETECTION
    // ============================================

    // RESET LOGIC:
    // The detector resets if:
    // 1. System Reset (~KEY[0])
    // 2. Screen is Clearing/Restoring (New canvas state)
    // 3. RIGHT CLICK (Eraser) is held (allows starting a new shape)
    // 4. KEY[1] is pressed (manual reset button for detector)
    wire classifier_reset = reset || screen_job_active || mouse_right_button || ~KEY[1];

    // ENABLE LOGIC:
    // Only enabled when drawing Black pixels and not currently wiping the screen.
    wire classifier_enable = drawing_enabled && vga_write && !screen_job_active && (vga_color == 9'b000_000_000);
    
    // Outputs for the mux
    wire [6:0] shape_hex;
    wire [6:0] digit_hex;

    // 1. Shape Classifier
    ShapeClassifier detector (
        .clk(CLOCK_50),
        .reset(classifier_reset),
        .enable(classifier_enable),
        .x(vga_x),
        .y(vga_y),
        .hex_output(shape_hex)
    );
    
    // 2. Digit Classifier
    DigitClassifier digit_detector (
        .clk(CLOCK_50),
        .reset(classifier_reset),
        .enable(classifier_enable),
        .x(vga_x),
        .y(vga_y),
        .hex_output(digit_hex)
    );
    
    // Output MUX: SW[1] selects between Digit (1) and Shape (0)
    assign HEX0 = (mode_digit_detect) ? digit_hex : shape_hex;

    // ============================================
    // DEBUG DISPLAYS
    // ============================================
    // LED Status
    assign LEDR[0] = drawing_enabled; 
    assign LEDR[1] = mode_digit_detect; // LED 1 ON = Digit Mode, OFF = Shape Mode
    assign LEDR[2] = mouse_left_button; 
    assign LEDR[3] = mouse_right_button;
    assign LEDR[4] = move_left_latched; 
    assign LEDR[5] = move_up_latched; 
    assign LEDR[6] = move_down_latched; 
    assign LEDR[7] = move_right_latched; 
    assign LEDR[8] = screen_job_active; 
    assign LEDR[9] = 1'b0; 

    // Using integer positions for display now
    wire [7:0] delta_x_magnitude = corrected_delta_x;
    wire [7:0] delta_y_magnitude = corrected_delta_y;

    // (Hex display logic kept same as previous, just compacted for brevity)
    reg [3:0] dx_h, dx_t, dx_o;
    reg [3:0] dy_h, dy_t, dy_o;

    always @(*) begin
        if (delta_x_magnitude >= 200) begin 
            dx_h = 2; 
            dx_t = (delta_x_magnitude - 200) / 10; 
            dx_o = (delta_x_magnitude - 200) % 10; 
        end
        else if (delta_x_magnitude >= 100) begin 
            dx_h = 1; 
            dx_t = (delta_x_magnitude - 100) / 10; 
            dx_o = (delta_x_magnitude - 100) % 10; 
        end
        else begin 
            dx_h = 0; 
            dx_t = delta_x_magnitude / 10; 
            dx_o = delta_x_magnitude % 10; 
        end
    end

    always @(*) begin
        if (delta_y_magnitude >= 200) begin 
            dy_h = 2; 
            dy_t = (delta_y_magnitude - 200) / 10; 
            dy_o = (delta_y_magnitude - 200) % 10; 
        end
        else if (delta_y_magnitude >= 100) begin 
            dy_h = 1; 
            dy_t = (delta_y_magnitude - 100) / 10; 
            dy_o = (delta_y_magnitude - 100) % 10; 
        end
        else begin 
            dy_h = 0; 
            dy_t = delta_y_magnitude / 10; 
            dy_o = delta_y_magnitude % 10; 
        end
    end

    //Hexadecimal_To_Seven_Segment s1(dx_o, HEX1);
    //Hexadecimal_To_Seven_Segment s2(dx_t, HEX2);
    //Hexadecimal_To_Seven_Segment s3(dx_h, HEX3);
    //Hexadecimal_To_Seven_Segment s4(dy_o, HEX4);
    //Hexadecimal_To_Seven_Segment s5(dy_t, HEX5);
     
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

endmodule
