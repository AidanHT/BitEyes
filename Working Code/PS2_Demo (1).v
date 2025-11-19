/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Demo                                                    *
 * Description:                                                              *
 *      This module demonstrates PS/2 mouse functionality by displaying      *
 *      received scan codes on HEX displays.                                 *
 *                                                                           *
 *****************************************************************************/

module PS2_Demo (
	// Inputs
	CLOCK_50,
	KEY,

	// Bidirectionals
	PS2_CLK,
	PS2_DAT,
	
	// Outputs
	HEX0,
	HEX1,
	HEX2,
	HEX3,
	HEX4,
	HEX5,
	HEX6,
	HEX7
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/


/*****************************************************************************
 *                             Port Declarations                             *
 *****************************************************************************/

// Inputs
input				CLOCK_50;
input		[3:0]	KEY;

// Bidirectionals
inout				PS2_CLK;
inout				PS2_DAT;

// Outputs
output		[6:0]	HEX0;
output		[6:0]	HEX1;
output		[6:0]	HEX2;
output		[6:0]	HEX3;
output		[6:0]	HEX4;
output		[6:0]	HEX5;
output		[6:0]	HEX6;
output		[6:0]	HEX7;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Internal Wires - PS/2 Controller
wire		[7:0]	ps2_byte;
wire				ps2_byte_en;

// Internal Wires - Mouse Parser
wire		[8:0]	delta_x;
wire		[8:0]	delta_y;
wire		[2:0]	buttons;
wire				packet_ready;

// Internal Registers
reg			[7:0]	last_data_received;
reg			[7:0]	byte_count;

// State Machine Registers

/*****************************************************************************
 *                         Finite State Machine(s)                           *
 *****************************************************************************/


/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Capture last received byte for display on HEX
always @(posedge CLOCK_50)
begin
	if (KEY[0] == 1'b0) begin
		last_data_received <= 8'h00;
		byte_count <= 8'h00;
	end else if (ps2_byte_en == 1'b1) begin
		last_data_received <= ps2_byte;
		byte_count <= byte_count + 8'h01;
	end
end

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/

// Display byte count on HEX2 and HEX3
// Display parsed mouse data on HEX4-HEX7 when packet is ready
// HEX0-HEX1 show the last received byte (scan code)
// Set unused HEX displays to blank
assign HEX4 = 7'h7F;
assign HEX5 = 7'h7F;
assign HEX6 = 7'h7F;
assign HEX7 = 7'h7F;

/*****************************************************************************
 *                              Internal Modules                             *
 *****************************************************************************/

// PS/2 Controller with mouse initialization enabled
PS2_Controller #(.INITIALIZE_MOUSE(1)) PS2 (
	// Inputs
	.CLOCK_50				(CLOCK_50),
	.reset					(~KEY[0]),
	.the_command			(8'h00),
	.send_command			(1'b0),

	// Bidirectionals
	.PS2_CLK				(PS2_CLK),
 	.PS2_DAT				(PS2_DAT),

	// Outputs
	.received_data			(ps2_byte),
	.received_data_en		(ps2_byte_en),
	.command_was_sent		(),
	.error_communication_timed_out()
);

// Mouse parser to decode 3-byte mouse packets
PS2_Mouse_Parser parser (
    .clk					(CLOCK_50), 
    .rst					(~KEY[0]),
    .ps2_byte				(ps2_byte), 
    .ps2_byte_en			(ps2_byte_en),
    .delta_x				(delta_x), 
    .delta_y				(delta_y),
    .buttons				(buttons), 
    .packet_ready			(packet_ready)
);
/*
// DEBUGGING: Display last received byte and byte count on HEX displays
// HEX0: Display lower nibble of last received byte
Hexadecimal_To_Seven_Segment Segment0 (
	// Inputs
	.hex_number				(last_data_received[3:0]),

	// Outputs
	.seven_seg_display		(HEX0)
);

// HEX1: Display upper nibble of last received byte
Hexadecimal_To_Seven_Segment Segment1 (
	// Inputs
	.hex_number				(last_data_received[7:4]),

	// Outputs
	.seven_seg_display		(HEX1)
);

// HEX2: Display lower nibble of byte count
Hexadecimal_To_Seven_Segment Segment2 (
	// Inputs
	.hex_number				(byte_count[3:0]),

	// Outputs
	.seven_seg_display		(HEX2)
);

// HEX3: Display upper nibble of byte count
Hexadecimal_To_Seven_Segment Segment3 (
	// Inputs
	.hex_number				(byte_count[7:4]),

	// Outputs
	.seven_seg_display		(HEX3)
);
*/
endmodule
