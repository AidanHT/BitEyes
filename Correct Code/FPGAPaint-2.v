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
// SHAPE RECOGNIZER SIGNALS
// ============================================
// Shape recognizer interface signals
wire        sr_draw_en;
wire [8:0]  sr_draw_x;
wire [7:0]  sr_draw_y;
wire        sr_draw_pixel_on;
wire        sr_clear_canvas;
wire        sr_start_recognition;
wire        sr_busy;
wire        sr_recognition_done;
wire [2:0]  sr_detected_shape;
wire [7:0]  sr_confidence;

// Edge detector for SW[1] trigger
reg sw1_prev;
wire start_recognition_pulse;

always @(posedge CLOCK_50) begin
	if (reset) begin
		sw1_prev <= 1'b0;
	end else begin
		sw1_prev <= SW[1];
	end
end

assign start_recognition_pulse = SW[1] && !sw1_prev;

// Connect shape recognizer signals
assign sr_draw_en = vga_write && !clearing_active;  // Only during normal drawing
assign sr_draw_x = mouse_x_pos;
assign sr_draw_y = mouse_y_pos;
// draw_pixel_on: 1 when drawing black pixels (left button with black pen), 0 when erasing
assign sr_draw_pixel_on = (mouse_left_button) ? ~SW[9] : 1'b0;
assign sr_clear_canvas = reset;  // Clear shape buffer on reset
assign sr_start_recognition = start_recognition_pulse;

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

// Shape Recognizer instance
shape_recognizer shape_recognizer_inst (
	.clk(CLOCK_50),
	.reset_n(~reset),
	.draw_en(sr_draw_en),
	.draw_x(sr_draw_x),
	.draw_y(sr_draw_y),
	.draw_pixel_on(sr_draw_pixel_on),
	.clear_canvas(sr_clear_canvas),
	.start_recognition(sr_start_recognition),
	.busy(sr_busy),
	.recognition_done(sr_recognition_done),
	.detected_shape(sr_detected_shape),
	.confidence(sr_confidence)
);

// Display status on LEDs
assign LEDR[0] = drawing_enabled;      // LED[0] = drawing mode enabled
assign LEDR[1] = SW[1];                // LED[1] = shape recognition switch
assign LEDR[2] = mouse_left_button;    // LED[2] = left mouse button
assign LEDR[3] = mouse_right_button;   // LED[3] = right mouse button
assign LEDR[4] = drawing_active;       // LED[4] = currently drawing
assign LEDR[5] = clearing_active;      // LED[5] = currently clearing screen
assign LEDR[6] = sr_busy;              // LED[6] = shape recognizer busy
assign LEDR[7] = sr_recognition_done;  // LED[7] = recognition complete pulse
assign LEDR[8] = sr_detected_shape[0]; // LED[8-9] = detected shape (binary)
assign LEDR[9] = sr_detected_shape[1];

// ============================================================================
// SHAPE RECOGNIZER HEX DISPLAY
// ============================================================================
// HEX5: Detected shape (blank, A, b, C, d)
// HEX4: Blank
// HEX3: Blank  
// HEX2-HEX0: Confidence value (0-255) in decimal
// ============================================================================

// Shape to 7-segment decoder
reg [6:0] shape_hex;
always @(*) begin
	case (sr_detected_shape)
		3'd0: shape_hex = 7'b1111111; // blank for NONE
		3'd1: shape_hex = 7'b0001000; // A for RECTANGLE
		3'd2: shape_hex = 7'b0000011; // b for SQUARE
		3'd3: shape_hex = 7'b1000110; // C for TRIANGLE
		3'd4: shape_hex = 7'b0100001; // d for CIRCLE
		default: shape_hex = 7'b1111111; // blank
	endcase
end

assign HEX5 = shape_hex;
assign HEX4 = 7'b1111111; // blank
assign HEX3 = 7'b1111111; // blank

// Convert confidence (0-255) to BCD (3 digits: hundreds, tens, ones)
reg [3:0] conf_hundreds;
reg [3:0] conf_tens;
reg [3:0] conf_ones;

always @(*) begin
	if (sr_confidence >= 200) begin
		conf_hundreds = 4'd2;
		conf_tens = (sr_confidence - 200) / 10;
		conf_ones = (sr_confidence - 200) % 10;
	end
	else if (sr_confidence >= 100) begin
		conf_hundreds = 4'd1;
		conf_tens = (sr_confidence - 100) / 10;
		conf_ones = (sr_confidence - 100) % 10;
	end
	else begin
		conf_hundreds = 4'd0;
		conf_tens = sr_confidence / 10;
		conf_ones = sr_confidence % 10;
	end
end

// Convert BCD digits to 7-segment (using simple decoder)
reg [6:0] hex2_display;
reg [6:0] hex1_display;
reg [6:0] hex0_display;

// 7-segment decoder for digits 0-9
always @(*) begin
	case (conf_hundreds)
		4'd0: hex2_display = 7'b1000000; // 0
		4'd1: hex2_display = 7'b1111001; // 1
		4'd2: hex2_display = 7'b0100100; // 2
		default: hex2_display = 7'b1111111; // blank
	endcase
end

always @(*) begin
	case (conf_tens)
		4'd0: hex1_display = 7'b1000000; // 0
		4'd1: hex1_display = 7'b1111001; // 1
		4'd2: hex1_display = 7'b0100100; // 2
		4'd3: hex1_display = 7'b0110000; // 3
		4'd4: hex1_display = 7'b0011001; // 4
		4'd5: hex1_display = 7'b0010010; // 5
		4'd6: hex1_display = 7'b0000010; // 6
		4'd7: hex1_display = 7'b1111000; // 7
		4'd8: hex1_display = 7'b0000000; // 8
		4'd9: hex1_display = 7'b0010000; // 9
		default: hex1_display = 7'b1111111; // blank
	endcase
end

always @(*) begin
	case (conf_ones)
		4'd0: hex0_display = 7'b1000000; // 0
		4'd1: hex0_display = 7'b1111001; // 1
		4'd2: hex0_display = 7'b0100100; // 2
		4'd3: hex0_display = 7'b0110000; // 3
		4'd4: hex0_display = 7'b0011001; // 4
		4'd5: hex0_display = 7'b0010010; // 5
		4'd6: hex0_display = 7'b0000010; // 6
		4'd7: hex0_display = 7'b1111000; // 7
		4'd8: hex0_display = 7'b0000000; // 8
		4'd9: hex0_display = 7'b0010000; // 9
		default: hex0_display = 7'b1111111; // blank
	endcase
end

assign HEX2 = hex2_display;
assign HEX1 = hex1_display;
assign HEX0 = hex0_display;

endmodule
