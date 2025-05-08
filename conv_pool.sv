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

    // Adjusted name to avoid duplication in instantiation
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
always_ff @(posedge clk, rst) begin
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

logic signed [17:0] inter_pix00,inter_pix01,inter_pix02,inter_pix03,
                    inter_pix10,inter_pix11,inter_pix12,inter_pix13,
                    inter_pix20,inter_pix21,inter_pix22,inter_pix23;

logic [7:0] c00_sat,c01_sat,c02_sat,c03_sat,
            c10_sat,c11_sat,c12_sat,c13_sat,
            c20_sat,c21_sat,c22_sat,c23_sat,
            max00,max01,max10,max11,max20,max21;

genvar i,j;
generate
for(i = 0; i < 3 ; i = i + 1) begin
  for(j = 0; j < 3 ; j = j + 1) begin
    // kernel 0
    assign inter_pix00 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + j*8) +: 8]}) *
      $signed({conv_kernel_0[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix01 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_0[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix02 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + j*8) +: 8]}) *
      $signed({conv_kernel_0[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix03 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_0[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign c00_sum = c00_sum+inter_pix00;
    assign c01_sum = c01_sum+inter_pix01;
    assign c02_sum = c02_sum+inter_pix02;
    assign c03_sum = c03_sum+inter_pix03;

    // kernel 1
    assign inter_pix10 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + j*8) +: 8]}) *
      $signed({conv_kernel_1[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix11 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_1[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix12 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + j*8) +: 8]}) *
      $signed({conv_kernel_1[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix13 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_1[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign c10_sum = c10_sum+inter_pix10;
    assign c11_sum = c11_sum+inter_pix11;
    assign c12_sum = c12_sum+inter_pix12;
    assign c13_sum = c13_sum+inter_pix13;

    // kernel 2
    assign inter_pix20 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + j*8) +: 8]}) *
      $signed({conv_kernel_2[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix21 = (
      $signed({1'b0, image_4x4_ffd[(i*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_2[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix22 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + j*8) +: 8]}) *
      $signed({conv_kernel_2[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign inter_pix23 = (
      $signed({1'b0, image_4x4_ffd[((i+1)*32 + (j+1)*8) +: 8]}) *
      $signed({conv_kernel_2[(i*24 + j*8 + 7)], conv_kernel_0[(i*24 + j*8) +: 8]})
    ) >>> shift_ffd;

    assign c20_sum = c20_sum+inter_pix20;
    assign c21_sum = c21_sum+inter_pix21;
    assign c22_sum = c22_sum+inter_pix22;
    assign c23_sum = c23_sum+inter_pix23;

  end
end
endgenerate

// 8-bit saturation
always_comb begin

assign c00_sat = (c00_sum < 0) ? 8'h00 : 
		(c00_sum > 255) ? 8'hFF : c00_sum[7:0];
assign c01_sat = (c01_sum < 0) ? 8'h00 : 
		(c01_sum > 255) ? 8'hFF : c01_sum[7:0];
assign c02_sat = (c02_sum < 0) ? 8'h00 : 
		(c02_sum > 255) ? 8'hFF : c02_sum[7:0];
assign c03_sat = (c03_sum < 0) ? 8'h00 : 
		(c03_sum > 255) ? 8'hFF : c03_sum[7:0];

assign c10_sat = (c10_sum < 0) ? 8'h00 : 
		(c10_sum > 255) ? 8'hFF : c10_sum[7:0];
assign c11_sat = (c11_sum < 0) ? 8'h00 : 
		(c11_sum > 255) ? 8'hFF : c11_sum[7:0];
assign c12_sat = (c12_sum < 0) ? 8'h00 : 
		(c12_sum > 255) ? 8'hFF : c12_sum[7:0];
assign c13_sat = (c13_sum < 0) ? 8'h00 : 
		(c13_sum > 255) ? 8'hFF : c13_sum[7:0];

assign c20_sat = (c20_sum < 0) ? 8'h00 : 
		(c20_sum > 255) ? 8'hFF : c20_sum[7:0];
assign c21_sat = (c21_sum < 0) ? 8'h00 : 
		(c21_sum > 255) ? 8'hFF : c21_sum[7:0];
assign c22_sat = (c22_sum < 0) ? 8'h00 : 
		(c22_sum > 255) ? 8'hFF : c22_sum[7:0];
assign c23_sat = (c23_sum < 0) ? 8'h00 : 
		(c23_sum > 255) ? 8'hFF : c23_sum[7:0];
end

// maxpooling
logic [7:0] y0_dff,y1_dff,y2_dff;
always_comb begin

assign max00 = (c00_sat > c01_sat) ? c00_sat : c01_sat;
assign max01 = (c02_sat > c03_sat) ? c02_sat : c03_sat;
assign y0_dff = (max00 > max01) ? max00 : max01;

assign max10 = (c10_sat > c11_sat) ? c10_sat : c11_sat;
assign max11 = (c12_sat > c13_sat) ? c12_sat : c13_sat;
assign y1_dff = (max10 > max11) ? max10 : max11;

assign max20 = (c20_sat > c21_sat) ? c20_sat : c21_sat;
assign max21 = (c22_sat > c23_sat) ? c22_sat : c23_sat;
assign y2_dff = (max20 > max21) ? max20 : max21;

end

// miscellaneous logic
logic [15:0] output_addr_0_dff,output_addr_1_dff,output_addr_2_dff;
// logic output_we_0_dff,output_we_1_dff,output_we_2_dff;

// Result Address
always_ff @(posedge clk, rst)begin

  if(!rst)begin
    output_addr_0 <= '0;
    output_addr_1 <= '0;
    output_addr_2 <= '0;
  end else begin
    output_addr_0 <= output_we_0+1;
    output_addr_1 <= output_we_1+1;
    output_addr_2 <= output_we_2+1;
  end

end

// Output DFFs
// output_we only useful for > 1 pipeline?
always_ff @(posedge clk, rst) begin

if(!rst)begin
  y_0 <= '0;
  y_1 <= '0;
  y_2 <= '0;
  output_we_0 <= '0;
  output_we_1 <= '0;
  output_we_2 <= '0;
end else begin
  y_0 <= y0_dff;
  y_1 <= y1_dff;
  y_2 <= y2_dff;
  output_we_0 <= 1'b1;
  output_we_1 <= 1'b1;
  output_we_2 <= 1'b1;
end

end

endmodule
