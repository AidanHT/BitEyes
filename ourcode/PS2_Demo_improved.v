/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Demo                                                    *
 * Description:                                                              *
 *      This module demonstrates PS/2 mouse functionality with VGA drawing   *
 *      canvas. Left click draws black, right click erases (white).         *
 *      Improved version with better state machines and cursor handling.     *
 *                                                                           *
 *****************************************************************************/

module PS2_Demo_improved (
	// Inputs
	CLOCK_50,
	KEY,

	// Bidirectionals
	PS2_CLK,
	PS2_DAT,
	
	// Outputs - HEX displays (optional debug)
	HEX0,
	HEX1,
	HEX2,
	HEX3,
	HEX4,
	HEX5,
	HEX6,
	HEX7,
	
	// VGA outputs
	VGA_R,
	VGA_G,
	VGA_B,
	VGA_HS,
	VGA_VS,
	VGA_BLANK_N,
	VGA_SYNC_N,
	VGA_CLK
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

// Screen dimensions
parameter SCREEN_WIDTH = 640;
parameter SCREEN_HEIGHT = 480;

// Colors (9-bit RGB: 3 bits each)
parameter COLOR_WHITE = 9'b111_111_111;  // White canvas
parameter COLOR_BLACK = 9'b000_000_000;  // Drawing color
parameter COLOR_RED   = 9'b111_000_000;  // Cursor color

/*****************************************************************************
 *                             Port Declarations                             *
 *****************************************************************************/

// Inputs
input				CLOCK_50;
input		[3:0]	KEY;

// Bidirectionals
inout				PS2_CLK;
inout				PS2_DAT;

// Outputs - HEX displays
output		[6:0]	HEX0;
output		[6:0]	HEX1;
output		[6:0]	HEX2;
output		[6:0]	HEX3;
output		[6:0]	HEX4;
output		[6:0]	HEX5;
output		[6:0]	HEX6;
output		[6:0]	HEX7;

// VGA outputs
output	[7:0]	VGA_R;
output	[7:0]	VGA_G;
output	[7:0]	VGA_B;
output			VGA_HS;
output			VGA_VS;
output			VGA_BLANK_N;
output			VGA_SYNC_N;
output			VGA_CLK;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Reset signal (active high for internal use)
wire reset_n;
assign reset_n = KEY[0];

// Internal Wires - PS/2 Controller
wire		[7:0]	ps2_byte;
wire				ps2_byte_en;

// Internal Wires - Mouse Parser
wire signed	[8:0]	delta_x;
wire signed	[8:0]	delta_y;
wire		[2:0]	buttons;  // {Middle, Right, Left}
wire				packet_ready;

// Mouse position tracking (signed for easier arithmetic)
reg signed	[10:0]	cursor_x;  // Extra bit for overflow detection
reg signed	[9:0]	cursor_y;   // Extra bit for overflow detection
reg			[9:0]	prev_cursor_x;
reg			[8:0]	prev_cursor_y;

// Button state tracking
reg				left_button;
reg				right_button;
reg				prev_left_button;
reg				prev_right_button;

// VGA interface signals
reg			[8:0]	vga_color;
reg			[9:0]	vga_x;
reg			[8:0]	vga_y;
reg					vga_write;

// Line drawing signals
wire				line_done;
wire		[9:0]	line_x;
wire		[8:0]	line_y;
wire				line_plot;
reg					line_start;
reg			[9:0]	line_x0, line_x1;
reg			[8:0]	line_y0, line_y1;
reg			[8:0]	current_color;  // Color for line drawing

// Display state machine
reg			[2:0]	display_state;
localparam	DISP_IDLE = 3'd0;
localparam	DISP_CLEAR = 3'd1;
localparam	DISP_LINE = 3'd2;
localparam	DISP_CURSOR = 3'd3;

// Canvas clear control
reg			[9:0]	clear_x;
reg			[8:0]	clear_y;

// Cursor drawing control
reg			[3:0]	cursor_pixel;
reg			[9:0]	cursor_draw_x;
reg			[8:0]	cursor_draw_y;

// Frame counter for timing
reg			[19:0]	frame_counter;
wire				cursor_visible;
assign cursor_visible = frame_counter[19];  // Blink cursor

// Internal Registers for HEX display (debug)
reg			[15:0]	mouse_x_display;
reg			[15:0]	mouse_y_display;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Frame counter
always @(posedge CLOCK_50) begin
	if (!reset_n)
		frame_counter <= 20'd0;
	else
		frame_counter <= frame_counter + 20'd1;
end

// Mouse position and button tracking
always @(posedge CLOCK_50) begin
	if (!reset_n) begin
		// Initialize to center of screen
		cursor_x <= 11'd320;
		cursor_y <= 10'd240;
		prev_cursor_x <= 10'd320;
		prev_cursor_y <= 9'd240;
		left_button <= 1'b0;
		right_button <= 1'b0;
		prev_left_button <= 1'b0;
		prev_right_button <= 1'b0;
		line_start <= 1'b0;
		mouse_x_display <= 16'd320;
		mouse_y_display <= 16'd240;
	end else if (packet_ready) begin
		// Save previous state
		prev_cursor_x <= cursor_x[9:0];
		prev_cursor_y <= cursor_y[8:0];
		prev_left_button <= left_button;
		prev_right_button <= right_button;
		
		// Update button states
		left_button <= buttons[0];
		right_button <= buttons[1];
		
		// Update cursor position with clamping
		cursor_x <= cursor_x + delta_x;
		cursor_y <= cursor_y - delta_y;  // Invert Y (PS/2 Y is inverted)
		
		// Clamp to screen boundaries
		if (cursor_x + delta_x < 0)
			cursor_x <= 0;
		else if (cursor_x + delta_x >= SCREEN_WIDTH)
			cursor_x <= SCREEN_WIDTH - 1;
		else
			cursor_x <= cursor_x + delta_x;
			
		if (cursor_y - delta_y < 0)
			cursor_y <= 0;
		else if (cursor_y - delta_y >= SCREEN_HEIGHT)
			cursor_y <= SCREEN_HEIGHT - 1;
		else
			cursor_y <= cursor_y - delta_y;
		
		// Update display values
		mouse_x_display <= cursor_x[9:0];
		mouse_y_display <= cursor_y[8:0];
		
		// Trigger line drawing if button held and position changed
		if ((left_button || right_button) && 
		    ((cursor_x[9:0] != prev_cursor_x) || (cursor_y[8:0] != prev_cursor_y))) begin
			line_start <= 1'b1;
			line_x0 <= prev_cursor_x;
			line_y0 <= prev_cursor_y;
			line_x1 <= cursor_x[9:0];
			line_y1 <= cursor_y[8:0];
			current_color <= left_button ? COLOR_BLACK : COLOR_WHITE;
		end
	end else if (line_start && display_state == DISP_LINE) begin
		// Clear line start once line drawing begins
		line_start <= 1'b0;
	end
end

// Main display state machine
always @(posedge CLOCK_50) begin
	if (!reset_n) begin
		display_state <= DISP_CLEAR;
		vga_write <= 1'b0;
		clear_x <= 10'd0;
		clear_y <= 9'd0;
		cursor_pixel <= 4'd0;
	end else begin
		case (display_state)
			DISP_IDLE: begin
				vga_write <= 1'b0;
				
				// Priority: Line drawing > Cursor drawing
				if (line_start) begin
					display_state <= DISP_LINE;
				end else if (cursor_visible && frame_counter[9:0] == 10'd0) begin
					// Redraw cursor periodically
					display_state <= DISP_CURSOR;
					cursor_pixel <= 4'd0;
				end
			end
			
			DISP_CLEAR: begin
				// Clear canvas to white on reset
				vga_x <= clear_x;
				vga_y <= clear_y;
				vga_color <= COLOR_WHITE;
				vga_write <= 1'b1;
				
				if (clear_x == SCREEN_WIDTH - 1) begin
					clear_x <= 10'd0;
					if (clear_y == SCREEN_HEIGHT - 1) begin
						clear_y <= 9'd0;
						display_state <= DISP_IDLE;
						vga_write <= 1'b0;
					end else begin
						clear_y <= clear_y + 9'd1;
					end
				end else begin
					clear_x <= clear_x + 10'd1;
				end
			end
			
			DISP_LINE: begin
				// Draw line using line drawer module
				if (line_plot) begin
					vga_x <= line_x;
					vga_y <= line_y;
					vga_color <= current_color;
					vga_write <= 1'b1;
				end else begin
					vga_write <= 1'b0;
				end
				
				if (line_done) begin
					display_state <= DISP_IDLE;
				end
			end
			
			DISP_CURSOR: begin
				// Draw 3x3 cursor
				case (cursor_pixel)
					4'd0: begin cursor_draw_x <= cursor_x[9:0]; cursor_draw_y <= cursor_y[8:0]; end  // Center
					4'd1: begin cursor_draw_x <= cursor_x[9:0] - 1; cursor_draw_y <= cursor_y[8:0]; end
					4'd2: begin cursor_draw_x <= cursor_x[9:0] + 1; cursor_draw_y <= cursor_y[8:0]; end
					4'd3: begin cursor_draw_x <= cursor_x[9:0]; cursor_draw_y <= cursor_y[8:0] - 1; end
					4'd4: begin cursor_draw_x <= cursor_x[9:0]; cursor_draw_y <= cursor_y[8:0] + 1; end
					default: begin
						display_state <= DISP_IDLE;
						vga_write <= 1'b0;
					end
				endcase
				
				if (cursor_pixel < 4'd5) begin
					// Check bounds before drawing
					if (cursor_draw_x < SCREEN_WIDTH && cursor_draw_y < SCREEN_HEIGHT) begin
						vga_x <= cursor_draw_x;
						vga_y <= cursor_draw_y;
						vga_color <= COLOR_RED;
						vga_write <= 1'b1;
					end else begin
						vga_write <= 1'b0;
					end
					cursor_pixel <= cursor_pixel + 4'd1;
				end else begin
					display_state <= DISP_IDLE;
					vga_write <= 1'b0;
				end
			end
			
			default: begin
				display_state <= DISP_IDLE;
				vga_write <= 1'b0;
			end
		endcase
	end
end

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/

// HEX displays show cursor position for debugging
// You can modify these to show button states or other debug info

/*****************************************************************************
 *                              Internal Modules                             *
 *****************************************************************************/

// PS/2 Controller with mouse initialization
PS2_Controller #(.INITIALIZE_MOUSE(1)) PS2 (
	.CLOCK_50				(CLOCK_50),
	.reset					(~reset_n),
	.the_command			(8'h00),
	.send_command			(1'b0),
	.PS2_CLK				(PS2_CLK),
 	.PS2_DAT				(PS2_DAT),
	.received_data			(ps2_byte),
	.received_data_en		(ps2_byte_en),
	.command_was_sent		(),
	.error_communication_timed_out()
);

// Mouse parser
PS2_Mouse_Parser parser (
    .clk					(CLOCK_50), 
    .rst					(~reset_n),
    .ps2_byte				(ps2_byte), 
    .ps2_byte_en			(ps2_byte_en),
    .delta_x				(delta_x), 
    .delta_y				(delta_y),
    .buttons				(buttons), 
    .packet_ready			(packet_ready)
);

// Line drawer for gap-free strokes
line_drawer drawer (
	.clk					(CLOCK_50),
	.resetn					(reset_n),
	.start					(line_start && display_state == DISP_IDLE),
	.x0						(line_x0),
	.y0						(line_y0),
	.x1						(line_x1),
	.y1						(line_y1),
	.x						(line_x),
	.y						(line_y),
	.plot					(line_plot),
	.done					(line_done)
);

// VGA Adapter
vga_adapter #(
	.RESOLUTION("640x480"),
	.COLOR_DEPTH(9),
	.BACKGROUND_IMAGE("white_canvas.mif")
) VGA (
	.resetn					(reset_n),
	.clock					(CLOCK_50),
	.color					(vga_color),
	.x						(vga_x),
	.y						(vga_y),
	.write					(vga_write),
	.VGA_R					(VGA_R),
	.VGA_G					(VGA_G),
	.VGA_B					(VGA_B),
	.VGA_HS					(VGA_HS),
	.VGA_VS					(VGA_VS),
	.VGA_BLANK_N			(VGA_BLANK_N),
	.VGA_SYNC_N				(VGA_SYNC_N),
	.VGA_CLK				(VGA_CLK)
);

// HEX displays for debugging - show mouse coordinates
Hexadecimal_To_Seven_Segment Segment0 (
	.hex_number				(mouse_x_display[3:0]),
	.seven_seg_display		(HEX0)
);

Hexadecimal_To_Seven_Segment Segment1 (
	.hex_number				(mouse_x_display[7:4]),
	.seven_seg_display		(HEX1)
);

Hexadecimal_To_Seven_Segment Segment2 (
	.hex_number				(mouse_x_display[9:8]),
	.seven_seg_display		(HEX2)
);

Hexadecimal_To_Seven_Segment Segment3 (
	.hex_number				({2'b00, right_button, left_button}),  // Show button states
	.seven_seg_display		(HEX3)
);

Hexadecimal_To_Seven_Segment Segment4 (
	.hex_number				(mouse_y_display[3:0]),
	.seven_seg_display		(HEX4)
);

Hexadecimal_To_Seven_Segment Segment5 (
	.hex_number				(mouse_y_display[7:4]),
	.seven_seg_display		(HEX5)
);

Hexadecimal_To_Seven_Segment Segment6 (
	.hex_number				({3'b000, mouse_y_display[8]}),
	.seven_seg_display		(HEX6)
);

// HEX7 blank
assign HEX7 = 7'h7F;

endmodule
