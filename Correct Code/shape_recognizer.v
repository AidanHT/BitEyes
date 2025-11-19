`timescale 1ns/1ns
`default_nettype none

// ============================================================================
// shape_recognizer.v
//
// Shape recognition module for 320x240 canvas with single-port M10K BRAM
// Implements feature extraction and classification for:
//   - Rectangle, Square, Triangle, Circle detection
//
// Strict Verilog-2001 compliance with single-driver discipline
// ============================================================================

module shape_recognizer (
    input  wire        clk,
    input  wire        reset_n,           // active-low synchronous reset

    // Drawing interface (from drawing engine)
    input  wire        draw_en,           // 1-cycle pulse: write a pixel
    input  wire [8:0]  draw_x,            // 0..319
    input  wire [7:0]  draw_y,            // 0..239
    input  wire        draw_pixel_on,     // 1 = set pixel to 1, 0 = set pixel to 0

    // Control interface
    input  wire        clear_canvas,      // request to clear entire buffer
    input  wire        start_recognition, // request shape recognition

    // Status / results
    output reg         busy,              // module is busy (clear or analysis)
    output reg         recognition_done,  // 1-cycle pulse when classification complete
    output reg  [2:0]  detected_shape,    // shape encoding
    output reg  [7:0]  confidence         // 0..255 confidence score
);

    // =========================================================
    // 1) Localparams (shape encodings, state encodings)
    // =========================================================
    
    // Shape encodings
    localparam [2:0]
        SHAPE_NONE      = 3'd0,
        SHAPE_RECTANGLE = 3'd1,
        SHAPE_SQUARE    = 3'd2,
        SHAPE_TRIANGLE  = 3'd3,
        SHAPE_CIRCLE    = 3'd4;
    
    // Main control FSM states
    localparam [1:0]
        MAIN_IDLE    = 2'd0,
        MAIN_DRAW    = 2'd1,
        MAIN_ANALYZE = 2'd2,
        MAIN_DONE    = 2'd3;
    
    // Feature extraction FSM states
    localparam [2:0]
        FE_IDLE        = 3'd0,
        FE_INIT        = 3'd1,
        FE_SCAN_ADDR   = 3'd2,
        FE_SCAN_WAIT   = 3'd3,
        FE_SCAN_PROC   = 3'd4,
        FE_DONE        = 3'd5;
    
    // Classification pipeline stages
    localparam [2:0]
        CL_IDLE        = 3'd0,
        CL_LATCH       = 3'd1,
        CL_CALC_AREA   = 3'd2,
        CL_CALC_RATIOS = 3'd3,
        CL_CLASSIFY    = 3'd4,
        CL_DONE        = 3'd5;

    // =========================================================
    // 2) Shadow Buffer BRAM Interface
    // =========================================================
    reg  [14:0] mem_addr;
    reg         mem_write_en;
    reg         mem_write_data;
    reg         mem_read_data;

    wire vcc, gnd;
    assign vcc = 1'b1;
    assign gnd = 1'b0;

    // =========================================================
    // 3) BRAM Block - Single-Port altsyncram Megafunction
    // =========================================================
    altsyncram shadow_buffer_ram (
        .wren_a(mem_write_en),
        .clock0(clk),
        .clocken0(vcc),
        .address_a(mem_addr),
        .data_a(mem_write_data),
        .q_a(mem_read_data)
    );
    defparam
        shadow_buffer_ram.width_a = 1,
        shadow_buffer_ram.widthad_a = 15,
        shadow_buffer_ram.numwords_a = 19200,
        shadow_buffer_ram.intended_device_family = "Cyclone V",
        shadow_buffer_ram.operation_mode = "SINGLE_PORT",
        shadow_buffer_ram.outdata_reg_a = "UNREGISTERED",
        shadow_buffer_ram.ram_block_type = "M10K",
        shadow_buffer_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        shadow_buffer_ram.power_up_uninitialized = "FALSE",
        shadow_buffer_ram.init_file = "UNUSED";

    // =========================================================
    // 4) Main FSM, Clear Logic
    // =========================================================
    reg [1:0] main_state;
    reg       clearing_active;
    reg [14:0] clear_addr;
    
    // Flag to trigger FE FSM start
    reg fe_start_request;
    
    // Main control FSM
    always @(posedge clk) begin
        if (!reset_n) begin
            main_state <= MAIN_IDLE;
            clearing_active <= 1'b0;
            clear_addr <= 15'd0;
            fe_start_request <= 1'b0;
        end else begin
            // Default
            fe_start_request <= 1'b0;
            
            case (main_state)
                MAIN_IDLE: begin
                    // Handle clear request
                    if (clear_canvas && !clearing_active) begin
                        clearing_active <= 1'b1;
                        clear_addr <= 17'd0;
                    end
                    
                    // Handle recognition start
                    if (start_recognition && !clearing_active) begin
                        main_state <= MAIN_ANALYZE;
                        fe_start_request <= 1'b1;
                    end
                end
                
                MAIN_DRAW: begin
                    // Drawing state (currently similar to IDLE)
                    // Could transition here for explicit draw mode if needed
                    main_state <= MAIN_IDLE;
                end
                
                MAIN_ANALYZE: begin
                    // Wait for classification to complete
                    if (recognition_done) begin
                        main_state <= MAIN_DONE;
                    end
                end
                
                MAIN_DONE: begin
                    // Wait for start_recognition to deassert
                    if (!start_recognition) begin
                        main_state <= MAIN_IDLE;
                    end
                end
                
                default: main_state <= MAIN_IDLE;
            endcase
            
            // Clear logic - runs independently
            if (clearing_active) begin
                if (clear_addr == 15'd19199) begin
                    clearing_active <= 1'b0;
                    clear_addr <= 15'd0;
                end else begin
                    clear_addr <= clear_addr + 15'd1;
                end
            end
        end
    end

    // =========================================================
    // 5) BRAM Arbiter - Priority: Clear > Draw > Scan
    // =========================================================
    
    // Address computation wires
    wire [14:0] draw_addr;
    wire [14:0] scan_addr;
    
    // Scale coordinates from 320x240 to 160x120 by dividing by 2
    assign draw_addr = ((draw_y >> 1) * 8'd160) + (draw_x >> 1);
    
    // Scan address computation
    reg [7:0] scan_x;
    reg [6:0] scan_y;
    assign scan_addr = (scan_y * 8'd160) + scan_x;
    
    // Arbiter - single driver for mem_addr, mem_write_en, mem_write_data
    always @(posedge clk) begin
        if (!reset_n) begin
            mem_addr <= 15'd0;
            mem_write_en <= 1'b0;
            mem_write_data <= 1'b0;
        end else begin
            // Default: no write
            mem_write_en <= 1'b0;
            mem_write_data <= 1'b0;
            
            // Priority 1: Clear
            if (clearing_active) begin
                mem_addr <= clear_addr;
                mem_write_en <= 1'b1;
                mem_write_data <= 1'b0;
            end
            // Priority 2: Draw
            else if (draw_en && (main_state == MAIN_IDLE || main_state == MAIN_DRAW)) begin
                mem_addr <= draw_addr;
                mem_write_en <= 1'b1;
                mem_write_data <= draw_pixel_on;
            end
            // Priority 3: Feature extraction scan (read only)
            else if (fe_state == FE_SCAN_ADDR) begin
                mem_addr <= scan_addr;
                mem_write_en <= 1'b0;
            end
            // Else maintain current address for passive reads
        end
    end

    // =========================================================
    // 6) Feature Extraction FSM and Feature Registers
    // =========================================================
    reg [2:0] fe_state;
    reg [14:0] pixel_count;
    reg [7:0] bbox_min_x, bbox_max_x;
    reg [6:0] bbox_min_y, bbox_max_y;
    reg [8:0] bbox_width, bbox_height;
    reg       canvas_empty;
    
    // Signal to classifier that FE is done
    reg fe_done_flag;
    
    // Feature extraction FSM
    always @(posedge clk) begin
        if (!reset_n) begin
            fe_state <= FE_IDLE;
            scan_x <= 8'd0;
            scan_y <= 7'd0;
            pixel_count <= 15'd0;
            bbox_min_x <= 8'd159;
            bbox_max_x <= 8'd0;
            bbox_min_y <= 7'd119;
            bbox_max_y <= 7'd0;
            bbox_width <= 9'd0;
            bbox_height <= 9'd0;
            canvas_empty <= 1'b1;
            fe_done_flag <= 1'b0;
        end else begin
            // Default
            fe_done_flag <= 1'b0;
            
            case (fe_state)
                FE_IDLE: begin
                    if (fe_start_request || (main_state == MAIN_ANALYZE && fe_state == FE_IDLE)) begin
                        fe_state <= FE_INIT;
                    end
                end
                
                FE_INIT: begin
                    // Initialize scan parameters
                    scan_x <= 8'd0;
                    scan_y <= 7'd0;
                    pixel_count <= 15'd0;
                    bbox_min_x <= 8'd159;
                    bbox_max_x <= 8'd0;
                    bbox_min_y <= 7'd119;
                    bbox_max_y <= 7'd0;
                    canvas_empty <= 1'b0;
                    fe_state <= FE_SCAN_ADDR;
                end
                
                FE_SCAN_ADDR: begin
                    // Address is set by arbiter
                    // Move to wait state for BRAM latency
                    fe_state <= FE_SCAN_WAIT;
                end
                
                FE_SCAN_WAIT: begin
                    // Wait one cycle for synchronous read
                    fe_state <= FE_SCAN_PROC;
                end
                
                FE_SCAN_PROC: begin
                    // Process the read data
                    if (mem_read_data == 1'b1) begin
                        pixel_count <= pixel_count + 15'd1;
                        
                        // Update bounding box
                        if (scan_x < bbox_min_x) bbox_min_x <= scan_x;
                        if (scan_x > bbox_max_x) bbox_max_x <= scan_x;
                        if (scan_y < bbox_min_y) bbox_min_y <= scan_y;
                        if (scan_y > bbox_max_y) bbox_max_y <= scan_y;
                    end
                    
                    // Advance scan position
                    if (scan_x == 8'd159) begin
                        scan_x <= 8'd0;
                        if (scan_y == 7'd119) begin
                            // Scan complete
                            fe_state <= FE_DONE;
                        end else begin
                            scan_y <= scan_y + 7'd1;
                            fe_state <= FE_SCAN_ADDR;
                        end
                    end else begin
                        scan_x <= scan_x + 8'd1;
                        fe_state <= FE_SCAN_ADDR;
                    end
                end
                
                FE_DONE: begin
                    // Compute final dimensions
                    if (pixel_count != 15'd0) begin
                        bbox_width  <= (bbox_max_x - bbox_min_x) + 9'd1;
                        bbox_height <= (bbox_max_y - bbox_min_y) + 9'd1;
                        canvas_empty <= 1'b0;
                    end else begin
                        bbox_width  <= 9'd0;
                        bbox_height <= 9'd0;
                        canvas_empty <= 1'b1;
                    end
                    
                    fe_done_flag <= 1'b1;
                    fe_state <= FE_IDLE;
                end
                
                default: fe_state <= FE_IDLE;
            endcase
        end
    end

    // =========================================================
    // 7) Classification Pipeline
    // =========================================================
    reg [2:0] classify_stage;
    
    // Latched feature inputs
    reg [14:0] pixel_count_latched;
    reg [8:0]  bbox_width_latched;
    reg [8:0]  bbox_height_latched;
    reg        canvas_empty_latched;
    
    // Derived metrics (32-bit)
    reg [31:0] bbox_area;
    reg [31:0] fill_ratio_num;      // pixel_count << scale
    reg [31:0] aspect_ratio_num;    // width << scale
    reg [31:0] aspect_ratio_den;    // height
    
    // Intermediate classification signals
    reg [31:0] fill_ratio_scaled;   // (pixel_count << 16) / bbox_area
    reg [31:0] aspect_diff;
    reg is_square_aspect;
    reg is_high_fill;
    reg is_medium_fill;
    reg is_low_fill;
    
    // Classification pipeline - SINGLE DRIVER for detected_shape, confidence, recognition_done
    always @(posedge clk) begin
        if (!reset_n) begin
            classify_stage <= CL_IDLE;
            detected_shape <= SHAPE_NONE;
            confidence <= 8'd0;
            recognition_done <= 1'b0;
            pixel_count_latched <= 15'd0;
            bbox_width_latched <= 9'd0;
            bbox_height_latched <= 9'd0;
            canvas_empty_latched <= 1'b1;
            bbox_area <= 32'd0;
            fill_ratio_num <= 32'd0;
            aspect_ratio_num <= 32'd0;
            aspect_ratio_den <= 32'd0;
            fill_ratio_scaled <= 32'd0;
            aspect_diff <= 32'd0;
            is_square_aspect <= 1'b0;
            is_high_fill <= 1'b0;
            is_medium_fill <= 1'b0;
            is_low_fill <= 1'b0;
        end else begin
            // Default: clear recognition_done pulse
            recognition_done <= 1'b0;
            
            case (classify_stage)
                CL_IDLE: begin
                    if (fe_done_flag) begin
                        classify_stage <= CL_LATCH;
                    end
                end
                
                CL_LATCH: begin
                    // Latch feature extraction outputs
                    pixel_count_latched <= pixel_count;
                    bbox_width_latched <= bbox_width;
                    bbox_height_latched <= bbox_height;
                    canvas_empty_latched <= canvas_empty;
                    
                    // Handle empty canvas immediately
                    if (canvas_empty) begin
                        detected_shape <= SHAPE_NONE;
                        confidence <= 8'd0;
                        recognition_done <= 1'b1;
                        classify_stage <= CL_IDLE;
                    end else begin
                        classify_stage <= CL_CALC_AREA;
                    end
                end
                
                CL_CALC_AREA: begin
                    // Compute bounding box area
                    bbox_area <= bbox_width_latched * bbox_height_latched;
                    classify_stage <= CL_CALC_RATIOS;
                end
                
                CL_CALC_RATIOS: begin
                    // Compute fill ratio (scaled by 256 for fixed-point)
                    // fill_ratio = (pixel_count << 8) / bbox_area
                    fill_ratio_num <= {pixel_count_latched, 8'd0};  // pixel_count << 8
                    
                    // Compute aspect ratio components
                    aspect_ratio_num <= {22'd0, bbox_width_latched};
                    aspect_ratio_den <= {22'd0, bbox_height_latched};
                    
                    // Calculate fill_ratio_scaled
                    if (bbox_area != 32'd0) begin
                        fill_ratio_scaled <= ({pixel_count_latched, 8'd0}) / bbox_area;
                    end else begin
                        fill_ratio_scaled <= 32'd0;
                    end
                    
                    // Calculate aspect difference
                    if (bbox_width_latched > bbox_height_latched) begin
                        aspect_diff <= bbox_width_latched - bbox_height_latched;
                    end else begin
                        aspect_diff <= bbox_height_latched - bbox_width_latched;
                    end
                    
                    classify_stage <= CL_CLASSIFY;
                end
                
                CL_CLASSIFY: begin
                    // Thresholds (scaled by 256):
                    // fill_ratio > 0.75 => 192
                    // fill_ratio 0.3-0.6 => 77-154
                    // aspect_ratio ~1.0 => diff < 10% of dimension
                    
                    // Determine aspect characteristics
                    // Square aspect: difference less than 10% of smaller dimension
                    if (bbox_width_latched < bbox_height_latched) begin
                        is_square_aspect <= (aspect_diff < (bbox_width_latched >> 3)); // < 12.5%
                    end else begin
                        is_square_aspect <= (aspect_diff < (bbox_height_latched >> 3)); // < 12.5%
                    end
                    
                    // Determine fill characteristics
                    is_high_fill <= (fill_ratio_scaled >= 32'd192);    // >= 0.75
                    is_medium_fill <= (fill_ratio_scaled >= 32'd77 && fill_ratio_scaled < 32'd192); // 0.3-0.75
                    is_low_fill <= (fill_ratio_scaled < 32'd77);       // < 0.3
                    
                    // Classification logic
                    if (is_high_fill && is_square_aspect) begin
                        // Square: high fill + square aspect
                        detected_shape <= SHAPE_SQUARE;
                        // Confidence based on how close to ideal
                        if (fill_ratio_scaled >= 32'd230) // > 0.9
                            confidence <= 8'd255;
                        else if (fill_ratio_scaled >= 32'd204) // > 0.8
                            confidence <= 8'd220;
                        else
                            confidence <= 8'd180;
                    end
                    else if (is_high_fill && !is_square_aspect) begin
                        // Rectangle: high fill + elongated aspect
                        detected_shape <= SHAPE_RECTANGLE;
                        if (fill_ratio_scaled >= 32'd230) // > 0.9
                            confidence <= 8'd255;
                        else if (fill_ratio_scaled >= 32'd204) // > 0.8
                            confidence <= 8'd220;
                        else
                            confidence <= 8'd180;
                    end
                    else if (is_square_aspect && fill_ratio_scaled >= 32'd170 && fill_ratio_scaled < 32'd220) begin
                        // Circle: square aspect + fill ratio around 0.67-0.86 (π/4 ≈ 0.785)
                        detected_shape <= SHAPE_CIRCLE;
                        // Higher confidence if closer to π/4 (≈ 201 in our scale)
                        if (fill_ratio_scaled >= 32'd190 && fill_ratio_scaled <= 32'd210)
                            confidence <= 8'd240;
                        else if (fill_ratio_scaled >= 32'd180 && fill_ratio_scaled <= 32'd220)
                            confidence <= 8'd200;
                        else
                            confidence <= 8'd160;
                    end
                    else if (is_medium_fill || is_low_fill) begin
                        // Triangle: lower fill ratio
                        detected_shape <= SHAPE_TRIANGLE;
                        if (fill_ratio_scaled >= 32'd102 && fill_ratio_scaled <= 32'd140) // 0.4-0.55
                            confidence <= 8'd200;
                        else if (fill_ratio_scaled >= 32'd77 && fill_ratio_scaled <= 32'd154) // 0.3-0.6
                            confidence <= 8'd160;
                        else
                            confidence <= 8'd120;
                    end
                    else begin
                        // Unrecognized
                        detected_shape <= SHAPE_NONE;
                        confidence <= 8'd0;
                    end
                    
                    recognition_done <= 1'b1;
                    classify_stage <= CL_IDLE;
                end
                
                default: classify_stage <= CL_IDLE;
            endcase
        end
    end

    // =========================================================
    // 8) Busy Signal - Single Driver
    // =========================================================
    always @(posedge clk) begin
        if (!reset_n) begin
            busy <= 1'b0;
        end else begin
            busy <= clearing_active ||
                    (main_state == MAIN_ANALYZE) ||
                    (main_state == MAIN_DONE);
        end
    end

endmodule

`default_nettype wire

