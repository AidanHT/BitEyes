module BackgroundROM (
    input clock,
    input [16:0] address,
    output reg [8:0] q
);

    // Infers a ROM block initialized with your MIF file
    altsyncram #(
        .operation_mode("ROM"),
        .width_a(9),
        .widthad_a(17),
        .numwords_a(76800), // 320 * 240
        .lpm_type("altsyncram"),
        .init_file("bmp_320_9.mif") 
    ) altsyncram_component (
        .clock0(clock),
        .address_a(address),
        .q_a(q),
        .clock1(1'b1), 
        .address_b(1'b1), 
        .q_b(), 
        .wren_a(1'b0),
        .wren_b(1'b0)
    );

endmodule
