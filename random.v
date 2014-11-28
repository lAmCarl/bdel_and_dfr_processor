module random(o,clk);
    output [15:0]o;      
	 input clk;
	 wire [15:0]t;
    assign t[0] = o[15]^o[14];
    assign t[15:1] = o[14:0];
    tff0 u1(o[0], t[0], clk);
	 genvar i;
	 generate
		for (i = 1; i < 16; i = i + 1 ) begin: random
				tff1 ui(o[i], t[i], clk);
		end
	endgenerate
endmodule

module tff0(q,t,c);
    output q;
    input t,c;
    reg q;
    initial 
     begin 
      q=1'b1;
     end
    always @ (posedge c)
    begin
        if (t==1'b0) begin q=q; end
        else begin q=~q;  end
    end
endmodule

module tff1(q,t,c);
    output q;
    input t,c;
    reg q;
    initial 
     begin 
      q=1'b0;
     end
    always @ (posedge c)
    begin
        if (t==1'b0) begin q=q; end
        else begin q=~q;  end
    end
endmodule
