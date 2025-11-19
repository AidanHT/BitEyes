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
	
	// HEX displays for testing - DELETE THIS SECTION AFTER TESTING
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

// FOR COLORS
wire [8:0] pen_colors;
assign pen_colors = {SW[9], SW[9], SW[9], 
                     SW[9], SW[9], SW[9], 
                     SW[9], SW[9], SW[9]};

wire reset;
assign reset = ~KEY[0];

wire [7:0] ps2_received_data;
wire ps2_received_data_en;

wire mouse_left_button;
wire mouse_right_button;
wire mouse_middle_button;
wire [8:0] mouse_delta_x; // First bit is the direction of movement
wire [8:0] mouse_delta_y;
wire mouse_data_valid;

reg [8:0] mouse_x_pos;  // 9 bits for X (0-319)
reg [7:0] mouse_y_pos;  // 8 bits for Y (0-239)

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
// SCREEN CLEARING STATE MACHINE
// ============================================
// States for the clearing process
localparam IDLE = 2'b00;
localparam CLEARING = 2'b01;
localparam WAIT_CLEAR = 2'b10;

reg [1:0] clear_state;
reg [8:0] clear_x;  // Current X position being cleared
reg [7:0] clear_y;  // Current Y position being cleared
reg clearing_active;  // Flag to indicate we're in clearing mode

// Screen clearing state machine
always @(posedge CLOCK_50) begin
	if (reset) begin
		// Start the clearing process
		clear_state <= CLEARING;
		clear_x <= 9'd0;
		clear_y <= 8'd0;
		clearing_active <= 1'b1;
	end
	else begin
		case (clear_state)
			IDLE: begin
				clearing_active <= 1'b0;
			end
			
			CLEARING: begin
				// Move to next pixel
				if (clear_x == SCREEN_WIDTH - 1) begin
					clear_x <= 9'd0;
					if (clear_y == SCREEN_HEIGHT - 1) begin
						// Finished clearing the screen
						clear_y <= 8'd0;
						clear_state <= IDLE;
						clearing_active <= 1'b0;
					end
					else begin
						clear_y <= clear_y + 1;
					end
				end
				else begin
					clear_x <= clear_x + 1;
				end
			end
			
			default: clear_state <= IDLE;
		endcase
	end
end
// ============================================

// Direction indicators - latched so they stay on once detected
reg move_left_latched;
reg move_right_latched;
reg move_up_latched;
reg move_down_latched;

// Detect movement in each direction
wire move_left_detect;
wire move_right_detect;
wire move_up_detect;
wire move_down_detect;

// Assigns for testing (removed mouse_data_valid check for immediate updates)
assign move_left_detect = mouse_data_valid && (mouse_delta_x[8] == 1) && (mouse_delta_x[7:0] != 0);
assign move_right_detect = mouse_data_valid && (mouse_delta_x[8] == 0) && (mouse_delta_x[7:0] != 0);
assign move_up_detect = mouse_data_valid && (mouse_delta_y[8] == 1) && (mouse_delta_y[7:0] != 0);
assign move_down_detect = mouse_data_valid && (mouse_delta_y[8] == 0) && (mouse_delta_y[7:0] != 0);

reg [7:0] corrected_delta_x;
reg [7:0] corrected_delta_y;

// Latch movement indicators - once set, stay on until reset
always @(posedge CLOCK_50) begin
	if (reset) begin
		move_left_latched <= 1'b0;
		move_right_latched <= 1'b0;
		move_up_latched <= 1'b0;
		move_down_latched <= 1'b0;
	end
	else begin
		// Set latches when movement detected, but don't clear them
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


// PS2 Controller with mouse initialization enabled
// Module was provided to us
PS2_Controller #(.INITIALIZE_MOUSE(1)) ps2_controller_inst (
	.CLOCK_50(CLOCK_50),
	.reset(reset),
	.the_command(8'h00),
	.send_command(1'b0),
	
	.PS2_CLK(PS2_CLK),
	.PS2_DAT(PS2_DAT),
	
	.command_was_sent(),
	.error_communication_timed_out(),
	.received_data(ps2_received_data),
	.received_data_en(ps2_received_data_en)
);

// Parses the PS2 outputs into named channels for better processing
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

always @(posedge CLOCK_50) begin
	if (reset) begin
		mouse_x_pos <= SCREEN_WIDTH / 2; // Start at center of screen
		mouse_y_pos <= SCREEN_HEIGHT / 2;
	end
	else begin
		// Update mouse position
		if (mouse_data_valid) begin
			// Calculate corrected deltas: if >= 128, it's encoded as 256 - actual_delta
			if (mouse_delta_x[7:0] >= 128) // negative movement (encoded)
				corrected_delta_x = 8'd256 - mouse_delta_x[7:0];
			else
				corrected_delta_x = mouse_delta_x[7:0];
				
			if (mouse_delta_y[7:0] >= 128) // negative movement (encoded)
				corrected_delta_y = 8'd256 - mouse_delta_y[7:0];
			else
				corrected_delta_y = mouse_delta_y[7:0];
			
			// Update X position only when we have valid movement data
			if (corrected_delta_x != 0) begin
				if (mouse_delta_x[7:0] < 128) begin // positive movement (right)
					// Use wider addition to prevent overflow issues
					if (mouse_x_pos + corrected_delta_x < SCREEN_WIDTH)
						mouse_x_pos <= mouse_x_pos + corrected_delta_x;
					else
						mouse_x_pos <= 9'd319; // SCREEN_WIDTH - 1
				end
				else begin // negative movement (left)
					if (mouse_x_pos >= corrected_delta_x)
						mouse_x_pos <= mouse_x_pos - corrected_delta_x;
					else
						mouse_x_pos <= 9'd0;
				end
			end
			
			// Update Y position only when we have valid movement data
			// Y=0 is at top, Y increases downward
			if (corrected_delta_y != 0) begin
				if (mouse_delta_y[7:0] > 128) begin // positive movement (down)
					if (mouse_y_pos + corrected_delta_y < SCREEN_HEIGHT)
						mouse_y_pos <= mouse_y_pos + corrected_delta_y;
					else
						mouse_y_pos <= 8'd239; // SCREEN_HEIGHT - 1
				end
				else begin // negative movement (up)
					if (mouse_y_pos >= corrected_delta_y)
						mouse_y_pos <= mouse_y_pos - corrected_delta_y;
					else
						mouse_y_pos <= 8'd0;
				end
			end
		end
	end
end

// Modified pixel drawing logic to handle clearing and normal drawing
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
		
		// Priority 1: Screen clearing has highest priority
		if (clearing_active) begin
			vga_write <= 1'b1;
			vga_x <= clear_x;
			vga_y <= clear_y;
			vga_color <= COLOR_CANVAS;  // Write white to clear the screen
		end
		// Priority 2: Normal drawing when not clearing
		else if (drawing_enabled && !clearing_active) begin
			if (mouse_right_button) begin
				vga_write <= 1'b1;
				vga_x <= mouse_x_pos;
				vga_y <= mouse_y_pos;
				vga_color <= COLOR_DRAW;  // White for erasing
			end
			else if (mouse_left_button) begin
				vga_write <= 1'b1;
				vga_x <= mouse_x_pos;
				vga_y <= mouse_y_pos;
				vga_color <= pen_colors;  // Black for drawing
			end
		end
	end
end

// VGA Adapter instance
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
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_BLANK_N(VGA_BLANK_N),
	.VGA_SYNC_N(VGA_SYNC_N),
	.VGA_CLK(VGA_CLK)
);

// Display status on LEDs
assign LEDR[0] = drawing_enabled; // LED[0] = drawing mode enabled
assign LEDR[1] = mouse_right_button; // LED[1] = right mouse button
assign LEDR[2] = mouse_left_button; // LED[2] = left mouse button
assign LEDR[3] = move_right_latched;
assign LEDR[4] = move_left_latched; // LED[4] = mouse moving left (latched)
assign LEDR[5] = move_up_latched; // LED[5] = mouse moving up (latched)
assign LEDR[6] = move_down_latched; // LED[6] = mouse moving down (latched)
assign LEDR[7] = drawing_active; // LED[7] = currently drawing
assign LEDR[8] = clearing_active; // LED[8] = currently clearing screen
assign LEDR[9] = 1'b0; // LED[9] = unused

// ============================================================================
// HEX DISPLAY TESTING CODE - DELETE THIS ENTIRE SECTION AFTER TESTING
// ============================================================================
// Displays mouse delta values in base 10 (decimal):
//   HEX5-HEX3: delta_x magnitude (0-255)
//   HEX2-HEX0: delta_y magnitude (0-255)
// ============================================================================

// Extract magnitude from delta values - use corrected deltas which already account for sign
wire [7:0] delta_x_magnitude;
wire [7:0] delta_y_magnitude;
assign delta_x_magnitude = corrected_delta_x;
assign delta_y_magnitude = corrected_delta_y;

// Convert binary to BCD for delta_x (3 digits: hundreds, tens, ones)
reg [3:0] delta_x_hundreds;
reg [3:0] delta_x_tens;
reg [3:0] delta_x_ones;

// Convert binary to BCD for delta_y (3 digits: hundreds, tens, ones)
reg [3:0] delta_y_hundreds;
reg [3:0] delta_y_tens;
reg [3:0] delta_y_ones;

// Binary to BCD conversion for delta_x
always @(*) begin
	if (delta_x_magnitude >= 200) begin
		delta_x_hundreds = 4'd2;
		delta_x_tens = (delta_x_magnitude - 200) / 10;
		delta_x_ones = (delta_x_magnitude - 200) % 10;
	end
	else if (delta_x_magnitude >= 100) begin
		delta_x_hundreds = 4'd1;
		delta_x_tens = (delta_x_magnitude - 100) / 10;
		delta_x_ones = (delta_x_magnitude - 100) % 10;
	end
	else begin
		delta_x_hundreds = 4'd0;
		delta_x_tens = delta_x_magnitude / 10;
		delta_x_ones = delta_x_magnitude % 10;
	end
end

// Binary to BCD conversion for delta_y
always @(*) begin
	if (delta_y_magnitude >= 200) begin
		delta_y_hundreds = 4'd2;
		delta_y_tens = (delta_y_magnitude - 200) / 10;
		delta_y_ones = (delta_y_magnitude - 200) % 10;
	end
	else if (delta_y_magnitude >= 100) begin
		delta_y_hundreds = 4'd1;
		delta_y_tens = (delta_y_magnitude - 100) / 10;
		delta_y_ones = (delta_y_magnitude - 100) % 10;
	end
	else begin
		delta_y_hundreds = 4'd0;
		delta_y_tens = delta_y_magnitude / 10;
		delta_y_ones = delta_y_magnitude % 10;
	end
end

endmodule
