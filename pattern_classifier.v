/*****************************************************************************
 *                                                                           *
 * Module:       pattern_classifier                                          *
 * Description:  Pattern recognition system for digit and shape             *
 *               classification with VGA memory interface                    *
 *                                                                           *
 *****************************************************************************/

module pattern_classifier (
    // Clock and reset
    input wire clk,
    input wire resetn,
    
    // Control inputs
    input wire classify_digit,    // KEY[1] - trigger digit classification
    input wire classify_shape,    // KEY[2] - trigger shape classification
    
    // VGA memory interface (read-only access)
    output reg [16:0] vga_read_addr,  // 320*240 = 76800 needs 17 bits
    input wire [8:0] vga_read_data,   // 9-bit RGB color
    
    // Classification outputs
    output reg [3:0] result,          // Classification result
    output reg classification_done,    // Done flag
    output reg is_digit_mode,         // 1=digit mode, 0=shape mode
    
    // 7-segment display outputs
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    output wire [6:0] HEX6,
    output wire [6:0] HEX7
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/

parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 240;
parameter COLOR_BLACK = 9'b000_000_000;  // Black pixels are drawn content

// State machine states
localparam IDLE = 4'd0;
localparam SCAN_IMAGE = 4'd1;
localparam FIND_BBOX = 4'd2;
localparam NORMALIZE = 4'd3;
localparam CLASSIFY_DIGIT = 4'd4;
localparam CLASSIFY_SHAPE = 4'd5;
localparam DISPLAY = 4'd6;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

reg [3:0] state;

// Image scanner signals
reg scanner_start;
wire scanner_done;
wire [8:0] bbox_min_x, bbox_max_x;
wire [7:0] bbox_min_y, bbox_max_y;
wire [15:0] pixel_count;
wire scanner_valid;

// Image normalizer signals
reg normalizer_start;
wire normalizer_done;
wire [255:0] normalized_image;

// Template matcher signals
wire [3:0] matched_digit;
wire [7:0] match_score;

// Shape classifier signals
wire [1:0] shape_type;  // 0=circle, 1=square, 2=triangle, 3=unknown

// Display control
reg show_result;

/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/

// Main state machine
always @(posedge clk) begin
    if (!resetn) begin
        state <= IDLE;
        scanner_start <= 1'b0;
        normalizer_start <= 1'b0;
        classification_done <= 1'b0;
        is_digit_mode <= 1'b0;
        result <= 4'd0;
        show_result <= 1'b0;
        vga_read_addr <= 17'd0;
    end else begin
        case (state)
            IDLE: begin
                classification_done <= 1'b0;
                scanner_start <= 1'b0;
                normalizer_start <= 1'b0;
                
                if (classify_digit) begin
                    is_digit_mode <= 1'b1;
                    scanner_start <= 1'b1;
                    state <= SCAN_IMAGE;
                end else if (classify_shape) begin
                    is_digit_mode <= 1'b0;
                    scanner_start <= 1'b1;
                    state <= SCAN_IMAGE;
                end
            end
            
            SCAN_IMAGE: begin
                scanner_start <= 1'b0;
                if (scanner_done) begin
                    if (scanner_valid) begin
                        state <= NORMALIZE;
                        normalizer_start <= 1'b1;
                    end else begin
                        // No content found
                        result <= 4'hF;  // Error/unknown
                        state <= DISPLAY;
                    end
                end
            end
            
            NORMALIZE: begin
                normalizer_start <= 1'b0;
                if (normalizer_done) begin
                    if (is_digit_mode) begin
                        state <= CLASSIFY_DIGIT;
                    end else begin
                        state <= CLASSIFY_SHAPE;
                    end
                end
            end
            
            CLASSIFY_DIGIT: begin
                // Template matching happens combinationally
                result <= matched_digit;
                state <= DISPLAY;
            end
            
            CLASSIFY_SHAPE: begin
                // Shape classification happens combinationally
                result <= {2'b00, shape_type};
                state <= DISPLAY;
            end
            
            DISPLAY: begin
                classification_done <= 1'b1;
                show_result <= 1'b1;
                if (!classify_digit && !classify_shape) begin
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

/*****************************************************************************
 *                            Module Instantiations                          *
 *****************************************************************************/

// Image scanner module
image_scanner scanner (
    .clk(clk),
    .resetn(resetn),
    .start(scanner_start),
    .vga_read_addr(vga_read_addr),
    .vga_read_data(vga_read_data),
    .done(scanner_done),
    .bbox_min_x(bbox_min_x),
    .bbox_max_x(bbox_max_x),
    .bbox_min_y(bbox_min_y),
    .bbox_max_y(bbox_max_y),
    .pixel_count(pixel_count),
    .valid(scanner_valid)
);

// Image normalizer module
image_normalizer normalizer (
    .clk(clk),
    .resetn(resetn),
    .start(normalizer_start),
    .bbox_min_x(bbox_min_x),
    .bbox_max_x(bbox_max_x),
    .bbox_min_y(bbox_min_y),
    .bbox_max_y(bbox_max_y),
    .vga_read_addr(vga_read_addr),
    .vga_read_data(vga_read_data),
    .done(normalizer_done),
    .normalized_image(normalized_image)
);

// Template matcher for digit classification
template_matcher matcher (
    .normalized_image(normalized_image),
    .matched_digit(matched_digit),
    .match_score(match_score)
);

// Shape classifier
shape_classifier shape_class (
    .normalized_image(normalized_image),
    .bbox_width(bbox_max_x - bbox_min_x + 1),
    .bbox_height(bbox_max_y - bbox_min_y + 1),
    .pixel_count(pixel_count),
    .shape_type(shape_type)
);

// Result display controller
result_display_controller display_ctrl (
    .result(result),
    .is_digit_mode(is_digit_mode),
    .show_result(show_result),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .HEX6(HEX6),
    .HEX7(HEX7)
);

endmodule


/*****************************************************************************
 * Image Scanner Module                                                      *
 * Scans VGA memory to find bounding box of drawn content                   *
 *****************************************************************************/

module image_scanner (
    input wire clk,
    input wire resetn,
    input wire start,
    
    // VGA memory interface
    output reg [16:0] vga_read_addr,
    input wire [8:0] vga_read_data,
    
    // Outputs
    output reg done,
    output reg [8:0] bbox_min_x,
    output reg [8:0] bbox_max_x,
    output reg [7:0] bbox_min_y,
    output reg [7:0] bbox_max_y,
    output reg [15:0] pixel_count,
    output reg valid  // 1 if any black pixels found
);

parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 240;
parameter COLOR_BLACK = 9'b000_000_000;
parameter BLACK_THRESHOLD = 9'b001_001_001;  // Near-black threshold

reg [1:0] state;
localparam S_IDLE = 2'd0;
localparam S_SCAN = 2'd1;
localparam S_DONE = 2'd2;

reg [8:0] scan_x;
reg [7:0] scan_y;
reg [1:0] read_delay;  // Pipeline delay for memory read

always @(posedge clk) begin
    if (!resetn) begin
        state <= S_IDLE;
        done <= 1'b0;
        bbox_min_x <= 9'd319;
        bbox_max_x <= 9'd0;
        bbox_min_y <= 8'd239;
        bbox_max_y <= 8'd0;
        pixel_count <= 16'd0;
        valid <= 1'b0;
        scan_x <= 9'd0;
        scan_y <= 8'd0;
        vga_read_addr <= 17'd0;
        read_delay <= 2'd0;
    end else begin
        case (state)
            S_IDLE: begin
                done <= 1'b0;
                if (start) begin
                    bbox_min_x <= 9'd319;
                    bbox_max_x <= 9'd0;
                    bbox_min_y <= 8'd239;
                    bbox_max_y <= 8'd0;
                    pixel_count <= 16'd0;
                    valid <= 1'b0;
                    scan_x <= 9'd0;
                    scan_y <= 8'd0;
                    vga_read_addr <= 17'd0;
                    read_delay <= 2'd0;
                    state <= S_SCAN;
                end
            end
            
            S_SCAN: begin
                // Account for 2-cycle memory read latency
                if (read_delay < 2'd2) begin
                    read_delay <= read_delay + 1;
                end else begin
                    // Check if current pixel is black (drawn)
                    if (vga_read_data < BLACK_THRESHOLD) begin
                        valid <= 1'b1;
                        pixel_count <= pixel_count + 1;
                        
                        // Update bounding box
                        if (scan_x < bbox_min_x) bbox_min_x <= scan_x;
                        if (scan_x > bbox_max_x) bbox_max_x <= scan_x;
                        if (scan_y < bbox_min_y) bbox_min_y <= scan_y;
                        if (scan_y > bbox_max_y) bbox_max_y <= scan_y;
                    end
                end
                
                // Move to next pixel
                if (scan_x == SCREEN_WIDTH - 1) begin
                    scan_x <= 9'd0;
                    if (scan_y == SCREEN_HEIGHT - 1) begin
                        state <= S_DONE;
                    end else begin
                        scan_y <= scan_y + 1;
                    end
                end else begin
                    scan_x <= scan_x + 1;
                end
                
                vga_read_addr <= vga_read_addr + 1;
            end
            
            S_DONE: begin
                done <= 1'b1;
                if (!start) begin
                    state <= S_IDLE;
                end
            end
            
            default: state <= S_IDLE;
        endcase
    end
end

endmodule


/*****************************************************************************
 * Image Normalizer Module                                                   *
 * Normalizes bounding box region to 16x16 binary image                     *
 *****************************************************************************/

module image_normalizer (
    input wire clk,
    input wire resetn,
    input wire start,
    
    // Bounding box inputs
    input wire [8:0] bbox_min_x,
    input wire [8:0] bbox_max_x,
    input wire [7:0] bbox_min_y,
    input wire [7:0] bbox_max_y,
    
    // VGA memory interface
    output reg [16:0] vga_read_addr,
    input wire [8:0] vga_read_data,
    
    // Outputs
    output reg done,
    output reg [255:0] normalized_image  // 16x16 flattened
);

parameter BLACK_THRESHOLD = 9'b001_001_001;

reg [2:0] state;
localparam N_IDLE = 3'd0;
localparam N_COMPUTE = 3'd1;
localparam N_SAMPLE = 3'd2;
localparam N_WAIT = 3'd3;
localparam N_DONE = 3'd4;

reg [3:0] grid_x, grid_y;  // 0-15
reg [8:0] sample_x;
reg [7:0] sample_y;
reg [9:0] bbox_width, bbox_height;
reg [1:0] read_delay;

always @(posedge clk) begin
    if (!resetn) begin
        state <= N_IDLE;
        done <= 1'b0;
        normalized_image <= 256'd0;
        grid_x <= 4'd0;
        grid_y <= 4'd0;
        vga_read_addr <= 17'd0;
        read_delay <= 2'd0;
    end else begin
        case (state)
            N_IDLE: begin
                done <= 1'b0;
                if (start) begin
                    grid_x <= 4'd0;
                    grid_y <= 4'd0;
                    normalized_image <= 256'd0;
                    state <= N_COMPUTE;
                end
            end
            
            N_COMPUTE: begin
                // Compute dimensions
                bbox_width <= bbox_max_x - bbox_min_x + 1;
                bbox_height <= bbox_max_y - bbox_min_y + 1;
                state <= N_SAMPLE;
            end
            
            N_SAMPLE: begin
                // Calculate sample position (center of grid cell)
                sample_x <= bbox_min_x + ((bbox_width * grid_x) >> 4) + (bbox_width >> 5);
                sample_y <= bbox_min_y + ((bbox_height * grid_y) >> 4) + (bbox_height >> 5);
                
                // Compute memory address: y * 320 + x
                vga_read_addr <= (bbox_min_y + ((bbox_height * grid_y) >> 4)) * 320 + 
                                 (bbox_min_x + ((bbox_width * grid_x) >> 4));
                read_delay <= 2'd0;
                state <= N_WAIT;
            end
            
            N_WAIT: begin
                // Wait for memory read
                if (read_delay < 2'd2) begin
                    read_delay <= read_delay + 1;
                end else begin
                    // Store normalized pixel
                    if (vga_read_data < BLACK_THRESHOLD) begin
                        normalized_image[grid_y * 16 + grid_x] <= 1'b1;  // Black
                    end else begin
                        normalized_image[grid_y * 16 + grid_x] <= 1'b0;  // White
                    end
                    
                    // Move to next grid cell
                    if (grid_x == 4'd15) begin
                        grid_x <= 4'd0;
                        if (grid_y == 4'd15) begin
                            state <= N_DONE;
                        end else begin
                            grid_y <= grid_y + 1;
                            state <= N_SAMPLE;
                        end
                    end else begin
                        grid_x <= grid_x + 1;
                        state <= N_SAMPLE;
                    end
                end
            end
            
            N_DONE: begin
                done <= 1'b1;
                if (!start) begin
                    state <= N_IDLE;
                end
            end
            
            default: state <= N_IDLE;
        endcase
    end
end

endmodule


/*****************************************************************************
 * Digit Template ROM Module                                                 *
 * Stores 16x16 binary templates for digits 0-9                             *
 *****************************************************************************/

module digit_template_rom (
    input wire [3:0] digit,
    output reg [255:0] template_data
);

// 16x16 templates for digits 0-9 (1 = black, 0 = white)
// Each row is 16 bits, stored from top to bottom
always @(*) begin
    case (digit)
        4'd0: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0001111111111000,
            16'b0011110000111100,
            16'b0111100000011110,
            16'b0111000000001110,
            16'b1110000000000111,
            16'b1110000000000111,
            16'b1110000000000111,
            16'b1110000000000111,
            16'b0111000000001110,
            16'b0111100000011110,
            16'b0011110000111100,
            16'b0001111111111000,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        4'd1: template_data = {
            16'b0000000000000000,
            16'b0000001110000000,
            16'b0000011110000000,
            16'b0000111110000000,
            16'b0001111110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0001111111100000,
            16'b0001111111100000,
            16'b0000000000000000
        };
        
        4'd2: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0011111111111100,
            16'b0111100000011110,
            16'b1110000000001110,
            16'b0000000000001110,
            16'b0000000000011110,
            16'b0000000000111100,
            16'b0000000001111000,
            16'b0000000011110000,
            16'b0000000111100000,
            16'b0000001111000000,
            16'b0000011110000000,
            16'b0111111111111110,
            16'b0111111111111110,
            16'b0000000000000000
        };
        
        4'd3: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0011111111111100,
            16'b0111100000011110,
            16'b0000000000001110,
            16'b0000000000001110,
            16'b0000000000011110,
            16'b0000001111111000,
            16'b0000001111111000,
            16'b0000000000011110,
            16'b0000000000001110,
            16'b0000000000001110,
            16'b0111100000011110,
            16'b0011111111111100,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        4'd4: template_data = {
            16'b0000000000000000,
            16'b0000000000111000,
            16'b0000000001111000,
            16'b0000000011111000,
            16'b0000000111011000,
            16'b0000001110011000,
            16'b0000011100011000,
            16'b0000111000011000,
            16'b0001110000011000,
            16'b0111111111111110,
            16'b0111111111111110,
            16'b0000000000011000,
            16'b0000000000011000,
            16'b0000000000011000,
            16'b0000000000011000,
            16'b0000000000000000
        };
        
        4'd5: template_data = {
            16'b0000000000000000,
            16'b0111111111111110,
            16'b0111111111111110,
            16'b0111000000000000,
            16'b0111000000000000,
            16'b0111000000000000,
            16'b0111111111110000,
            16'b0111111111111100,
            16'b0000000000011110,
            16'b0000000000001110,
            16'b0000000000001110,
            16'b0000000000001110,
            16'b0111100000011110,
            16'b0011111111111100,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        4'd6: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0011111111111100,
            16'b0111100000011110,
            16'b0111000000000000,
            16'b1110000000000000,
            16'b1110111111110000,
            16'b1111111111111100,
            16'b1111100000011110,
            16'b1110000000001110,
            16'b1110000000001110,
            16'b0111000000001110,
            16'b0111100000011110,
            16'b0011111111111100,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        4'd7: template_data = {
            16'b0000000000000000,
            16'b0111111111111110,
            16'b0111111111111110,
            16'b0000000000001110,
            16'b0000000000011100,
            16'b0000000000111000,
            16'b0000000000111000,
            16'b0000000001110000,
            16'b0000000001110000,
            16'b0000000011100000,
            16'b0000000011100000,
            16'b0000000111000000,
            16'b0000000111000000,
            16'b0000001110000000,
            16'b0000001110000000,
            16'b0000000000000000
        };
        
        4'd8: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0011111111111100,
            16'b0111100000011110,
            16'b0111000000001110,
            16'b0111000000001110,
            16'b0111100000011110,
            16'b0001111111111000,
            16'b0001111111111000,
            16'b0111100000011110,
            16'b0111000000001110,
            16'b0111000000001110,
            16'b0111100000011110,
            16'b0011111111111100,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        4'd9: template_data = {
            16'b0000000000000000,
            16'b0000111111110000,
            16'b0011111111111100,
            16'b0111100000011110,
            16'b0111000000001110,
            16'b0111000000001110,
            16'b0111000000001111,
            16'b0111100000011111,
            16'b0011111111111111,
            16'b0000111111110111,
            16'b0000000000001110,
            16'b0000000000001110,
            16'b0111100000011110,
            16'b0011111111111100,
            16'b0000111111110000,
            16'b0000000000000000
        };
        
        default: template_data = 256'd0;
    endcase
end

endmodule


/*****************************************************************************
 * Template Matcher Module                                                   *
 * Compares normalized image against all digit templates                    *
 *****************************************************************************/

module template_matcher (
    input wire [255:0] normalized_image,
    output reg [3:0] matched_digit,
    output reg [7:0] match_score
);

wire [7:0] scores [0:9];
wire [255:0] templates [0:9];
integer i;

// Instantiate template ROM for each digit
genvar d;
generate
    for (d = 0; d < 10; d = d + 1) begin : template_gen
        digit_template_rom rom_inst (
            .digit(d[3:0]),
            .template_data(templates[d])
        );
        
        // Count matching pixels
        match_counter counter (
            .image(normalized_image),
            .template(templates[d]),
            .score(scores[d])
        );
    end
endgenerate

// Find best match
always @(*) begin
    matched_digit = 4'd0;
    match_score = scores[0];
    
    for (i = 1; i < 10; i = i + 1) begin
        if (scores[i] > match_score) begin
            match_score = scores[i];
            matched_digit = i[3:0];
        end
    end
end

endmodule


/*****************************************************************************
 * Match Counter Module                                                      *
 * Counts matching pixels between image and template                        *
 *****************************************************************************/

module match_counter (
    input wire [255:0] image,
    input wire [255:0] template,
    output reg [7:0] score
);

wire [255:0] matches;
assign matches = ~(image ^ template);  // XNOR - 1 where they match

integer i;
always @(*) begin
    score = 8'd0;
    for (i = 0; i < 256; i = i + 1) begin
        score = score + matches[i];
    end
end

endmodule


/*****************************************************************************
 * Shape Feature Extractor Module                                            *
 * Extracts geometric features for shape classification                     *
 *****************************************************************************/

module shape_feature_extractor (
    input wire [255:0] normalized_image,
    input wire [9:0] bbox_width,
    input wire [9:0] bbox_height,
    input wire [15:0] pixel_count,
    
    output reg [9:0] aspect_ratio_x10,  // aspect ratio * 10
    output reg [7:0] filled_ratio,      // (pixel_count / bbox_area) * 100
    output reg [3:0] corner_count
);

wire [19:0] bbox_area;
wire [19:0] filled_calc;

assign bbox_area = bbox_width * bbox_height;
assign filled_calc = (pixel_count * 100) / bbox_area;

always @(*) begin
    // Compute aspect ratio * 10
    if (bbox_height > 0) begin
        aspect_ratio_x10 = (bbox_width * 10) / bbox_height;
    end else begin
        aspect_ratio_x10 = 10'd10;  // 1.0 default
    end
    
    // Compute filled ratio
    if (bbox_area > 0) begin
        filled_ratio = filled_calc[7:0];
    end else begin
        filled_ratio = 8'd0;
    end
    
    // Simple corner detection (count sharp turns in normalized image)
    corner_count = detect_corners(normalized_image);
end

function [3:0] detect_corners;
    input [255:0] image;
    reg [3:0] count;
    integer x, y, idx;
    reg curr, up, down, left, right;
    begin
        count = 4'd0;
        
        // Sample key points in the 16x16 grid for corners
        for (y = 1; y < 15; y = y + 1) begin
            for (x = 1; x < 15; x = x + 1) begin
                idx = y * 16 + x;
                curr = image[idx];
                
                if (curr) begin
                    up = image[(y-1)*16 + x];
                    down = image[(y+1)*16 + x];
                    left = image[y*16 + (x-1)];
                    right = image[y*16 + (x+1)];
                    
                    // Corner if pixel has exactly 2 neighbors at right angle
                    if ((up && left && !down && !right) ||
                        (up && right && !down && !left) ||
                        (down && left && !up && !right) ||
                        (down && right && !up && !left)) begin
                        if (count < 4'd15) count = count + 1;
                    end
                end
            end
        end
        
        detect_corners = count;
    end
endfunction

endmodule


/*****************************************************************************
 * Shape Classifier Module                                                   *
 * Classifies shapes based on geometric features                            *
 *****************************************************************************/

module shape_classifier (
    input wire [255:0] normalized_image,
    input wire [9:0] bbox_width,
    input wire [9:0] bbox_height,
    input wire [15:0] pixel_count,
    
    output reg [1:0] shape_type  // 0=circle, 1=square, 2=triangle, 3=unknown
);

wire [9:0] aspect_ratio_x10;
wire [7:0] filled_ratio;
wire [3:0] corner_count;

shape_feature_extractor feature_extractor (
    .normalized_image(normalized_image),
    .bbox_width(bbox_width),
    .bbox_height(bbox_height),
    .pixel_count(pixel_count),
    .aspect_ratio_x10(aspect_ratio_x10),
    .filled_ratio(filled_ratio),
    .corner_count(corner_count)
);

always @(*) begin
    // Classification logic based on features
    // Circle: high filled ratio, aspect ratio close to 1.0, few corners
    if ((filled_ratio > 60) && 
        (aspect_ratio_x10 >= 8 && aspect_ratio_x10 <= 12) &&
        (corner_count <= 2)) begin
        shape_type = 2'd0;  // Circle
    end
    // Square: medium-high filled ratio, aspect ratio close to 1.0, 4+ corners
    else if ((filled_ratio > 50) &&
             (aspect_ratio_x10 >= 8 && aspect_ratio_x10 <= 12) &&
             (corner_count >= 3)) begin
        shape_type = 2'd1;  // Square
    end
    // Triangle: lower filled ratio, 3-4 corners
    else if ((filled_ratio > 30) && (filled_ratio < 65) &&
             (corner_count >= 2 && corner_count <= 5)) begin
        shape_type = 2'd2;  // Triangle
    end
    else begin
        shape_type = 2'd3;  // Unknown
    end
end

endmodule


/*****************************************************************************
 * Result Display Controller Module                                          *
 * Controls 7-segment displays for classification results                   *
 *****************************************************************************/

module result_display_controller (
    input wire [3:0] result,
    input wire is_digit_mode,
    input wire show_result,
    
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    output wire [6:0] HEX6,
    output wire [6:0] HEX7
);

// Blank display
parameter BLANK = 7'b1111111;

// Custom 7-segment patterns
parameter SEG_d = 7'b0100001;  // 'd' for digit mode
parameter SEG_C = 7'b1000110;  // 'C' for circle
parameter SEG_S = 7'b0010010;  // 'S' for square
parameter SEG_t = 7'b0000111;  // 't' for triangle
parameter SEG_QUESTION = 7'b0110011;  // '?' for unknown

reg [6:0] hex_reg [0:7];

// Hexadecimal to 7-segment for digits
function [6:0] hex_to_7seg;
    input [3:0] hex;
    begin
        case (hex)
            4'h0: hex_to_7seg = 7'b1000000;
            4'h1: hex_to_7seg = 7'b1111001;
            4'h2: hex_to_7seg = 7'b0100100;
            4'h3: hex_to_7seg = 7'b0110000;
            4'h4: hex_to_7seg = 7'b0011001;
            4'h5: hex_to_7seg = 7'b0010010;
            4'h6: hex_to_7seg = 7'b0000010;
            4'h7: hex_to_7seg = 7'b1111000;
            4'h8: hex_to_7seg = 7'b0000000;
            4'h9: hex_to_7seg = 7'b0010000;
            default: hex_to_7seg = BLANK;
        endcase
    end
endfunction

always @(*) begin
    if (show_result) begin
        // Clear all displays
        hex_reg[0] = BLANK;
        hex_reg[1] = BLANK;
        hex_reg[2] = BLANK;
        hex_reg[3] = BLANK;
        hex_reg[4] = BLANK;
        hex_reg[5] = BLANK;
        hex_reg[6] = BLANK;
        hex_reg[7] = BLANK;
        
        if (is_digit_mode) begin
            // Display: "d X" where X is the digit
            hex_reg[1] = SEG_d;
            hex_reg[0] = hex_to_7seg(result);
        end else begin
            // Display shape result on HEX1
            case (result[1:0])
                2'd0: hex_reg[1] = SEG_C;       // Circle
                2'd1: hex_reg[1] = SEG_S;       // Square
                2'd2: hex_reg[1] = SEG_t;       // Triangle
                2'd3: hex_reg[1] = SEG_QUESTION; // Unknown
            endcase
        end
    end else begin
        // All blank when not showing result
        hex_reg[0] = BLANK;
        hex_reg[1] = BLANK;
        hex_reg[2] = BLANK;
        hex_reg[3] = BLANK;
        hex_reg[4] = BLANK;
        hex_reg[5] = BLANK;
        hex_reg[6] = BLANK;
        hex_reg[7] = BLANK;
    end
end

assign HEX0 = hex_reg[0];
assign HEX1 = hex_reg[1];
assign HEX2 = hex_reg[2];
assign HEX3 = hex_reg[3];
assign HEX4 = hex_reg[4];
assign HEX5 = hex_reg[5];
assign HEX6 = hex_reg[6];
assign HEX7 = hex_reg[7];

endmodule

