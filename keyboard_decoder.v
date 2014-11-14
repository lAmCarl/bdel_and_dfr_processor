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
		
	PS2_Controller(
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
		//...
		8'h72: keycode = 8'd99; //key down
		8'h75: keycode = 8'd100; //key up
		default: keycode = orig_keycode;
		endcase
	end
endmodule