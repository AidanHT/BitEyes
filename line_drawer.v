/*****************************************************************************
 *                                                                           *
 * Module:       line_drawer                                                 *
 * Description:                                                              *
 *      This module implements Bresenham's line drawing algorithm to draw    *
 *      lines between two points. Used for gap-free mouse drawing.          *
 *                                                                           *
 *****************************************************************************/

module line_drawer (
	input wire clk,
	input wire resetn,
	
	// Control signals
	input wire start,           // Pulse to start drawing a line
	output reg done,            // Indicates line drawing is complete
	
	// Line endpoints
	input wire [9:0] x0,        // Start X coordinate
	input wire [8:0] y0,        // Start Y coordinate
	input wire [9:0] x1,        // End X coordinate
	input wire [8:0] y1,        // End Y coordinate
	
	// Output pixel coordinates
	output reg [9:0] x,         // Current pixel X
	output reg [8:0] y,         // Current pixel Y
	output reg plot             // High when pixel should be plotted
);

	// State machine states
	localparam IDLE = 3'd0;
	localparam INIT = 3'd1;
	localparam DRAW = 3'd2;
	localparam DONE = 3'd3;
	
	reg [2:0] state;
	
	// Bresenham's algorithm variables
	reg signed [10:0] dx, dy;
	reg signed [10:0] sx, sy;
	reg signed [11:0] error;
	reg signed [11:0] error2;
	reg [9:0] curr_x;
	reg [8:0] curr_y;
	reg [9:0] end_x;
	reg [8:0] end_y;
	
	// State machine
	always @(posedge clk) begin
		if (!resetn) begin
			state <= IDLE;
			done <= 1'b0;
			plot <= 1'b0;
			x <= 10'd0;
			y <= 9'd0;
		end else begin
			case (state)
				IDLE: begin
					done <= 1'b0;
					plot <= 1'b0;
					
					if (start) begin
						state <= INIT;
					end
				end
				
				INIT: begin
					// Initialize Bresenham's algorithm
					curr_x <= x0;
					curr_y <= y0;
					end_x <= x1;
					end_y <= y1;
					
					// Calculate deltas
					dx <= (x1 >= x0) ? (x1 - x0) : (x0 - x1);
					dy <= (y1 >= y0) ? (y1 - y0) : (y0 - y1);
					
					// Calculate step directions
					sx <= (x0 < x1) ? 11'd1 : -11'd1;
					sy <= (y0 < y1) ? 11'd1 : -11'd1;
					
					// Initialize error (standard Bresenham formula)
					error <= dx - dy;
					
					state <= DRAW;
				end
				
				DRAW: begin
					// Output current pixel
					x <= curr_x;
					y <= curr_y;
					plot <= 1'b1;
					
					// Check if we've reached the end point
					if (curr_x == end_x && curr_y == end_y) begin
						state <= DONE;
					end else begin
						// Calculate 2 * error for comparison
						error2 <= error << 1;
						
						// Update position and error based on Bresenham's algorithm
						if ((error << 1) > -dy) begin
							error <= error - dy;
							curr_x <= (sx == 11'd1) ? (curr_x + 10'd1) : (curr_x - 10'd1);
						end
						
						if ((error << 1) < dx) begin
							error <= error + dx;
							curr_y <= (sy == 11'd1) ? (curr_y + 9'd1) : (curr_y - 9'd1);
						end
					end
				end
				
				DONE: begin
					plot <= 1'b0;
					done <= 1'b1;
					state <= IDLE;
				end
				
				default: state <= IDLE;
			endcase
		end
	end

endmodule


/*****************************************************************************
 *                                                                           *
 * Alternative simplified line_drawer using simpler state machine           *
 * This version may be easier to debug if the above has issues              *
 *                                                                           *
 *****************************************************************************/

module line_drawer_simple (
	input wire clk,
	input wire resetn,
	
	// Control signals
	input wire start,
	output reg done,
	
	// Line endpoints
	input wire [9:0] x0, x1,
	input wire [8:0] y0, y1,
	
	// Output pixel
	output reg [9:0] x,
	output reg [8:0] y,
	output reg plot
);

	reg [2:0] state;
	localparam IDLE = 3'd0;
	localparam DRAW = 3'd1;
	localparam DONE = 3'd2;
	
	// Working registers
	reg [9:0] curr_x, target_x;
	reg [8:0] curr_y, target_y;
	reg signed [10:0] dx, dy, sx, sy, err, e2;
	
	always @(posedge clk) begin
		if (!resetn) begin
			state <= IDLE;
			done <= 1'b0;
			plot <= 1'b0;
		end else begin
			case (state)
				IDLE: begin
					done <= 1'b0;
					plot <= 1'b0;
					
					if (start) begin
						// Setup line drawing
						curr_x <= x0;
						curr_y <= y0;
						target_x <= x1;
						target_y <= y1;
						
						// Calculate absolute differences
						dx <= (x1 >= x0) ? (x1 - x0) : (x0 - x1);
						dy <= (y1 >= y0) ? (y1 - y0) : (y0 - y1);
						
						// Determine step direction
						sx <= (x0 < x1) ? 1 : -1;
						sy <= (y0 < y1) ? 1 : -1;
						
						// Initialize error term
						err <= dx - dy;
						
						state <= DRAW;
					end
				end
				
				DRAW: begin
					// Output current pixel
					x <= curr_x;
					y <= curr_y;
					plot <= 1'b1;
					
					if (curr_x == target_x && curr_y == target_y) begin
						state <= DONE;
					end else begin
						// Bresenham's algorithm step
						e2 <= err << 1;  // err * 2
						
						// Adjust X coordinate
						if ((err << 1) > -dy) begin
							err <= err - dy;
							curr_x <= (sx == 1) ? (curr_x + 10'd1) : (curr_x - 10'd1);
						end
						
						// Adjust Y coordinate  
						if ((err << 1) < dx) begin
							err <= err + dx;
							curr_y <= (sy == 1) ? (curr_y + 9'd1) : (curr_y - 9'd1);
						end
					end
				end
				
				DONE: begin
					plot <= 1'b0;
					done <= 1'b1;
					if (!start)  // Wait for start to go low
						state <= IDLE;
				end
			endcase
		end
	end
endmodule
