/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Mouse_Simulator                                        *
 * Description:                                                              *
 *      Simulates PS/2 mouse behavior for testbench purposes                *
 *      Generates PS/2 protocol signals with mouse movement packets         *
 *                                                                           *
 *****************************************************************************/

module PS2_Mouse_Simulator (
	input				clk,
	input				reset,
	
	// PS/2 interface (tristated in real hardware, driven here for simulation)
	output reg			ps2_clk,
	output reg			ps2_dat
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

localparam	IDLE = 3'd0;
localparam	START_BIT = 3'd1;
localparam	DATA_BITS = 3'd2;
localparam	PARITY_BIT = 3'd3;
localparam	STOP_BIT = 3'd4;
localparam	WAIT_STATE = 3'd5;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

reg [2:0] state;
reg [3:0] bit_count;
reg [7:0] current_byte;
reg [1:0] byte_index;
reg [31:0] wait_counter;
reg [31:0] clk_counter;

// Mouse packet (3 bytes)
reg [7:0] packet [0:2];

// Movement pattern variables
reg [31:0] time_counter;
reg signed [8:0] mouse_dx, mouse_dy;
reg move_right;
reg left_button;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Generate simple circular mouse movement pattern for testing
always @(posedge clk) begin
	if (reset) begin
		time_counter <= 0;
		move_right <= 1;
		left_button <= 1;  // Start with button pressed to draw
	end else begin
		time_counter <= time_counter + 1;
		
		// Change direction every 1000000 cycles (20ms at 50MHz)
		if (time_counter >= 1000000) begin
			time_counter <= 0;
			move_right <= ~move_right;
		end
		
		// Toggle button every 2000000 cycles to show draw/erase
		if (time_counter == 2000000) begin
			left_button <= ~left_button;
		end
	end
end

// Calculate mouse deltas based on pattern
always @(*) begin
	if (move_right) begin
		mouse_dx = 9'sd2;  // Move right
		mouse_dy = 9'sd1;  // Move down slightly
	end else begin
		mouse_dx = -9'sd2; // Move left
		mouse_dy = -9'sd1; // Move up slightly
	end
end

// Build mouse packet
always @(posedge clk) begin
	if (reset) begin
		packet[0] <= 8'h08;  // Status byte: bit 3 always 1, no buttons pressed
		packet[1] <= 8'h00;  // X movement
		packet[2] <= 8'h00;  // Y movement
	end else begin
		// Byte 0: Status byte
		// Bit 0: Left button (1 = pressed)
		// Bit 1: Right button
		// Bit 2: Middle button
		// Bit 3: Always 1
		// Bit 4: X sign bit
		// Bit 5: Y sign bit
		// Bit 6: X overflow
		// Bit 7: Y overflow
		packet[0] <= {1'b0, 1'b0, mouse_dy[8], mouse_dx[8], 1'b1, 1'b0, 1'b0, left_button};
		packet[1] <= mouse_dx[7:0];  // X movement
		packet[2] <= mouse_dy[7:0];  // Y movement
	end
end

// PS/2 clock generation and data transmission
always @(posedge clk) begin
	if (reset) begin
		state <= IDLE;
		ps2_clk <= 1'b1;
		ps2_dat <= 1'b1;
		bit_count <= 0;
		byte_index <= 0;
		wait_counter <= 0;
		clk_counter <= 0;
		current_byte <= 8'h00;
	end else begin
		case (state)
			IDLE: begin
				ps2_clk <= 1'b1;
				ps2_dat <= 1'b1;
				wait_counter <= wait_counter + 1;
				
				// Send packet every 10000 cycles (~200us at 50MHz)
				if (wait_counter >= 10000) begin
					wait_counter <= 0;
					byte_index <= 0;
					current_byte <= packet[0];
					state <= START_BIT;
					clk_counter <= 0;
				end
			end
			
			START_BIT: begin
				clk_counter <= clk_counter + 1;
				if (clk_counter == 0) begin
					ps2_dat <= 1'b0;  // Start bit
					ps2_clk <= 1'b1;
				end else if (clk_counter == 50) begin
					ps2_clk <= 1'b0;  // Clock low
				end else if (clk_counter == 100) begin
					ps2_clk <= 1'b1;  // Clock high
					clk_counter <= 0;
					bit_count <= 0;
					state <= DATA_BITS;
				end
			end
			
			DATA_BITS: begin
				clk_counter <= clk_counter + 1;
				if (clk_counter == 0) begin
					ps2_dat <= current_byte[bit_count];
					ps2_clk <= 1'b1;
				end else if (clk_counter == 50) begin
					ps2_clk <= 1'b0;  // Clock low
				end else if (clk_counter == 100) begin
					ps2_clk <= 1'b1;  // Clock high
					clk_counter <= 0;
					
					if (bit_count == 7) begin
						state <= PARITY_BIT;
					end else begin
						bit_count <= bit_count + 1;
					end
				end
			end
			
			PARITY_BIT: begin
				clk_counter <= clk_counter + 1;
				if (clk_counter == 0) begin
					// Odd parity
					ps2_dat <= ~(^current_byte);
					ps2_clk <= 1'b1;
				end else if (clk_counter == 50) begin
					ps2_clk <= 1'b0;  // Clock low
				end else if (clk_counter == 100) begin
					ps2_clk <= 1'b1;  // Clock high
					clk_counter <= 0;
					state <= STOP_BIT;
				end
			end
			
			STOP_BIT: begin
				clk_counter <= clk_counter + 1;
				if (clk_counter == 0) begin
					ps2_dat <= 1'b1;  // Stop bit
					ps2_clk <= 1'b1;
				end else if (clk_counter == 50) begin
					ps2_clk <= 1'b0;  // Clock low
				end else if (clk_counter == 100) begin
					ps2_clk <= 1'b1;  // Clock high
					clk_counter <= 0;
					
					if (byte_index == 2) begin
						// Completed all 3 bytes
						state <= IDLE;
						wait_counter <= 0;
					end else begin
						// Move to next byte
						byte_index <= byte_index + 1;
						current_byte <= packet[byte_index + 1];
						state <= WAIT_STATE;
						wait_counter <= 0;
					end
				end
			end
			
			WAIT_STATE: begin
				ps2_clk <= 1'b1;
				ps2_dat <= 1'b1;
				wait_counter <= wait_counter + 1;
				
				// Small delay between bytes
				if (wait_counter >= 500) begin
					wait_counter <= 0;
					state <= START_BIT;
					clk_counter <= 0;
				end
			end
		endcase
	end
end

endmodule

