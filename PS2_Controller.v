/*****************************************************************************
 *                                                                           *
 * Module:       PS2_Controller                                             *
 * Description:                                                              *
 *      PS/2 Controller for keyboard and mouse communication                *
 *      Handles bidirectional PS/2 protocol with clock and data lines       *
 *                                                                           *
 *****************************************************************************/

module PS2_Controller #(
	parameter INITIALIZE_MOUSE = 0
) (
	// Inputs
	input				CLOCK_50,
	input				reset,
	input		[7:0]	the_command,
	input				send_command,
	
	// Bidirectionals
	inout				PS2_CLK,
	inout				PS2_DAT,
	
	// Outputs
	output reg	[7:0]	received_data,
	output reg			received_data_en,
	output reg			command_was_sent,
	output reg			error_communication_timed_out
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

// Timing constants for PS/2 protocol
localparam	CLOCK_CYCLES_FOR_101US	= 5050;
localparam	DATA_WIDTH_FOR_101US	= 13;
localparam	CLOCK_CYCLES_FOR_15MS	= 750000;
localparam	DATA_WIDTH_FOR_15MS		= 20;
localparam	DEBOUNCE_COUNTER_SIZE	= 4;

// States
localparam	PS2_STATE_0_IDLE					= 3'd0;
localparam	PS2_STATE_1_DATA_IN					= 3'd1;
localparam	PS2_STATE_2_COMMAND_OUT				= 3'd2;
localparam	PS2_STATE_3_END_TRANSFER			= 3'd3;
localparam	PS2_STATE_4_END_DELAYED				= 3'd4;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Internal state
reg			[2:0]	ns_ps2_transceiver;
reg			[2:0]	s_ps2_transceiver;

// Data
reg			[7:0]	data_from_ps2;
reg			[7:0]	data_to_ps2;

// Bit counter
reg			[3:0]	data_count;
reg			[3:0]	bit_count;

// Parity
reg					parity_error;

// PS/2 clock and data
reg					ps2_clk_reg;
reg					ps2_dat_reg;
wire				ps2_clk_negedge;

// Debounce
reg			[DEBOUNCE_COUNTER_SIZE:0]	clk_debounce_counter;
reg										ps2_clk_debounced;

// Timeout counter
reg			[DATA_WIDTH_FOR_15MS:0]		command_timeout_counter;
reg										command_timed_out;

// Initialization
reg										initialize;
reg			[1:0]						init_step;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// PS/2 clock edge detection
always @(posedge CLOCK_50) begin
	if (reset) begin
		ps2_clk_reg <= 1'b1;
	end else begin
		ps2_clk_reg <= PS2_CLK;
	end
end

assign ps2_clk_negedge = ps2_clk_reg & ~PS2_CLK;

// Main state machine
always @(posedge CLOCK_50) begin
	if (reset) begin
		s_ps2_transceiver <= PS2_STATE_0_IDLE;
	end else begin
		s_ps2_transceiver <= ns_ps2_transceiver;
	end
end

// Debounce counter
always @(posedge CLOCK_50) begin
	if (reset) begin
		clk_debounce_counter <= {(DEBOUNCE_COUNTER_SIZE+1){1'b0}};
		ps2_clk_debounced <= 1'b1;
	end else if (PS2_CLK == 1'b0) begin
		clk_debounce_counter <= {(DEBOUNCE_COUNTER_SIZE+1){1'b0}};
		ps2_clk_debounced <= 1'b0;
	end else if (clk_debounce_counter == {(DEBOUNCE_COUNTER_SIZE+1){1'b1}}) begin
		ps2_clk_debounced <= 1'b1;
	end else begin
		clk_debounce_counter <= clk_debounce_counter + 1;
	end
end

// Data reception and transmission
always @(posedge CLOCK_50) begin
	if (reset) begin
		data_from_ps2 <= 8'h00;
		data_to_ps2 <= 8'h00;
		bit_count <= 4'd0;
		received_data <= 8'h00;
		received_data_en <= 1'b0;
		command_was_sent <= 1'b0;
		error_communication_timed_out <= 1'b0;
		parity_error <= 1'b0;
		
	end else begin
		received_data_en <= 1'b0;
		command_was_sent <= 1'b0;
		error_communication_timed_out <= command_timed_out;
		
		case (s_ps2_transceiver)
			PS2_STATE_0_IDLE: begin
				bit_count <= 4'd0;
				if (send_command) begin
					data_to_ps2 <= the_command;
				end
			end
			
			PS2_STATE_1_DATA_IN: begin
				if (ps2_clk_negedge) begin
					case (bit_count)
						4'd0: begin
							// Start bit
							parity_error <= 1'b0;
							bit_count <= bit_count + 1;
						end
						4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin
							// Data bits
							data_from_ps2[bit_count - 1] <= PS2_DAT;
							bit_count <= bit_count + 1;
						end
						4'd9: begin
							// Parity bit
							parity_error <= ~(PS2_DAT ^ data_from_ps2[0] ^ data_from_ps2[1] ^ 
							                 data_from_ps2[2] ^ data_from_ps2[3] ^ data_from_ps2[4] ^ 
							                 data_from_ps2[5] ^ data_from_ps2[6] ^ data_from_ps2[7]);
							bit_count <= bit_count + 1;
						end
						4'd10: begin
							// Stop bit
							if (!parity_error && PS2_DAT) begin
								received_data <= data_from_ps2;
								received_data_en <= 1'b1;
							end
							bit_count <= 4'd0;
						end
					endcase
				end
			end
			
			PS2_STATE_2_COMMAND_OUT: begin
				// Send command (simplified - host to device communication)
				if (ps2_clk_negedge) begin
					bit_count <= bit_count + 1;
				end
			end
			
			PS2_STATE_3_END_TRANSFER: begin
				command_was_sent <= 1'b1;
				bit_count <= 4'd0;
			end
			
			PS2_STATE_4_END_DELAYED: begin
				bit_count <= 4'd0;
			end
		endcase
	end
end

// Timeout counter
always @(posedge CLOCK_50) begin
	if (reset) begin
		command_timeout_counter <= {(DATA_WIDTH_FOR_15MS+1){1'b0}};
		command_timed_out <= 1'b0;
	end else begin
		if (s_ps2_transceiver == PS2_STATE_2_COMMAND_OUT) begin
			if (command_timeout_counter == CLOCK_CYCLES_FOR_15MS) begin
				command_timed_out <= 1'b1;
			end else begin
				command_timeout_counter <= command_timeout_counter + 1;
			end
		end else begin
			command_timeout_counter <= {(DATA_WIDTH_FOR_15MS+1){1'b0}};
			command_timed_out <= 1'b0;
		end
	end
end

// Mouse initialization
always @(posedge CLOCK_50) begin
	if (reset) begin
		initialize <= INITIALIZE_MOUSE;
		init_step <= 2'd0;
	end else begin
		if (initialize && received_data_en) begin
			init_step <= init_step + 1;
			if (init_step == 2'd3) begin
				initialize <= 1'b0;
			end
		end
	end
end

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/

// Next state logic
always @(*) begin
	case (s_ps2_transceiver)
		PS2_STATE_0_IDLE: begin
			if ((ps2_clk_debounced == 1'b0) && (PS2_DAT == 1'b0)) begin
				ns_ps2_transceiver = PS2_STATE_1_DATA_IN;
			end else if (send_command) begin
				ns_ps2_transceiver = PS2_STATE_2_COMMAND_OUT;
			end else begin
				ns_ps2_transceiver = PS2_STATE_0_IDLE;
			end
		end
		
		PS2_STATE_1_DATA_IN: begin
			if ((bit_count == 4'd10) && ps2_clk_negedge) begin
				ns_ps2_transceiver = PS2_STATE_0_IDLE;
			end else begin
				ns_ps2_transceiver = PS2_STATE_1_DATA_IN;
			end
		end
		
		PS2_STATE_2_COMMAND_OUT: begin
			if ((bit_count == 4'd11) && ps2_clk_negedge) begin
				ns_ps2_transceiver = PS2_STATE_3_END_TRANSFER;
			end else if (command_timed_out) begin
				ns_ps2_transceiver = PS2_STATE_0_IDLE;
			end else begin
				ns_ps2_transceiver = PS2_STATE_2_COMMAND_OUT;
			end
		end
		
		PS2_STATE_3_END_TRANSFER: begin
			ns_ps2_transceiver = PS2_STATE_4_END_DELAYED;
		end
		
		PS2_STATE_4_END_DELAYED: begin
			ns_ps2_transceiver = PS2_STATE_0_IDLE;
		end
		
		default: begin
			ns_ps2_transceiver = PS2_STATE_0_IDLE;
		end
	endcase
end

/*****************************************************************************
 *                              Bidirectional I/O                            *
 *****************************************************************************/

// PS/2 clock and data are open-drain, pull high when not driven
assign PS2_CLK = (s_ps2_transceiver == PS2_STATE_2_COMMAND_OUT) ? 1'b0 : 1'bz;
assign PS2_DAT = (s_ps2_transceiver == PS2_STATE_2_COMMAND_OUT) ? 
                 data_to_ps2[bit_count] : 1'bz;

endmodule

