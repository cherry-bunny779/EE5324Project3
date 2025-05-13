`timescale 1ps/1ps
module conv_pool (
    input  logic        clk,
    input  logic        rst,
    input  logic [127:0] image_4x4,                // 8*(4x4)128-bit input image; greyscale 0~255
    input  logic [71:0]  conv_kernel_0,            // 8*(3x3) = 72 bits; 8-bit fixed point
    input  logic [71:0]  conv_kernel_1,		   // 1 sign, 4 int, 3 fraction
    input  logic [71:0]  conv_kernel_2,
    input  logic [1:0]   shift,                    // 2-bit shift
    input  logic         input_re,                 // data read enable
    input  logic [15:0]  input_addr,               // 16-bit input address

    output logic         output_we_0,              // write enable for output 0
    output logic [15:0]  output_addr_0,            // 16-bit output address 0
    output logic         output_we_1,
    output logic [15:0]  output_addr_1,

    output logic         output_we_2,
    output logic [15:0]  output_addr_2,

    output logic [7:0]   y_0,                      // 8-bit result outputs
    output logic [7:0]   y_1,
    output logic [7:0]   y_2
);


// each pixel is greyscale with values 0 -> 255
// each kernel is is 8-bit 2's complement number -128 -> 127

    logic [127:0] image_4x4_ffd;                // 128-bit input image
    logic [71:0]  conv_kernel_0_ffd;            // 8*9 = 72 bits
    logic [71:0]  conv_kernel_1_ffd;
    logic [71:0]  conv_kernel_2_ffd;
    logic [1:0]   shift_ffd;                    // 2-bit shift
    logic         input_re_ffd;                 // data read enable
    logic [15:0]  input_addr_ffd;                // 16-bit input address

// Input DFF
always_ff @(posedge clk) begin
    if (!rst) begin
        image_4x4_ffd     <= '0;
        conv_kernel_0_ffd <= '0;
        conv_kernel_1_ffd <= '0;
        conv_kernel_2_ffd <= '0;
        shift_ffd         <= '0;
        input_re_ffd      <= 1'b0;
        input_addr_ffd    <= '0;
    end else if (input_re) begin
        image_4x4_ffd     <= image_4x4;
        conv_kernel_0_ffd <= conv_kernel_0;
        conv_kernel_1_ffd <= conv_kernel_1;
        conv_kernel_2_ffd <= conv_kernel_2;
        shift_ffd         <= shift;
        input_re_ffd      <= input_re;
        input_addr_ffd    <= input_addr;
    end else begin
        image_4x4_ffd     <= image_4x4_ffd;
        conv_kernel_0_ffd <= conv_kernel_0_ffd;
        conv_kernel_1_ffd <= conv_kernel_1_ffd;
        conv_kernel_2_ffd <= conv_kernel_2_ffd;
        shift_ffd         <= shift_ffd;
        input_re_ffd      <= input_re_ffd;
        input_addr_ffd    <= input_addr_ffd;
    end
	//$display("image4x4dffd: %h\n",image_4x4_ffd);
end

// assume: padding delt with in data
logic signed [21:0] c00_sum;
logic signed [21:0] c01_sum;
logic signed [21:0] c02_sum;
logic signed [21:0] c03_sum;
logic signed [21:0] c10_sum;
logic signed [21:0] c11_sum;
logic signed [21:0] c12_sum;
logic signed [21:0] c13_sum;
logic signed [21:0] c20_sum;
logic signed [21:0] c21_sum;
logic signed [21:0] c22_sum;
logic signed [21:0] c23_sum;

/*logic signed [17:0] inter_pix00,inter_pix01,inter_pix02,inter_pix03,
                    inter_pix10,inter_pix11,inter_pix12,inter_pix13,
                    inter_pix20,inter_pix21,inter_pix22,inter_pix23;
*/
logic [7:0] c00_sat,c01_sat,c02_sat,c03_sat,
            c10_sat,c11_sat,c12_sat,c13_sat,
            c20_sat,c21_sat,c22_sat,c23_sat,
            max00,max01,max10,max11,max20,max21;
logic signed [21:0] c00_sum_shift, c01_sum_shift, c02_sum_shift,c03_sum_shift, c10_sum_shift, 
		c11_sum_shift, c12_sum_shift, c13_sum_shift, c20_sum_shift, c21_sum_shift, c22_sum_shift,c23_sum_shift;


// Function to compute one multiply
function automatic logic signed [17:0] convolve_accumulate (
    input logic signed [8:0] px,
    input logic [71:0] kernel,
    input int ky,
    input int kx
);
    logic signed [8:0] kernel_val;
    logic signed [17:0] result;
    int index;
    begin
        index = (ky * 3 + kx) * 8;
        kernel_val = $signed({kernel[index + 7], kernel[index +: 8]});
        result = px * kernel_val;
        return result;
    end
endfunction

// === Required Declarations ===
typedef enum logic [2:0] {
  IDLE,
  LOAD_C00, LOAD_C01, LOAD_C02, LOAD_C03,
  DONE
} conv_state_t;

logic [3:0] pipeline_index;
conv_state_t state, next_state;
logic start, done, flag;

assign start = input_re_ffd;
// === Sequential FSM Block ===
always_ff @(posedge clk) begin
  if (!rst) begin
    state <= IDLE;
    pipeline_index <= 0;
    done <= 0;

    // Clear accumulators
    c00_sum <= 0; c01_sum <= 0; c02_sum <= 0; c03_sum <= 0;
    c10_sum <= 0; c11_sum <= 0; c12_sum <= 0; c13_sum <= 0;
    c20_sum <= 0; c21_sum <= 0; c22_sum <= 0; c23_sum <= 0;
  end else begin
    state <= next_state;

    if (state inside {LOAD_C00, LOAD_C01, LOAD_C02, LOAD_C03}) begin
      automatic int ky = pipeline_index / 3;
      automatic int kx = pipeline_index % 3;

      logic signed [8:0] px;

      case (state)
        LOAD_C00: begin
          px = $signed({1'b0, image_4x4_ffd[(ky)*32 + (kx)*8 +: 8]});
          c00_sum <= c00_sum + convolve_accumulate(px, conv_kernel_0_ffd, ky, kx);
          c10_sum <= c10_sum + convolve_accumulate(px, conv_kernel_1_ffd, ky, kx);
          c20_sum <= c20_sum + convolve_accumulate(px, conv_kernel_2_ffd, ky, kx);
        end
        LOAD_C01: begin
          px = $signed({1'b0, image_4x4_ffd[(ky)*32 + (kx+1)*8 +: 8]});
          c01_sum <= c01_sum + convolve_accumulate(px, conv_kernel_0_ffd, ky, kx);
          c11_sum <= c11_sum + convolve_accumulate(px, conv_kernel_1_ffd, ky, kx);
          c21_sum <= c21_sum + convolve_accumulate(px, conv_kernel_2_ffd, ky, kx);
        end
        LOAD_C02: begin
          px = $signed({1'b0, image_4x4_ffd[(ky+1)*32 + (kx)*8 +: 8]});
          c02_sum <= c02_sum + convolve_accumulate(px, conv_kernel_0_ffd, ky, kx);
          c12_sum <= c12_sum + convolve_accumulate(px, conv_kernel_1_ffd, ky, kx);
          c22_sum <= c22_sum + convolve_accumulate(px, conv_kernel_2_ffd, ky, kx);
        end
        LOAD_C03: begin
          px = $signed({1'b0, image_4x4_ffd[(ky+1)*32 + (kx+1)*8 +: 8]});
          c03_sum <= c03_sum + convolve_accumulate(px, conv_kernel_0_ffd, ky, kx);
          c13_sum <= c13_sum + convolve_accumulate(px, conv_kernel_1_ffd, ky, kx);
          c23_sum <= c23_sum + convolve_accumulate(px, conv_kernel_2_ffd, ky, kx);
        end
      endcase

      if (pipeline_index == 8)
        pipeline_index <= 0;
      else
        pipeline_index <= pipeline_index + 1;
    end

    if (state == DONE) done <= 1;
    else done <= 0;

    if (state == IDLE) begin

      	c00_sum <= 0; c01_sum <= 0; c02_sum <= 0; c03_sum <= 0;
    	c10_sum <= 0; c11_sum <= 0; c12_sum <= 0; c13_sum <= 0;
   	c20_sum <= 0; c21_sum <= 0; c22_sum <= 0; c23_sum <= 0;
    end

  end
end

// === FSM Next-State Logic ===
always_comb begin
  case (state)
    IDLE:       next_state = start ? LOAD_C00 : IDLE;
    LOAD_C00:   next_state = (pipeline_index == 8) ? LOAD_C01 : LOAD_C00;
    LOAD_C01:   next_state = (pipeline_index == 8) ? LOAD_C02 : LOAD_C01;
    LOAD_C02:   next_state = (pipeline_index == 8) ? LOAD_C03 : LOAD_C02;
    LOAD_C03:   next_state = (pipeline_index == 8) ? DONE     : LOAD_C03;
    DONE:       next_state = IDLE;
    default:    next_state = IDLE;
  endcase
end

// === Shift Output After Completion ===
always_comb begin

    c00_sum_shift = c00_sum >>> (shift_ffd + 3);
    c01_sum_shift = c01_sum >>> (shift_ffd + 3);
    c02_sum_shift = c02_sum >>> (shift_ffd + 3);
    c03_sum_shift = c03_sum >>> (shift_ffd + 3);

    c10_sum_shift = c10_sum >>> (shift_ffd + 3);
    c11_sum_shift = c11_sum >>> (shift_ffd + 3);
    c12_sum_shift = c12_sum >>> (shift_ffd + 3);
    c13_sum_shift = c13_sum >>> (shift_ffd + 3);

    c20_sum_shift = c20_sum >>> (shift_ffd + 3);
    c21_sum_shift = c21_sum >>> (shift_ffd + 3);
    c22_sum_shift = c22_sum >>> (shift_ffd + 3);
    c23_sum_shift = c23_sum >>> (shift_ffd + 3);

end



// 8-bit saturation
always_comb begin
  c00_sat = (c00_sum_shift < 0) ? 8'h00 :
               (c00_sum_shift > 255) ? 8'hFF :
               c00_sum_shift[7:0];

  c01_sat = (c01_sum_shift < 0) ? 8'h00 :
               (c01_sum_shift > 255) ? 8'hFF :
               c01_sum_shift[7:0];
  c02_sat = (c02_sum_shift < 0) ? 8'h00 :
               (c02_sum_shift > 255) ? 8'hFF :
               c02_sum_shift[7:0];

  c03_sat = (c03_sum_shift < 0) ? 8'h00 :
               (c03_sum_shift > 255) ? 8'hFF :
               c03_sum_shift[7:0];

  c10_sat = (c10_sum_shift < 0) ? 8'h00 :
               (c10_sum_shift > 255) ? 8'hFF :
               c10_sum_shift[7:0];

  c11_sat = (c11_sum_shift < 0) ? 8'h00 :
               (c11_sum_shift > 255) ? 8'hFF :
               c11_sum_shift[7:0];

  c12_sat = (c12_sum_shift < 0) ? 8'h00 :
               (c12_sum_shift > 255) ? 8'hFF :
               c12_sum_shift[7:0];

  c13_sat = (c13_sum_shift < 0) ? 8'h00 :
               (c13_sum_shift > 255) ? 8'hFF :
               c13_sum_shift[7:0];

  c20_sat = (c20_sum_shift < 0) ? 8'h00 :
               (c20_sum_shift > 255) ? 8'hFF :
               c20_sum_shift[7:0];

  c21_sat = (c21_sum_shift < 0) ? 8'h00 :
               (c21_sum_shift > 255) ? 8'hFF :
               c21_sum_shift[7:0];

  c22_sat = (c22_sum_shift < 0) ? 8'h00 :
               (c22_sum_shift> 255) ? 8'hFF :
               c22_sum_shift[7:0];

  c23_sat = (c23_sum_shift < 0) ? 8'h00 :
               (c23_sum_shift > 255) ? 8'hFF :
               c23_sum_shift[7:0];
end


// maxpooling
logic [7:0] y0_dff,y1_dff,y2_dff;
always_comb begin

  max00 = (c00_sat > c01_sat) ? c00_sat : c01_sat;
  max01 = (c02_sat > c03_sat) ? c02_sat : c03_sat;
  y0_dff = (max00 > max01) ? max00 : max01;

  max10 = (c10_sat > c11_sat) ? c10_sat : c11_sat;
  max11 = (c12_sat > c13_sat) ? c12_sat : c13_sat;
  y1_dff = (max10 > max11) ? max10 : max11;

  max20 = (c20_sat > c21_sat) ? c20_sat : c21_sat;
  max21 = (c22_sat > c23_sat) ? c22_sat : c23_sat;
  y2_dff = (max20 > max21) ? max20 : max21;

end

// miscellaneous logic
logic [15:0] output_addr_0_dff,output_addr_1_dff,output_addr_2_dff;
// logic output_we_0_dff,output_we_1_dff,output_we_2_dff;

// Result Address
always_ff @(posedge clk)begin

  if(!rst)begin
    output_addr_0 <= 16'h0000;
    output_addr_1 <= 16'h0000;
    output_addr_2 <= 16'h0000;
  end else if (done) begin
    output_addr_0 <= output_addr_0+1;
    output_addr_1 <= output_addr_2+1;
    output_addr_2 <= output_addr_2+1;
  end else begin
    output_addr_0 <= output_addr_0;
    output_addr_1 <= output_addr_2;
    output_addr_2 <= output_addr_2;
  end

end

// Output DFFs
logic [3:0] output_we_0_offset,output_we_1_offset,output_we_2_offset;

always_ff @(posedge clk) begin

if(!rst)begin
  y_0 <= '0;
  y_1 <= '0;
  y_2 <= '0;
end else begin
  y_0 <= y0_dff;
  y_1 <= y1_dff;
  y_2 <= y2_dff;
end

end

assign output_we_0 = done;
assign output_we_1 = done;
assign output_we_2 = done;

endmodule
