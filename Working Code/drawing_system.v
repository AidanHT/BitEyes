// Top-level module for VGA drawing system using PS/2 mouse input

module drawing_system(
    // Inputs
    CLOCK_50,
    KEY,
    SW,
    
    // Bidirectionals
    PS2_CLK,
    PS2_DAT,
    
    // Outputs
    VGA_R,
    VGA_G,
    VGA_B,
    VGA_HS,
    VGA_VS,
    VGA_BLANK_N,
    VGA_SYNC_N,
    VGA_CLK,
    LEDR,
    HEX0,
    HEX1,
    HEX2,
    HEX3
);

// Parameter Declarations

// VGA parameters
parameter VGA_WIDTH = 320;
parameter VGA_HEIGHT = 240;
parameter X_BITS = 9;   // log2(320)
parameter Y_BITS = 8;   // log2(240)

// Cursor parameters
parameter CURSOR_SIZE = 21;  // 21x21 pixel cursor (3x larger than original 7x7)
parameter CURSOR_COLOR = 9'b111_000_000;  // Red cursor

// Drawing parameters
parameter DRAW_SIZE = 2;  // 2x2 pixel brush size
parameter DRAW_COLOR = 9'b111_111_111;    // White for drawing
parameter ERASE_COLOR = 9'b000_000_000;   // Black for erasing

// Port Declarations

// Inputs
input CLOCK_50;
input [3:0] KEY;
input [9:0] SW;

// Bidirectionals
inout PS2_CLK;
inout PS2_DAT;

// Outputs
output [7:0] VGA_R;
output [7:0] VGA_G;
output [7:0] VGA_B;
output VGA_HS;
output VGA_VS;
output VGA_BLANK_N;
output VGA_SYNC_N;
output VGA_CLK;
output [9:0] LEDR;
output [6:0] HEX0;
output [6:0] HEX1;
output [6:0] HEX2;
output [6:0] HEX3;

// Internal Wires and Registers Declarations

// Reset signal (active low)
wire resetn;
assign resetn = KEY[0];

// PS/2 Controller signals
wire [7:0] ps2_byte;
wire ps2_byte_en;

// Mouse Parser signals
wire [8:0] delta_x;
wire [8:0] delta_y;
wire [2:0] buttons;
wire packet_ready;

// Cursor position registers
reg [X_BITS-1:0] cursor_x;
reg [Y_BITS-1:0] cursor_y;
reg [X_BITS-1:0] old_cursor_x;
reg [Y_BITS-1:0] old_cursor_y;
reg cursor_moved;
reg cursor_needs_redraw;

// VGA signals
reg [8:0] vga_color;
reg [X_BITS-1:0] vga_x;
reg [Y_BITS-1:0] vga_y;
reg vga_write;

// Drawing state
reg drawing_enabled;
reg erasing_enabled;
reg was_drawing;  // Track previous drawing state to detect button release
wire left_button_pressed;
wire right_button_pressed;

// State machine
parameter IDLE = 3'b000;
parameter CLEAR_OLD_CURSOR = 3'b001;
parameter DRAW_CURSOR = 3'b010;
parameter DRAW_PIXEL = 3'b011;
parameter DRAW_PIXEL_LOOP = 3'b100;
parameter CLEARING_SCREEN = 3'b101;

reg [2:0] state;
reg [8:0] cursor_count;  // Counter for cursor pixels (21x21 = 441 pixels)
reg [18:0] clear_address;  // Counter for clearing entire screen (320*240 = 76800)
reg [1:0] draw_pixel_count;  // Counter for 2x2 pixel drawing

// Mouse Position Tracking

// Signed arithmetic for position update
wire signed [X_BITS:0] new_cursor_x;  // Extra bit for overflow detection
wire signed [Y_BITS:0] new_cursor_y;

// Calculate new position with overflow protection
assign new_cursor_x = $signed({1'b0, cursor_x}) + $signed(delta_x);
assign new_cursor_y = $signed({1'b0, cursor_y}) - $signed(delta_y);  // Subtract to invert Y-axis for screen coordinates

// Update cursor position on mouse packet ready
always @(posedge CLOCK_50) begin
    if (!resetn) begin
        cursor_x <= 9'd160;   // Start at center of 320x240 screen
        cursor_y <= 8'd120;
        old_cursor_x <= 9'd160;
        old_cursor_y <= 8'd120;
    end else begin
        if (packet_ready) begin
            // Store old position before updating
            old_cursor_x <= cursor_x;
            old_cursor_y <= cursor_y;
            
            // Update X with boundary checking
            if ($signed(new_cursor_x) < $signed(10'd0))
                cursor_x <= 9'd0;
            else if ($signed(new_cursor_x) >= $signed({1'b0, 9'd320}))
                cursor_x <= 9'd319;
            else
                cursor_x <= new_cursor_x[X_BITS-1:0];
                
            // Update Y with boundary checking
            if ($signed(new_cursor_y) < $signed(9'd0))
                cursor_y <= 8'd0;
            else if ($signed(new_cursor_y) >= $signed({1'b0, 8'd240}))
                cursor_y <= 8'd239;
            else
                cursor_y <= new_cursor_y[Y_BITS-1:0];
        end
    end
end

// Drawing and Erasing Logic

assign left_button_pressed = buttons[0];
assign right_button_pressed = buttons[1];

// Main state machine for drawing and cursor rendering
always @(posedge CLOCK_50) begin
    if (!resetn) begin
        state <= IDLE;
        cursor_count <= 9'd0;
        clear_address <= 19'd0;
        draw_pixel_count <= 2'd0;
        vga_write <= 1'b0;
        drawing_enabled <= 1'b0;
        erasing_enabled <= 1'b0;
        was_drawing <= 1'b0;
        cursor_moved <= 1'b0;
        cursor_needs_redraw <= 1'b1;  // Draw initial cursor
    end else begin
        // SW[9] triggers screen clear
        if (SW[9] && state == IDLE) begin
            state <= CLEARING_SCREEN;
            clear_address <= 19'd0;
        end
        
        case (state)
            IDLE: begin
                vga_write <= 1'b0;
                
                // Detect cursor movement
                if (packet_ready && ((delta_x != 9'd0) || (delta_y != 9'd0))) begin
                    cursor_moved <= 1'b1;
                    cursor_needs_redraw <= 1'b1;
                end else begin
                    cursor_moved <= 1'b0;
                end
                
                // Update drawing and erasing state
                if (packet_ready && left_button_pressed) begin
                    drawing_enabled <= 1'b1;
                    erasing_enabled <= 1'b0;
                    was_drawing <= 1'b1;
                end else if (packet_ready && right_button_pressed) begin
                    drawing_enabled <= 1'b0;
                    erasing_enabled <= 1'b1;
                    was_drawing <= 1'b1;
                end else if (packet_ready && !left_button_pressed && !right_button_pressed) begin
                    // Button released - need to redraw cursor
                    if (was_drawing) begin
                        cursor_needs_redraw <= 1'b1;
                        cursor_moved <= 1'b0;  // Don't clear old cursor, just redraw
                    end
                    drawing_enabled <= 1'b0;
                    erasing_enabled <= 1'b0;
                    was_drawing <= 1'b0;
                end
                
                // Handle drawing pixel first if button is pressed
                if (drawing_enabled || erasing_enabled) begin
                    state <= DRAW_PIXEL;
                end
                // Redraw cursor when it has moved (clear old position first)
                else if (cursor_needs_redraw && cursor_moved) begin
                    cursor_count <= 9'd0;
                    state <= CLEAR_OLD_CURSOR;
                end
                // Draw cursor without clearing (for button release or initial draw)
                else if (cursor_needs_redraw && !cursor_moved) begin
                    cursor_count <= 9'd0;
                    state <= DRAW_CURSOR;
                end
                // Otherwise stay idle
            end
            
            CLEAR_OLD_CURSOR: begin
                // Erase old cursor position by drawing black (21x21 cross pattern)
                // Draw cross at center line (row 10 or column 10)
                if ((cursor_count % 9'd21 == 9'd10) || (cursor_count / 9'd21 == 9'd10)) begin
                    // Calculate position with bounds checking
                    if ((old_cursor_x >= 9'd10) && (old_cursor_x + 9'd11 < 9'd320) &&
                        (old_cursor_y >= 8'd10) && (old_cursor_y + 8'd11 < 8'd240)) begin
                        vga_x <= old_cursor_x - 9'd10 + (cursor_count % 9'd21);
                        vga_y <= old_cursor_y - 8'd10 + (cursor_count / 9'd21);
                        vga_color <= ERASE_COLOR;
                        vga_write <= 1'b1;
                    end else begin
                        vga_write <= 1'b0;
                    end
                end else begin
                    vga_write <= 1'b0;
                end
                
                // Move through all cursor pixels
                if (cursor_count < 9'd440) begin  // 21x21 - 1
                    cursor_count <= cursor_count + 1'b1;
                end else begin
                    cursor_count <= 9'd0;
                    state <= DRAW_CURSOR;
                end
            end
            
            DRAW_CURSOR: begin
                // Draw cursor as a cross pattern (21x21 grid)
                // Draw cross at center line (row 10 or column 10)
                if ((cursor_count % 9'd21 == 9'd10) || (cursor_count / 9'd21 == 9'd10)) begin
                    // Calculate position with bounds checking
                    if ((cursor_x >= 9'd10) && (cursor_x + 9'd11 < 9'd320) &&
                        (cursor_y >= 8'd10) && (cursor_y + 8'd11 < 8'd240)) begin
                        vga_x <= cursor_x - 9'd10 + (cursor_count % 9'd21);
                        vga_y <= cursor_y - 8'd10 + (cursor_count / 9'd21);
                        vga_color <= CURSOR_COLOR;
                        vga_write <= 1'b1;
                    end else begin
                        vga_write <= 1'b0;
                    end
                end else begin
                    vga_write <= 1'b0;
                end
                
                // Move through all cursor pixels
                if (cursor_count < 9'd440) begin  // 21x21 - 1
                    cursor_count <= cursor_count + 1'b1;
                end else begin
                    cursor_count <= 9'd0;
                    cursor_needs_redraw <= 1'b0;  // Clear redraw flag
                    state <= IDLE;
                end
            end
            
            DRAW_PIXEL: begin
                // Initialize 2x2 pixel drawing
                draw_pixel_count <= 2'd0;
                state <= DRAW_PIXEL_LOOP;
            end
            
            DRAW_PIXEL_LOOP: begin
                // Draw 2x2 pixel block at cursor position
                // Calculate offset based on draw_pixel_count: 0=(0,0), 1=(1,0), 2=(0,1), 3=(1,1)
                if ((cursor_x + (draw_pixel_count[0] ? 9'd1 : 9'd0) < 9'd320) &&
                    (cursor_y + (draw_pixel_count[1] ? 8'd1 : 8'd0) < 8'd240)) begin
                    vga_x <= cursor_x + (draw_pixel_count[0] ? 9'd1 : 9'd0);
                    vga_y <= cursor_y + (draw_pixel_count[1] ? 8'd1 : 8'd0);
                    vga_color <= drawing_enabled ? DRAW_COLOR : ERASE_COLOR;
                    vga_write <= 1'b1;
                end else begin
                    vga_write <= 1'b0;
                end
                
                // Move through all 4 pixels of the 2x2 block
                if (draw_pixel_count < 2'd3) begin
                    draw_pixel_count <= draw_pixel_count + 1'b1;
                end else begin
                    cursor_needs_redraw <= 1'b0;  // Don't redraw cursor while drawing
                    state <= IDLE;
                end
            end
            
            CLEARING_SCREEN: begin
                // Clear entire screen by writing black to every pixel
                // Address format: {X[8:0], Y[7:0]} = 17 bits
                vga_x <= clear_address[16:8];  // Upper 9 bits = X coordinate
                vga_y <= clear_address[7:0];   // Lower 8 bits = Y coordinate
                vga_color <= ERASE_COLOR;      // Black
                vga_write <= 1'b1;
                
                if (clear_address == 19'd76799)  // 320*240-1
                    state <= IDLE;
                else
                    clear_address <= clear_address + 1'b1;
            end
            
            default: state <= IDLE;
        endcase
    end
end

// VGA Display Controller

// VGA adapter with internal video memory
vga_adapter #(
    .RESOLUTION("320x240"),
    .COLOR_DEPTH(9),
    .BACKGROUND_IMAGE("black.mif")
) VGA (
    .resetn(resetn),
    .clock(CLOCK_50),
    .color(vga_color),
    .x(vga_x),
    .y(vga_y),
    .write(vga_write),
    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    .VGA_HS(VGA_HS),
    .VGA_VS(VGA_VS),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_SYNC_N(VGA_SYNC_N),
    .VGA_CLK(VGA_CLK)
);

// PS/2 Mouse Interface and Parser

PS2_Controller #(
    .INITIALIZE_MOUSE(1)
) ps2_ctrl (
    .CLOCK_50(CLOCK_50),
    .reset(~resetn),
    .the_command(8'h00),
    .send_command(1'b0),
    .PS2_CLK(PS2_CLK),
    .PS2_DAT(PS2_DAT),
    .received_data(ps2_byte),
    .received_data_en(ps2_byte_en),
    .command_was_sent(),
    .error_communication_timed_out()
);

PS2_Mouse_Parser mouse_parser (
    .clk(CLOCK_50),
    .rst(~resetn),
    .ps2_byte(ps2_byte),
    .ps2_byte_en(ps2_byte_en),
    .delta_x(delta_x),
    .delta_y(delta_y),
    .buttons(buttons),
    .packet_ready(packet_ready)
);

// Debugging and Status Displays

// Display cursor position on HEX displays
// X coordinate: 0-319 (0x000-0x13F) displayed on HEX1-HEX0
Hexadecimal_To_Seven_Segment seg0 (
	// Inputs
	.hex_number				(cursor_x[3:0]),

	// Outputs
	.seven_seg_display		(HEX0)
);
Hexadecimal_To_Seven_Segment seg1 (
	// Inputs
	.hex_number				(cursor_x[7:4]),

	// Outputs
	.seven_seg_display		(HEX1)
);
// Y coordinate: 0-239 (0x000-0x0EF) displayed on HEX3-HEX2
Hexadecimal_To_Seven_Segment seg2 (
	// Inputs
	.hex_number				(cursor_y[3:0]),

	// Outputs
	.seven_seg_display		(HEX2)
);
Hexadecimal_To_Seven_Segment seg3 (
	// Inputs
	.hex_number				(cursor_y[7:4]),

	// Outputs
	.seven_seg_display		(HEX3)
);

// Display button states and drawing status on LEDs
assign LEDR[2:0] = buttons; // Display which buttons are pressed
assign LEDR[3] = drawing_enabled;
assign LEDR[4] = erasing_enabled;
assign LEDR[5] = packet_ready;
assign LEDR[6] = (state == CLEARING_SCREEN);  // Indicator when clearing
assign LEDR[9:7] = 3'b0;

endmodule
