module ShapeClassifier(
    input clk,
    input reset,        // Connect to global reset or clear signal
    input enable,       // High when a "drawing" pixel is written (not erasing)
    input [8:0] x,
    input [7:0] y,
    output reg [6:0] hex_output // Decoded 7-segment output
);

    // =========================================================================
    // 1. BOUNDING BOX TRACKING
    // =========================================================================
    reg [8:0] min_x, max_x;
    reg [7:0] min_y, max_y;

    // Registers to track the 'spread' of the shape at its extreme edges
    reg [7:0] y_at_min_x_min, y_at_min_x_max; // Left Edge Span
    reg [7:0] y_at_max_x_min, y_at_max_x_max; // Right Edge Span
    reg [8:0] x_at_min_y_min, x_at_min_y_max; // Top Edge Span
    reg [8:0] x_at_max_y_min, x_at_max_y_max; // Bottom Edge Span
    
    // --- NEW: START POINT TRACKING ---
    reg [8:0] start_x;
    reg [7:0] start_y;
    reg has_started;
    
    reg active_drawing;

    always @(posedge clk) begin
        if (reset) begin
            // Reset Bounds
            min_x <= 9'd511; max_x <= 9'd0;
            min_y <= 8'd255; max_y <= 8'd0;
            
            // Reset Spans
            y_at_min_x_min <= 8'd255; y_at_min_x_max <= 8'd0;
            y_at_max_x_min <= 8'd255; y_at_max_x_max <= 8'd0;
            x_at_min_y_min <= 9'd511; x_at_min_y_max <= 9'd0;
            x_at_max_y_min <= 9'd511; x_at_max_y_max <= 9'd0;
            
            active_drawing <= 0;
            has_started <= 0;
            start_x <= 0;
            start_y <= 0;
        end
        else if (enable) begin
            active_drawing <= 1;

            // Capture the very first pixel drawn as the "Start Point"
            if (!has_started) begin
                start_x <= x;
                start_y <= y;
                has_started <= 1;
            end

            // --- Update Global X Bounds ---
            if (x < min_x) begin
                min_x <= x;
                y_at_min_x_min <= y;
                y_at_min_x_max <= y;
            end
            else if (x == min_x) begin
                if (y < y_at_min_x_min) y_at_min_x_min <= y;
                if (y > y_at_min_x_max) y_at_min_x_max <= y;
            end

            if (x > max_x) begin
                max_x <= x;
                y_at_max_x_min <= y;
                y_at_max_x_max <= y;
            end
            else if (x == max_x) begin
                if (y < y_at_max_x_min) y_at_max_x_min <= y;
                if (y > y_at_max_x_max) y_at_max_x_max <= y;
            end

            // --- Update Global Y Bounds ---
            if (y < min_y) begin
                min_y <= y;
                x_at_min_y_min <= x;
                x_at_min_y_max <= x;
            end
            else if (y == min_y) begin
                if (x < x_at_min_y_min) x_at_min_y_min <= x;
                if (x > x_at_min_y_max) x_at_min_y_max <= x;
            end

            if (y > max_y) begin
                max_y <= y;
                x_at_max_y_min <= x;
                x_at_max_y_max <= x;
            end
            else if (y == max_y) begin
                if (x < x_at_max_y_min) x_at_max_y_min <= x;
                if (x > x_at_max_y_max) x_at_max_y_max <= x;
            end
        end
    end

    // =========================================================================
    // 2. SHAPE ANALYSIS (Combinational)
    // =========================================================================
    
    // Dimensions
    wire [8:0] width = (max_x > min_x) ? (max_x - min_x) : 0;
    wire [7:0] height = (max_y > min_y) ? (max_y - min_y) : 0;
    
    // Closure Detection:
    // Calculate distance between current 'x/y' (passed in input) and 'start_x/start_y'.
    // Since x/y inputs cycle through the brush pixels, this check is constantly running on the current cursor position.
    wire [8:0] dist_x = (x > start_x) ? (x - start_x) : (start_x - x);
    wire [7:0] dist_y = (y > start_y) ? (y - start_y) : (start_y - y);

    // Is Closed? (Allow a gap of ~15 pixels to account for hand jitter)
    wire is_closed = (dist_x < 15) && (dist_y < 15);

    // Spans
    wire [7:0] span_left = (y_at_min_x_max > y_at_min_x_min) ? (y_at_min_x_max - y_at_min_x_min) : 0;
    wire [7:0] span_right = (y_at_max_x_max > y_at_max_x_min) ? (y_at_max_x_max - y_at_max_x_min) : 0;
    wire [8:0] span_top = (x_at_min_y_max > x_at_min_y_min) ? (x_at_min_y_max - x_at_min_y_min) : 0;
    wire [8:0] span_bottom = (x_at_max_y_max > x_at_max_y_min) ? (x_at_max_y_max - x_at_max_y_min) : 0;

    // Flat Sides Detection (> 50%)
    wire left_is_flat   = span_left   > (height >> 1);
    wire right_is_flat  = span_right  > (height >> 1);
    wire top_is_flat    = span_top    > (width >> 1);
    wire bottom_is_flat = span_bottom > (width >> 1);

    wire [2:0] flat_sides_count = left_is_flat + right_is_flat + top_is_flat + bottom_is_flat;

    // =========================================================================
    // 3. HEX OUTPUT DRIVER
    // =========================================================================
    
    always @(*) begin
        // Condition to show display:
        // 1. Must be actively drawing
        // 2. Shape must be reasonably large (>5 pixels) to avoid noise
        // 3. Shape must be CLOSED (end point near start point)
        if (!active_drawing || (width < 5 && height < 5) || !is_closed) begin
             // Blank display (7'b1111111 is OFF for active-low HEX)
             hex_output = 7'b1111111;
        end
        else if (flat_sides_count >= 2) begin
            // RECTANGLE / SQUARE -> "r"
            hex_output = 7'b0101111; 
        end
        else if (flat_sides_count == 1) begin
            // TRIANGLE -> "⊢"
            hex_output = 7'b0001111;
        end
        else begin
            // CIRCLE -> "c"
            hex_output = 7'b0100111; 
        end
    end

endmodule
