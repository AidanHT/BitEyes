
// Parses the PS2 outputs into named channels for better processing
module PS2_Mouse_Parser (
	input CLOCK_50,
	input reset,
	input [7:0] ps2_received_data,
	input ps2_received_data_en,
	
	output reg left_button,
	output reg right_button,
	output reg middle_button,
	output reg [8:0] mouse_delta_x, // 9-bit signed X movement
	output reg [8:0] mouse_delta_y, // 9-bit signed Y movement
	output reg mouse_data_valid // 1 when complete packet received
);

reg [1:0] byte_counter; // Tracks which byte its receiving (0, 1, or 2)
reg [7:0] byte0_reg; // button states
reg [7:0] byte1_reg; // X movement
reg [7:0] byte2_reg; // Y movement

// Simple FSM for getting the data from the one ps2_received_data channel
// PS/2 mouse sends 3-byte packets: [status][delta_x][delta_y]
// Status byte: bit 0=left, bit 1=right, bit 2=middle, bit 3=always 1, 
//              bit 4=x_sign, bit 5=y_sign, bit 6=x_overflow, bit 7=y_overflow
always @(posedge CLOCK_50) begin
	if (reset) begin
		byte_counter <= 2'b00;
		byte0_reg <= 8'h00;
		byte1_reg <= 8'h00;
		byte2_reg <= 8'h00;
		mouse_data_valid <= 1'b0;
		left_button <= 1'b0;
		right_button <= 1'b0;
		middle_button <= 1'b0;
		mouse_delta_x <= 9'b0;
		mouse_delta_y <= 9'b0;
	end
	else begin
		mouse_data_valid <= 1'b0; // Default to "data not valid"
	
		if (ps2_received_data_en) begin
			case (byte_counter)
				2'b00: begin
					// Accept first byte as status byte if bit 3 is set (standard PS/2 mouse protocol)
					if (ps2_received_data[3] == 1'b1) begin
						byte0_reg <= ps2_received_data;
						byte_counter <= 2'b01;
						// Don't update buttons yet - wait for complete packet to avoid flickering
					end
					// If bit 3 not set, ignore this byte and wait for valid status byte
				end
				2'b01: begin
					// Gets X movement (second byte) - accept any byte here
					byte1_reg <= ps2_received_data;
					byte_counter <= 2'b10;
				end
				2'b10: begin
					// Gets Y movement (third byte) and completes packet
					byte2_reg <= ps2_received_data;
					byte_counter <= 2'b00;
					
					// Update button states only when complete packet is received
					// This ensures stable button states and prevents flickering
					left_button <= byte0_reg[0];
					right_button <= byte0_reg[1];
					middle_button <= byte0_reg[2];
					
					// Construct 9-bit signed movement values
					// bit 4 of status byte is X sign, bit 5 is Y sign
					mouse_delta_x <= {byte0_reg[4], byte1_reg};
					mouse_delta_y <= {byte0_reg[5], byte2_reg};
					
					// Signal that complete packet is ready (for position updates)
					mouse_data_valid <= 1'b1;
				end
			endcase
		end
		end
end

endmodule
