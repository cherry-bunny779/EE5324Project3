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
always_ff @(posedge clk, negedge rst) begin
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


always_comb begin
  // Clear accumulation registers
  c00_sum = 0; c01_sum = 0; c02_sum = 0; c03_sum = 0;
  c10_sum = 0; c11_sum = 0; c12_sum = 0; c13_sum = 0;
  c20_sum = 0; c21_sum = 0; c22_sum = 0; c23_sum = 0;

  // Manually unrolled 2x2 output grid
  // Each (oy, ox) corresponds to one output value
  // Output positions: (0,0), (0,1), (1,0), (1,1)
  
  // Macro to simplify pixel access (row, col from 0 to 3)
  `define PIXEL(row, col) image_4x4_ffd[(row)*32 + (col)*8 +: 8]
  `define KERNEL_VAL(kernel, ky, kx) $signed({kernel[((ky)*3 + (kx))*8 + 7], kernel[((ky)*3 + (kx))*8 +: 8]})

  // (0,0) Output
  for (int ky = 0; ky < 3; ky++) begin
    for (int kx = 0; kx < 3; kx++) begin
      automatic logic signed [8:0] px = $signed({1'b0, `PIXEL(ky, kx)});
      c00_sum += (px * `KERNEL_VAL(conv_kernel_0_ffd, ky, kx));
      c10_sum += (px * `KERNEL_VAL(conv_kernel_1_ffd, ky, kx));
      c20_sum = c20_sum + (px * `KERNEL_VAL(conv_kernel_2_ffd, ky, kx));
    end
  end

  // (0,1) Output
  for (int ky = 0; ky < 3; ky++) begin
    for (int kx = 0; kx < 3; kx++) begin
      automatic logic signed [8:0] px = $signed({1'b0, `PIXEL(ky, kx+1)});
      c01_sum += (px * `KERNEL_VAL(conv_kernel_0_ffd, ky, kx));
      c11_sum += (px * `KERNEL_VAL(conv_kernel_1_ffd, ky, kx));
      c21_sum = c21_sum + (px * `KERNEL_VAL(conv_kernel_2_ffd, ky, kx));
    end
  end

  // (1,0) Output
  for (int ky = 0; ky < 3; ky++) begin
    for (int kx = 0; kx < 3; kx++) begin
      automatic logic signed [8:0] px = $signed({1'b0, `PIXEL(ky+1, kx)});
      c02_sum += (px * `KERNEL_VAL(conv_kernel_0_ffd, ky, kx));
      c12_sum += (px * `KERNEL_VAL(conv_kernel_1_ffd, ky, kx));
      c22_sum = c22_sum + (px * `KERNEL_VAL(conv_kernel_2_ffd, ky, kx));
    end
  end

  // (1,1) Output
  for (int ky = 0; ky < 3; ky++) begin
      //$display("img4x4 = %h\nkernel = %h", image_4x4_ffd, conv_kernel_2_ffd);
    for (int kx = 0; kx < 3; kx++) begin
      automatic logic signed [8:0] px = $signed({1'b0, `PIXEL(ky+1, kx+1)});
      c03_sum += (px * `KERNEL_VAL(conv_kernel_0_ffd, ky, kx));
      c13_sum += (px * `KERNEL_VAL(conv_kernel_1_ffd, ky, kx));
      c23_sum = c23_sum + (px * `KERNEL_VAL(conv_kernel_2_ffd, ky, kx));
      //$display("c23_sum: %h kernel %d\n",c23_sum,`KERNEL_VAL(conv_kernel_2_ffd, ky, kx) );
    end
  end

  c00_sum_shift = c00_sum >>> shift_ffd+3;
  c01_sum_shift = c01_sum >>> shift_ffd+3;
  c02_sum_shift = c02_sum >>> shift_ffd+3;
  c03_sum_shift = c03_sum >>> shift_ffd+3;

  c10_sum_shift = c10_sum >>> shift_ffd+3;
  c11_sum_shift = c11_sum >>> shift_ffd+3;
  c12_sum_shift = c12_sum >>> shift_ffd+3;
  c13_sum_shift = c13_sum >>> shift_ffd+3;

  c20_sum_shift = c20_sum >>> shift_ffd+3;
  c21_sum_shift = c21_sum >>> shift_ffd+3;
  c22_sum_shift = c22_sum >>> shift_ffd+3;
  c23_sum_shift = c23_sum >>> shift_ffd+3;

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
always_ff @(posedge clk, negedge rst)begin

  if(!rst)begin
    output_addr_0 <= 16'hFFFC;
    output_addr_1 <= 16'hFFFC;
    output_addr_2 <= 16'hFFFC;
  end else begin
    output_addr_0 <= output_addr_0+1;
    output_addr_1 <= output_addr_2+1;
    output_addr_2 <= output_addr_2+1;
  end

end

// Output DFFs
logic [3:0] output_we_0_offset,output_we_1_offset,output_we_2_offset;

always_ff @(posedge clk, negedge rst) begin

if(!rst)begin
  y_0 <= '0;
  y_1 <= '0;
  y_2 <= '0;
  output_we_0_offset <= 4'b0100;
  output_we_1_offset <= 4'b0100;
  output_we_2_offset <= 4'b0100;
end else if (output_we_0_offset[3] == 1) begin
  y_0 <= y0_dff;
  y_1 <= y1_dff;
  y_2 <= y2_dff;
  output_we_0_offset <= output_we_0_offset;
  output_we_1_offset <= output_we_1_offset;
  output_we_2_offset <= output_we_2_offset;
end else begin
  y_0 <= y0_dff;
  y_1 <= y1_dff;
  y_2 <= y2_dff;
  output_we_0_offset <= output_we_0_offset+1;
  output_we_1_offset <= output_we_1_offset+1;
  output_we_2_offset <= output_we_2_offset+1;
end

end

assign output_we_0 = output_we_0_offset[3];
assign output_we_1 = output_we_1_offset[3];
assign output_we_2 = output_we_2_offset[3];

endmodule
