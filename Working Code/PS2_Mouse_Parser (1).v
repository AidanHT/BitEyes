/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Mouse_Parser                                            *
 * Description:                                                              *
 *      This module parses 3-byte mouse packets from PS/2 mouse data.       *
 *      Mouse packet format:                                                 *
 *      Byte 0: [Y_OVF X_OVF Y_SIGN X_SIGN 1 M R L]                         *
 *      Byte 1: X movement (8-bit)                                           *
 *      Byte 2: Y movement (8-bit)                                           *
 *                                                                           *
 *****************************************************************************/

module PS2_Mouse_Parser (
    input clk, 
    input rst,
    input [7:0] ps2_byte, 
    input ps2_byte_en,
    output reg [8:0] delta_x, 
    output reg [8:0] delta_y,
    output reg [2:0] buttons, 
    output reg packet_ready
);

/*****************************************************************************
 *                           Constant Declarations                           *
 *****************************************************************************/
localparam BYTE_0 = 2'b00;  // Status byte
localparam BYTE_1 = 2'b01;  // X movement
localparam BYTE_2 = 2'b10;  // Y movement

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/
reg [1:0] byte_counter = BYTE_0;
reg [7:0] status_byte = 8'h00; // Holds the first byte (status byte)
reg [7:0] x_byte = 8'h00; // Holds the second byte (X movement)
reg [7:0] y_byte = 8'h00; // Holds the third byte (Y movement)

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Byte counter to track which byte of the 3-byte packet we're receiving
always @(posedge clk) begin
    if (rst) begin
        byte_counter <= BYTE_0;
    end else if (ps2_byte_en) begin
        // Check if this is a valid status byte (bit 3 must be 1)
        if (byte_counter == BYTE_0) begin
            if (ps2_byte[3] == 1'b1)
                byte_counter <= BYTE_1;
            else
                byte_counter <= BYTE_0;  // Stay in BYTE_0 if invalid
        end else if (byte_counter == BYTE_1) begin
            byte_counter <= BYTE_2;
        end else if (byte_counter == BYTE_2) begin
            byte_counter <= BYTE_0;
        end
    end
end

// Capture the three bytes of the mouse packet
always @(posedge clk) begin
    if (rst) begin
        status_byte <= 8'h00;
        x_byte <= 8'h00;
        y_byte <= 8'h00;
    end else if (ps2_byte_en) begin
        case (byte_counter)
            BYTE_0: begin
                if (ps2_byte[3] == 1'b1)  // Valid status byte
                    status_byte <= ps2_byte;
            end
            BYTE_1: begin
                x_byte <= ps2_byte;
            end
            BYTE_2: begin
                y_byte <= ps2_byte;
            end
            default: begin
                // Do nothing
            end
        endcase
    end
end

// Generate packet_ready pulse when complete packet is received
always @(posedge clk) begin
    if (rst) begin
        packet_ready <= 1'b0;
    end else begin
        packet_ready <= (ps2_byte_en && (byte_counter == BYTE_2));
    end
end

// Extract button states and movement data
always @(posedge clk) begin
    if (rst) begin
        buttons <= 3'b000;
        delta_x <= 9'h000;
        delta_y <= 9'h000;
    end else if (ps2_byte_en && (byte_counter == BYTE_2)) begin
        // Extract button states from status byte
        // Bit 0: Left button, Bit 1: Right button, Bit 2: Middle button
        buttons <= status_byte[2:0];
        
        // Extract X movement with sign extension
        // Bit 4 of status byte is X sign bit
        if (status_byte[4] == 1'b1)
            delta_x <= {1'b1, x_byte};  // Negative movement
        else
            delta_x <= {1'b0, x_byte};  // Positive movement
            
        // Extract Y movement with sign extension
        // Bit 5 of status byte is Y sign bit
        if (status_byte[5] == 1'b1)
            delta_y <= {1'b1, y_byte};  // Negative movement
        else
            delta_y <= {1'b0, y_byte};  // Positive movement
    end
end

endmodule
