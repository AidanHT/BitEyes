/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Demo                                                    *
 * Description:                                                              *
 *      PS/2 mouse VGA drawing - Fixed 320x240 version                      *
 *                                                                           *
 *****************************************************************************/

module PS2_Demo (
	// Inputs
	CLOCK_50,
	KEY,

	// Bidirectionals
	PS2_CLK,
	PS2_DAT,
	
	// Outputs - HEX displays
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
	VGA_CLK,
	
	// Debug outputs for DESim pixel interface
	debug_vga_x,
	debug_vga_y,
	debug_vga_color,
	debug_vga_write
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

// Using 320x240 resolution to reduce memory requirements
parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 240;

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

// Debug outputs for DESim pixel interface
output	[8:0]	debug_vga_x;
output	[7:0]	debug_vga_y;
output	[8:0]	debug_vga_color;
output			debug_vga_write;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Reset signal
wire reset_n;
assign reset_n = KEY[0];

// PS/2 signals
wire		[7:0]	ps2_byte;
wire				ps2_byte_en;

// Mouse parser outputs
wire signed	[8:0]	delta_x;
wire signed	[8:0]	delta_y;
wire		[2:0]	buttons;
wire				packet_ready;

// Mouse position tracking - using smaller range for 320x240
reg signed	[9:0]	mouse_x;  // -320 to 320 for overflow detection
reg signed	[9:0]	mouse_y;  // -240 to 240 for overflow detection
reg			[8:0]	cursor_x;  // 0-319
reg			[7:0]	cursor_y;  // 0-239
reg			[8:0]	last_draw_x;
reg			[7:0]	last_draw_y;

// Button tracking
reg				left_button;
reg				right_button;
reg				was_drawing;

// VGA interface - adjusted for 320x240
reg			[8:0]	vga_color;
reg			[8:0]	vga_x;  // 0-319
reg			[7:0]	vga_y;  // 0-239
reg					vga_write;

// Line drawing
wire				line_done;
wire		[8:0]	line_x;  // Adjusted for 320x240
wire		[7:0]	line_y;
wire				line_plot;
reg					line_start;
reg			[8:0]	line_x0, line_x1;
reg			[7:0]	line_y0, line_y1;

// State control
reg			[1:0]	state;
localparam	IDLE = 2'd0;
localparam	CLEAR = 2'd1;
localparam	DRAW_LINE = 2'd2;

// Clear control
reg			[8:0]	clear_x;
reg			[7:0]	clear_y;

// Debug values
reg			[15:0]	hex_x;
reg			[15:0]	hex_y;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Combined mouse tracking and drawing control
always @(posedge CLOCK_50) begin
	if (!reset_n) begin
		// Initialize everything
		mouse_x <= 10'd160;  // Center of 320
		mouse_y <= 10'd120;  // Center of 240
		cursor_x <= 9'd160;
		cursor_y <= 8'd120;
		last_draw_x <= 9'd160;
		last_draw_y <= 8'd120;
		left_button <= 1'b0;
		right_button <= 1'b0;
		was_drawing <= 1'b0;
		hex_x <= 16'd160;
		hex_y <= 16'd120;
		line_start <= 1'b0;
		line_x0 <= 9'd160;
		line_y0 <= 8'd120;
		line_x1 <= 9'd160;
		line_y1 <= 8'd120;
	end else if (packet_ready) begin
		// Update mouse position with clamping
		mouse_x <= mouse_x + delta_x;
		mouse_y <= mouse_y - delta_y;  // Invert Y
		
		// Clamp to screen bounds
		if (mouse_x + delta_x < 0)
			cursor_x <= 9'd0;
		else if (mouse_x + delta_x >= SCREEN_WIDTH)
			cursor_x <= SCREEN_WIDTH - 1;
		else
			cursor_x <= mouse_x[8:0];
			
		if (mouse_y - delta_y < 0)
			cursor_y <= 8'd0;
		else if (mouse_y - delta_y >= SCREEN_HEIGHT)
			cursor_y <= SCREEN_HEIGHT - 1;
		else
			cursor_y <= mouse_y[7:0];
		
		// Update button states
		left_button <= buttons[0];
		right_button <= buttons[1];
		
		// Update hex display
		hex_x <= {7'd0, cursor_x};
		hex_y <= {8'd0, cursor_y};
		
		// Handle drawing
		if ((buttons[0] || buttons[1]) && state == IDLE && !line_start) begin
			if (was_drawing) begin
				// Continue drawing from last position
				line_x0 <= last_draw_x;
				line_y0 <= last_draw_y;
				line_x1 <= cursor_x;
				line_y1 <= cursor_y;
			end else begin
				// Start new drawing at current position
				line_x0 <= cursor_x;
				line_y0 <= cursor_y;
				line_x1 <= cursor_x;
				line_y1 <= cursor_y;
			end
			line_start <= 1'b1;
			was_drawing <= 1'b1;
			last_draw_x <= cursor_x;
			last_draw_y <= cursor_y;
		end else if (!buttons[0] && !buttons[1]) begin
			was_drawing <= 1'b0;
		end
	end else begin
		// Clear line start when drawer picks it up
		if (line_start && state == DRAW_LINE) begin
			line_start <= 1'b0;
		end
	end
end

// Main state machine for display control
always @(posedge CLOCK_50) begin
	if (!reset_n) begin
		state <= CLEAR;
		vga_write <= 1'b0;
		clear_x <= 9'd0;
		clear_y <= 8'd0;
		vga_color <= COLOR_WHITE;
		vga_x <= 9'd0;
		vga_y <= 8'd0;
	end else begin
		case (state)
			IDLE: begin
				vga_write <= 1'b0;
				if (line_start) begin
					state <= DRAW_LINE;
				end
			end
			
			CLEAR: begin
				// Clear to white
				vga_x <= clear_x;
				vga_y <= clear_y;
				vga_color <= COLOR_WHITE;
				vga_write <= 1'b1;
				
				if (clear_x == SCREEN_WIDTH - 1) begin
					clear_x <= 9'd0;
					if (clear_y == SCREEN_HEIGHT - 1) begin
						clear_y <= 8'd0;
						state <= IDLE;
					end else begin
						clear_y <= clear_y + 1;
					end
				end else begin
					clear_x <= clear_x + 1;
				end
			end
			
			DRAW_LINE: begin
				if (line_plot) begin
					vga_x <= line_x;
					vga_y <= line_y;
					vga_color <= left_button ? COLOR_BLACK : COLOR_WHITE;
					vga_write <= 1'b1;
				end else begin
					vga_write <= 1'b0;
				end
				
				if (line_done) begin
					state <= IDLE;
				end
			end
			
			default: state <= IDLE;
		endcase
	end
end

/*****************************************************************************
 *                              Internal Modules                             *
 *****************************************************************************/

// PS/2 Controller
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

// Modified line drawer for 320x240
line_drawer_320x240 drawer (
	.clk					(CLOCK_50),
	.resetn					(reset_n),
	.start					(line_start),
	.x0						(line_x0),
	.y0						(line_y0),
	.x1						(line_x1),
	.y1						(line_y1),
	.x						(line_x),
	.y						(line_y),
	.plot					(line_plot),
	.done					(line_done)
);

// VGA Adapter configured for 320x240
vga_adapter #(
	.RESOLUTION("320x240"),
	.COLOR_DEPTH(9),
	.BACKGROUND_IMAGE("white_canvas_320.mif")
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

// Connect debug outputs for DESim
assign debug_vga_x = vga_x;
assign debug_vga_y = vga_y;
assign debug_vga_color = vga_color;
assign debug_vga_write = vga_write;

// HEX displays
Hexadecimal_To_Seven_Segment Segment0 (
	.hex_number				(hex_x[3:0]),
	.seven_seg_display		(HEX0)
);

Hexadecimal_To_Seven_Segment Segment1 (
	.hex_number				(hex_x[7:4]),
	.seven_seg_display		(HEX1)
);

Hexadecimal_To_Seven_Segment Segment2 (
	.hex_number				(hex_x[11:8]),
	.seven_seg_display		(HEX2)
);

Hexadecimal_To_Seven_Segment Segment3 (
	.hex_number				({2'b00, right_button, left_button}),
	.seven_seg_display		(HEX3)
);

Hexadecimal_To_Seven_Segment Segment4 (
	.hex_number				(hex_y[3:0]),
	.seven_seg_display		(HEX4)
);

Hexadecimal_To_Seven_Segment Segment5 (
	.hex_number				(hex_y[7:4]),
	.seven_seg_display		(HEX5)
);

Hexadecimal_To_Seven_Segment Segment6 (
	.hex_number				(hex_y[11:8]),
	.seven_seg_display		(HEX6)
);

assign HEX7 = 7'h7F;

endmodule


/*****************************************************************************
 * Line drawer modified for 320x240 resolution                              *
 *****************************************************************************/

module line_drawer_320x240 (
	input wire clk,
	input wire resetn,
	input wire start,
	output reg done,
	
	input wire [8:0] x0, x1,  // 0-319
	input wire [7:0] y0, y1,  // 0-239
	
	output reg [8:0] x,
	output reg [7:0] y,
	output reg plot
);

	reg [1:0] state;
	localparam IDLE = 2'd0;
	localparam DRAW = 2'd1;
	localparam DONE = 2'd2;
	
	reg [8:0] curr_x, end_x;
	reg [7:0] curr_y, end_y;
	reg signed [9:0] dx, dy, sx, sy, err, e2;
	
	always @(posedge clk) begin
		if (!resetn) begin
			state <= IDLE;
			done <= 1'b0;
			plot <= 1'b0;
			x <= 9'd0;
			y <= 8'd0;
		end else begin
			case (state)
				IDLE: begin
					done <= 1'b0;
					plot <= 1'b0;
					
					if (start) begin
						curr_x <= x0;
						curr_y <= y0;
						end_x <= x1;
						end_y <= y1;
						
						dx <= (x1 >= x0) ? (x1 - x0) : (x0 - x1);
						dy <= (y1 >= y0) ? (y1 - y0) : (y0 - y1);
						sx <= (x0 < x1) ? 1 : -1;
						sy <= (y0 < y1) ? 1 : -1;
						err <= ((x1 >= x0) ? (x1 - x0) : (x0 - x1)) - 
						       ((y1 >= y0) ? (y1 - y0) : (y0 - y1));
						
						state <= DRAW;
					end
				end
				
				DRAW: begin
					x <= curr_x;
					y <= curr_y;
					plot <= 1'b1;
					
					if (curr_x == end_x && curr_y == end_y) begin
						state <= DONE;
					end else begin
						e2 <= err << 1;
						
						if ((err << 1) > -dy) begin
							err <= err - dy;
							curr_x <= (sx == 1) ? (curr_x + 1) : (curr_x - 1);
						end
						
						if ((err << 1) < dx) begin
							err <= err + dx;
							curr_y <= (sy == 1) ? (curr_y + 1) : (curr_y - 1);
						end
					end
				end
				
				DONE: begin
					plot <= 1'b0;
					done <= 1'b1;
					if (!start)
						state <= IDLE;
				end
			endcase
		end
	end
endmodule
