module fixedpoint_tb();

logic signed [17:0] c, e;
logic [8:0] a,b,d;

initial begin

$display("Test Fixed Point Numbers SV\n");

a = 9'b11000_0001;  // signed 2's comp fp -15.875, 3 bits fraction
b = 9'b00000_0101;  // positive 5

/*
c = a*b;
d = c >>> 3; 
// results d = 0000_00110 (wrong) need to make larger c, if d 8 bits, automatically lower 8 bits of c?
*/
c = $signed(a)*$signed(b);
e = c >>> 3;
d = e[7:0];
$display("intermediate: %b shifted: %b results: %b\n",c,e,d);
// intermediate: 0101101000110011 results: 01000110; a and b must be sign extended AND declared as "signed"
// intermediate: 111010011100110011 shifted: 111111010011100110 results: 011100110 Seems correct. but interpret results as fp or 2's?
end

endmodule
