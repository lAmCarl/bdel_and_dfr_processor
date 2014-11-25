module keyboard_decoder(CLOCK_50, PS2_CLK, PS2_DAT, key_pressed, keycode);
	input CLOCK_50;
	inout PS2_CLK, PS2_DAT;
	output reg key_pressed = 0;
	output reg [7:0] keycode = 0;
	
	reg [7:0] orig_keycode = 0;
	wire[7:0] received_data;
	wire received_data_en;
	reg [7:0] data = 0;
	reg ignore = 0;
		
	PS2_Controller myController(
			.CLOCK_50(CLOCK_50),
			.PS2_CLK(PS2_CLK),
			.PS2_DAT(PS2_DAT),
			.received_data(received_data),
			.received_data_en(received_data_en));
			
	always@(posedge CLOCK_50) begin
		if(received_data_en) begin
			if(!ignore) begin
				if(received_data != 8'hE0) begin
					if(received_data == 8'hF0) begin
						ignore <= 1;
						key_pressed <= 0;
					end
					else begin
						key_pressed <= 1;
						data <= received_data;
						orig_keycode <= keycode;
					end
				end
			end
			else begin
				key_pressed <= 0;
				ignore <= 0;
			end
		end 
		else begin
		key_pressed <= 0;
		end
	end
	
	always@(*) begin
		case(data)
8'h45: keycode = 8'd0;
8'h16: keycode = 8'd1;
8'h1E: keycode = 8'd2;
8'h26: keycode = 8'd3;
8'h25: keycode = 8'd4;
8'h2E: keycode = 8'd5;
8'h36: keycode = 8'd6;
8'h3D: keycode = 8'd7;
8'h3E: keycode = 8'd8;
8'h46: keycode = 8'd9;
8'h1C: keycode = 8'd10;
8'h32: keycode = 8'd11;
8'h21: keycode = 8'd12;
8'h23: keycode = 8'd13;
8'h24: keycode = 8'd14;
8'h2B: keycode = 8'd15;
8'h34: keycode = 8'd16;
8'h33: keycode = 8'd17;
8'h43: keycode = 8'd18;
8'h3B: keycode = 8'd19;
8'h42: keycode = 8'd20;
8'h4B: keycode = 8'd21;
8'h3A: keycode = 8'd22;
8'h31: keycode = 8'd23;
8'h44: keycode = 8'd24;
8'h4D: keycode = 8'd25;
8'h15: keycode = 8'd26;
8'h2D: keycode = 8'd27;
8'h1B: keycode = 8'd28;
8'h2C: keycode = 8'd29;
8'h3C: keycode = 8'd30;
8'h2A: keycode = 8'd31;
8'h1D: keycode = 8'd32;
8'h22: keycode = 8'd33;
8'h35: keycode = 8'd34;
8'h1A: keycode = 8'd35;
		8'h5A: keycode = 8'd98; // enter
		8'h72: keycode = 8'd99; //key down
		8'h75: keycode = 8'd100; //key up
      8'h29: keycode = 8'd36; // space
		8'h66: keycode = 8'd37; // delete
      8'h49: keycode = 8'd38; // period
		default: keycode = 8'd255;
		endcase
	end
endmodule