/*****************************************************************************
 *                                                                           *
 * Module:       Hexadecimal_To_Seven_Segment                               *
 * Description:                                                              *
 *      Converts a 4-bit hexadecimal value to 7-segment display encoding    *
 *                                                                           *
 *****************************************************************************/

module Hexadecimal_To_Seven_Segment (
	// Inputs
	input		[3:0]	hex_number,
	
	// Outputs
	output reg	[6:0]	seven_seg_display
);

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/

// 7-segment encoding (active low for DE-series boards)
// Segments:  6543210
//           .GFEDCBA
//
//     A
//    ---
//  F|   |B
//    -G-
//  E|   |C
//    ---  
//     D

always @(*) begin
	case (hex_number)
		4'h0: seven_seg_display = 7'b1000000;  // 0
		4'h1: seven_seg_display = 7'b1111001;  // 1
		4'h2: seven_seg_display = 7'b0100100;  // 2
		4'h3: seven_seg_display = 7'b0110000;  // 3
		4'h4: seven_seg_display = 7'b0011001;  // 4
		4'h5: seven_seg_display = 7'b0010010;  // 5
		4'h6: seven_seg_display = 7'b0000010;  // 6
		4'h7: seven_seg_display = 7'b1111000;  // 7
		4'h8: seven_seg_display = 7'b0000000;  // 8
		4'h9: seven_seg_display = 7'b0010000;  // 9
		4'hA: seven_seg_display = 7'b0001000;  // A
		4'hB: seven_seg_display = 7'b0000011;  // b
		4'hC: seven_seg_display = 7'b1000110;  // C
		4'hD: seven_seg_display = 7'b0100001;  // d
		4'hE: seven_seg_display = 7'b0000110;  // E
		4'hF: seven_seg_display = 7'b0001110;  // F
	endcase
end

endmodule

