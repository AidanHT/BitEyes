/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Mouse_Parser                                           *
 * Description:                                                              *
 *      Parses PS/2 mouse data packets into movement and button information *
 *      Standard PS/2 mouse sends 3-byte packets                            *
 *                                                                           *
 *****************************************************************************/

module PS2_Mouse_Parser (
	// Inputs
	input				clk,
	input				rst,
	input		[7:0]	ps2_byte,
	input				ps2_byte_en,
	
	// Outputs
	output reg signed	[8:0]	delta_x,
	output reg signed	[8:0]	delta_y,
	output reg			[2:0]	buttons,
	output reg					packet_ready
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

// Packet byte positions
localparam	BYTE_0	= 2'd0;		// Status byte with buttons
localparam	BYTE_1	= 2'd1;		// X movement
localparam	BYTE_2	= 2'd2;		// Y movement

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Packet state
reg		[1:0]	byte_count;

// Packet data storage
reg		[7:0]	packet_byte0;
reg		[7:0]	packet_byte1;
reg		[7:0]	packet_byte2;

// Movement overflow flags
wire			x_overflow;
wire			y_overflow;
wire			x_sign;
wire			y_sign;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Packet assembly state machine
always @(posedge clk) begin
	if (rst) begin
		byte_count <= BYTE_0;
		packet_byte0 <= 8'h00;
		packet_byte1 <= 8'h00;
		packet_byte2 <= 8'h00;
		packet_ready <= 1'b0;
		delta_x <= 9'd0;
		delta_y <= 9'd0;
		buttons <= 3'b000;
		
	end else begin
		packet_ready <= 1'b0;
		
		if (ps2_byte_en) begin
			case (byte_count)
				BYTE_0: begin
					// First byte: check if it's a valid status byte
					// Bit 3 should always be 1 for valid mouse packets
					if (ps2_byte[3]) begin
						packet_byte0 <= ps2_byte;
						byte_count <= BYTE_1;
					end else begin
						// Invalid packet, stay at BYTE_0
						byte_count <= BYTE_0;
					end
				end
				
				BYTE_1: begin
					// Second byte: X movement
					packet_byte1 <= ps2_byte;
					byte_count <= BYTE_2;
				end
				
				BYTE_2: begin
					// Third byte: Y movement
					packet_byte2 <= ps2_byte;
					byte_count <= BYTE_0;
					packet_ready <= 1'b1;
					
					// Extract button states from byte 0
					// Bit 0: Left button
					// Bit 1: Right button
					// Bit 2: Middle button
					buttons <= packet_byte0[2:0];
					
					// Extract movement with sign extension
					// Byte 0 bits: [7:6] = Y/X overflow, [5:4] = Y/X sign
					// Sign extend the 8-bit movement to 9 bits
					if (packet_byte0[6]) begin
						// X overflow
						delta_x <= packet_byte0[4] ? -9'd255 : 9'd255;
					end else begin
						// Normal X movement with sign extension
						delta_x <= {packet_byte0[4], ps2_byte[7:0]};
					end
					
					if (packet_byte0[7]) begin
						// Y overflow
						delta_y <= packet_byte0[5] ? -9'd255 : 9'd255;
					end else begin
						// Normal Y movement with sign extension
						delta_y <= {packet_byte0[5], packet_byte2[7:0]};
					end
				end
				
				default: begin
					byte_count <= BYTE_0;
				end
			endcase
		end
	end
end

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/

// Extract overflow and sign bits
assign x_overflow = packet_byte0[6];
assign y_overflow = packet_byte0[7];
assign x_sign = packet_byte0[4];
assign y_sign = packet_byte0[5];

endmodule

