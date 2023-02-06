module MyDesign (
//---------------------------------------------------------------------------
//Control signals
  input   wire dut_run                    , 
  output  reg dut_busy                   ,
  input   wire reset_b                    ,  
  input   wire clk                        ,
 
//---------------------------------------------------------------------------
//Input SRAM interface
  output reg        input_sram_write_enable    ,
  output reg [11:0] input_sram_write_addresss  ,
  output reg [15:0] input_sram_write_data      ,
  output reg [11:0] input_sram_read_address    ,
  input wire [15:0] input_sram_read_data       ,

//---------------------------------------------------------------------------
//Output SRAM interface
  output reg        output_sram_write_enable    ,
  output reg [11:0] output_sram_write_addresss  ,
  output reg [15:0] output_sram_write_data      ,
  output reg [11:0] output_sram_read_address    ,
  input wire [15:0] output_sram_read_data       ,

//---------------------------------------------------------------------------
//Scratchpad SRAM interface
  output reg        scratchpad_sram_write_enable    ,
  output reg [11:0] scratchpad_sram_write_addresss  ,
  output reg [15:0] scratchpad_sram_write_data      ,
  output reg [11:0] scratchpad_sram_read_address    ,
  input wire [15:0] scratchpad_sram_read_data       ,

//---------------------------------------------------------------------------
//Weights SRAM interface                                                       
  output reg        weights_sram_write_enable    ,
  output reg [11:0] weights_sram_write_addresss  ,
  output reg [15:0] weights_sram_write_data      ,
  output reg [11:0] weights_sram_read_address    ,
  input wire [15:0] weights_sram_read_data       

);


//MARK: my code begins hereeeeeeeeeeeeeeeee
//Memories
reg [7:0] N_input;
reg signed [7:0] Kernel_Matrix [0:8]; //matrix for storing kernel
reg [3:0] Kernel_index; //indexes above array
reg signed [7:0] Input_Matrix_Section [0:15]; //matrix for storing 16 inputs 4x4
reg [4:0] Input_Matrix_index; //indexes above array
reg signed [19:0] Conv_Output [0:3];
reg signed [15:0] conv_temp_1;
reg signed [15:0] conv_temp_2;
reg signed [15:0] conv_temp_3;
reg signed [15:0] conv_temp_4;
reg [3:0] mult_input_iterator; //special increment the input matrix selector for +2 jumps
reg [3:0] mult_iteration;//when count is 4, new set of inputs and operations
//^used to index kernel 
reg [7:0] temp_pool_1; //stores higher of first 2 outputs
reg [7:0] temp_pool_2; //stores higher of second 2 outputs
reg [7:0] pool_to_write; //stores final thing to write to output
reg [15:0] output_maxpooling;


//Logical memories
reg [7:0] count_reading_row_switch;
reg [7:0] count_reading_column_switch;
reg [11:0] read_iter_counter;
reg [11:0] input_req_base;
reg [11:0] input_req_offset;//based on N
reg [11:0] input_req_row_strider; //based on N 
reg [11:0] output_req_base;
reg [11:0] output_req_offset;//based on N
reg [11:0] output_req_row_strider; //based on N 
reg [11:0] Extra_Matrix;

//Kernel
reg [11:0] kernel_req_base;
reg [11:0] kernel_req_offset;
reg [2:0] kernel_iter_counter;

//FSM 
reg [3:0] Top_Level_Current_State;
reg [3:0] Top_Level_Next_State;

reg [3:0] Reading_Current_State;
reg [3:0] Reading_Next_State;

reg [3:0] Kernel_Current_State;
reg [3:0] Kernel_Next_State;

reg [3:0] Conv_Current_State;
reg [3:0] Conv_Next_State;

//FSM states encoding
parameter [3:0]
  S0 = 4'b0000,//waiting for dut_run 
  S1 = 4'b0001,
  S2 = 4'b0010,
  S3 = 4'b0011,
  S4 = 4'b0100,
  S5 = 4'b0101,
  S6 = 4'b0110,
  S7 = 4'b0111,
  S8 = 4'b1000,
  S9 = 4'b1001,
  S10 = 4'b1010,
  S11 = 4'b1011,
  S12 = 4'b1100; 

 //FSM flags 
 //Inputs
 reg input_begin;
 reg N_received;
 reg new_inputs;
 reg Final_Input_Found;
 reg conv_in_progress;
 reg relu_done_extra;

 //Kernel
 reg kernel_begin;
 reg kernel_ready;

 //Convolution
 reg conv_begin; //
 reg conv_ready; //used to control beginning of mult until enough inputs allocated
 //not used? Mark: Use it goddammit
 reg conv_done; //Operation done, to start next use as control?
 reg relu_done;//need to use for control or remove
 reg maxpooling_done; //need to use for control or remove
 reg maxpooling_flag; //controls which location within address to write, packing control

 reg output_offset;
 reg [10:0] relu_counter; //added

 //---------------------------------------------------------------------------//
 //Overall system control 
always@(posedge clk or negedge reset_b)
begin
  if(!reset_b)
  begin
    Top_Level_Current_State <= S0;
    Reading_Current_State <= S0;
    Kernel_Current_State <= S0;
    Conv_Current_State <= S0;
  end
  else 
  begin
    Top_Level_Current_State <= Top_Level_Next_State;
    Reading_Current_State <= Reading_Next_State;
    Kernel_Current_State <= Kernel_Next_State;
    Conv_Current_State <= Conv_Next_State;
  end
end
 //---------------------------------------------------------------------------//
 //System control FSM - control
 always@(*)
 begin
   case (Top_Level_Current_State)
   S0: //beginning/idle state 
   begin
     if(dut_run)
      begin
          Top_Level_Next_State = S1;  
      end
     else 
     begin
       Top_Level_Next_State = S0;
     end
   end
   S1://N_check
   begin
    if(N_received)
      begin
        if(N_input == 8'hFF) Top_Level_Next_State = S5;
        else Top_Level_Next_State = S2;
        

        new_inputs = 1'b0;
      end
    else 
      begin
      Top_Level_Next_State = S1;
      new_inputs = 1'b1;
      end

   end
   S2://conv and kernel matrices begin filling UNTIL we have enough to begin convolution/relu
   begin
   //set dut_busy high
     if(conv_ready)
      begin
       Top_Level_Next_State = S4;
      end
     else 
      begin
       Top_Level_Next_State = S2;
       new_inputs = 1'b0;
      end
   end
   S3://in-progress state for convolution and relu, since kernel is full
   begin
     if(relu_done)
     begin
       Top_Level_Next_State = S4;
     end
     else begin
       Top_Level_Next_State = S2;
     end
   end
   S4://in-progress state for maxpooling
   begin
     if(maxpooling_done)
     begin
       Top_Level_Next_State = S1;
     end
     else begin
       Top_Level_Next_State = S4;
     end
   end
   S5:
   begin//in-progress state for output writing/FFFF
       Top_Level_Next_State = S0;
   end
   default: Top_Level_Next_State = S0;
   endcase
 end
 //---------------------------------------------------------------------------//
 //---------------------------------------------------------------------------//
//System control FSM - FF
always@(posedge clk)
begin
  case(Top_Level_Current_State)
  S0:
    begin
      kernel_begin <= 1'b0;
      input_begin <=1'b0;
      conv_begin <= 1'b0;
      dut_busy <= 1'b0;
      new_inputs <= 1'b0;
    end
  S1:
    begin
      dut_busy <= 1'b1;
      kernel_begin <= 1'b1;
      input_begin <=1'b1;
    end
  S2:
    begin
      kernel_begin <= 1'b0;
      input_begin <=1'b0;
      dut_busy <= 1'b1;
    end
  S3://only Reading for now
  begin

  end
  S4:
  begin
        if(conv_ready)
      begin
        conv_begin <= 1'b1;
      end
      else
      begin
        conv_begin <= 1'b0;
      end

  end
  S5:
  begin
    dut_busy <= 1'b0;
  end
  endcase
end
//---------------------------------------------------------------------------//

//---------------------------------------------------------------------------//
//Kernel - control
always@(*)
begin
  case(Kernel_Current_State)
  S0:
  begin
    if(kernel_begin) 
    begin
    Kernel_Next_State = S1;
    end
    else 
    begin
    Kernel_Next_State = S0;
    end
  end
  S1:
  begin
    //put address on bus
    Kernel_Next_State = S2;
  end
  S2:
  begin
    //buffer
    //do nothing
    Kernel_Next_State = S3;
  end
  S3:
  begin
    //allocate
    Kernel_Next_State = S4;
  end
  S4:
  begin
  //increment or finish
    if(kernel_iter_counter >= 12'd4) 
    begin
    Kernel_Next_State = S0;
    kernel_ready = 1'b1;
    end
    else 
    begin
      Kernel_Next_State = S1;
    end
  end
  default : Kernel_Next_State = S0;
  endcase
end
//---------------------------------------------------------------------------//
//Kernel - FFs
always@(posedge clk)
begin
  case(Kernel_Current_State)
  S0:
  begin
    //kernel_begin <= 1'b0;
    kernel_ready <= 1'b0;
    //kernel_inprogress <= 1'b0;
    kernel_req_base <= 1'b0;
    kernel_req_offset <= 1'b0;
    kernel_iter_counter <= 1'b0;
    Kernel_index <= 1'b0;
  end
  S1:
  begin
    //put address on bus
    weights_sram_read_address <= kernel_req_base + kernel_req_offset;
  end
  S2:
  begin
    //buffer
    //do nothing
  end
  S3:
  begin
    //allocate
    Kernel_Matrix[Kernel_index][7:0] <= weights_sram_read_data[15:8];
    Kernel_Matrix[Kernel_index + 1'b1][7:0] <= weights_sram_read_data[7:0];
  end
  S4:
  begin
  //increment or finish
    kernel_iter_counter <= kernel_iter_counter + 1'd1;
    Kernel_index <= Kernel_index + 2'd2;
    kernel_req_offset <= kernel_req_offset + 1'd1;
  end
  endcase
  end
//---------------------------------------------------------------------------//
//Reading control
always@(*)
begin
  case(Reading_Current_State) 
  S0:
  begin
    //full reset/known state
    Reading_Next_State = S1;
  end
  S1:
  begin
    //MARK: reset in between/begin 
    if(input_begin) Reading_Next_State = S2;
    else Reading_Next_State = S1;
  end
  S2:
  begin
    if(N_received == 1'b0)
      begin
      Reading_Next_State = S4;
      end

    else
      begin
      Reading_Next_State = S3;
      end
  end
  S4:
  begin
    Reading_Next_State = S5;
  end
  S5:
  begin
    Reading_Next_State = S2;
  end
  S3:
  begin
    if (Final_Input_Found)
      begin
      Reading_Next_State = S0;
      end
    else
      begin
    Reading_Next_State = S6;
      end
  end
  S6:
    begin
      if (conv_in_progress)
        begin
         Reading_Next_State = S6;
        end
      else
        begin
        Reading_Next_State = S8;
        end
  end
  S7:
  begin
  Reading_Next_State = S8;
  end
  S8:
  begin
    if(count_reading_row_switch >= ((N_input >> 1) - 2'd1))
    begin
    Reading_Next_State = S9;
    end
    else
    begin
    Reading_Next_State = S2;
    end
  end
   S9:
   begin
   Reading_Next_State = S1;
   end
default : Reading_Next_State = S0;
endcase
end
//---------------------------------------------------------------------------//
//Reading FFs
always@(posedge clk)
begin
  //MARK: delete if doesn't work
  if(dut_run)
  begin

  input_req_base <= 12'b0;
  conv_ready <= 1'b0;
  input_req_offset <= 12'b0;
  input_req_row_strider <= 12'b0;
  count_reading_row_switch <= 8'b0;
  count_reading_column_switch <= 8'b0;
  N_received <= 1'b0;
  Final_Input_Found <= 1'b0;
  Extra_Matrix <= 12'b0;
  N_input <= 8'b0;
  
  end
  else
  begin
  input_req_base <= input_req_base;
  conv_ready <= conv_ready;
  input_req_offset <= input_req_offset;
  input_req_row_strider <= input_req_row_strider;
  count_reading_row_switch <= count_reading_row_switch;
  count_reading_column_switch <= count_reading_column_switch;
  N_received <= N_received;
  Final_Input_Found <= Final_Input_Found;
  Extra_Matrix <= Extra_Matrix;
  N_input <= N_input;
  end
  case(Reading_Current_State) 
  S0:
  begin
    //full reset state
    //if(!reset_b) 
    //begin
    input_req_base <= 12'b0;
    //end
    conv_ready <= 1'b0; 
    input_req_offset <= 12'b0;
    input_req_row_strider <= 12'b0;
    count_reading_row_switch <= 8'b0;
    count_reading_column_switch <= 8'b0;
    read_iter_counter <= 12'b0;
    //kernel_req_base <= 12'b0; //removed
    //kernel_req_offset <= 12'b0; //removed
    N_received <= 1'b0;
    Final_Input_Found <= 1'b0;
  Extra_Matrix <= 12'b0;
  end
  S1:
  begin
    //MARK: reset in between, enables reuse of storage
    //preserve current SRAM address 
  
    Input_Matrix_index <= 4'b0;
   
    count_reading_column_switch <= 8'b0;
    count_reading_row_switch <= 8'b0;
  
    N_received <= 1'b0;
  
  conv_ready <= 1'b0;
  input_req_row_strider <= 12'b0;
  input_req_offset <= 12'b0;
  input_req_base <= 12'b0;
  //Final_Input_Found <= 1'b0;

  end
  S2:
  begin
    //assert: put address on bus
    //S3: if N needed, conditional
    begin
  if (N_input == 8'hFF)
  begin
    Final_Input_Found <= 1'b1;
  end
  else
  begin
      input_sram_read_address <= input_req_base + input_req_offset + input_req_row_strider + Extra_Matrix;
  end
  end

  end
  S3:
  begin
  //
    //Cannot hit this state for N 
    //Calculate req offset for next iteration
    case(Input_Matrix_index)
    5'd0: 
    begin
      input_req_offset <= 5'd1;
    end
    5'd2:
    begin
      input_req_offset <= (N_input>>1);
    end
    5'd4:
    begin
      input_req_offset <= ((N_input>>1) + 1'b1);
    end
    5'd6:
    begin
      input_req_offset <= N_input;
    end    
    5'd8:
    begin
      input_req_offset <= N_input + 1'b1;
    end
    5'd10:
    begin
      input_req_offset <= N_input + (N_input>>1);
    end    
    5'd12:
    begin
      input_req_offset <= (N_input + (N_input>>1) + 1'b1);
    end
    5'd14:
    begin
      input_req_offset <= 0;
      input_req_base <= input_req_base + 1'd1;
      count_reading_column_switch <= count_reading_column_switch + 1'd1;
      conv_ready <= 1'b1;
    end
    5'd16:
    begin
      input_req_offset <= 1'b1;
      //rollover storage
      Input_Matrix_index <= 1'b0;
      conv_ready <= 1'b0;

    end
    default: Input_Matrix_index <= 1'b0;
    endcase
  end
  S4:
  begin
    //buffer state
    //do nothing
  end
  S5:
  begin
    //we take N
    //condition for EOF or S2 (keep or stop reading)
    N_input <= input_sram_read_data[7:0];

    N_received <= 1'b1;//TODO MARK: need to set this low at the end of the matrix
    input_req_base <= input_req_base + 2'd1;
  end
  S6:
  begin
  //Cannot hit this state for N
    //read assign state 
    //increment counter, req offsets
  if (count_reading_row_switch >= ((N_input >> 1) - 2'd1) ||  conv_in_progress)
  begin
  //
  end
  else
  begin
    Input_Matrix_Section[Input_Matrix_index + 1'b1][7:0] <= input_sram_read_data[7:0];
    Input_Matrix_Section[Input_Matrix_index][7:0] <= input_sram_read_data[15:8];
  end
  end
  S7:
  begin
    //Input_Matrix_index <= Input_Matrix_index + 2'd2;//should not happen for reading N 
  end
  S8:
  begin
    //increment memory array index
  Input_Matrix_index <= Input_Matrix_index + 2'd2;//should not happen for reading N 
    if(count_reading_column_switch >= ((N_input >> 1) - 2'd1))
    begin
      input_req_base <= 1'b1;
      input_req_row_strider <= input_req_row_strider + N_input;
      count_reading_column_switch <= 1'b0;
      count_reading_row_switch <= count_reading_row_switch + 1'b1;
    end
    else 
  begin
      input_req_row_strider <= input_req_row_strider;
      count_reading_column_switch <= count_reading_column_switch;
      count_reading_row_switch <= count_reading_row_switch;
    N_received <= N_received;
    end
  end
  S9:
  begin
  Extra_Matrix <= Extra_Matrix + ( (N_input >> 1 )*N_input) + 1'b1;
    //N_received <= 1'b0;
  end
endcase
end
//---------------------------------------------------------------------------//
//Convolution FSM
always@(*)
begin
  case(Conv_Current_State)
  S0:
  begin
    Conv_Next_State = S1;
  end
  S1:
  begin
    if(conv_begin)
    begin
      Conv_Next_State = S2;
    end
    else begin
      Conv_Next_State = S1;
    end
  end
  S2:
  begin
    if (relu_done_extra)
  begin
  Conv_Next_State = S12;
  end
  else
  begin
  Conv_Next_State = S3;
  end
  end
  S3:
  begin
  Conv_Next_State = S4;
  end
  S4:
  begin
    Conv_Next_State = S5;
  end
  S5:
  begin
    if(mult_iteration >= 4'd9)
    begin
      Conv_Next_State = S6;
    end
    else 
    begin
      Conv_Next_State = S2;
    end
  end
  S6:
  begin
    Conv_Next_State = S7;
  end
  S7:
  begin
    Conv_Next_State = S8;
  end
  S8:
  begin
    Conv_Next_State = S9;
  end
  S9:
  begin
    Conv_Next_State = S10;
  end
  S10:
  begin
    Conv_Next_State = S11;
  end
  S11:
  begin
  Conv_Next_State = S1;
  end
  //S12:
  //begin
  //Conv_Next_State = S1;
  //end
  default : Conv_Next_State = S0;

  endcase
end

//---------------------------------------------------------------------------//
//Convolution FFs
always@(posedge clk)
begin
  if (dut_run)
  begin
  
  mult_iteration <= 4'b0;
  mult_input_iterator <= 4'b0;
  relu_done <= 1'b0;
  conv_done <= 1'b0;
  maxpooling_flag <= 1'b1;
  maxpooling_done <= 1'b0;
  output_req_base <= 12'b0;
  output_req_offset <= 12'b0;
  output_req_row_strider <= 12'b0;
  output_offset <= 12'b0;
  conv_in_progress <= 1'b0;
  output_maxpooling <= 16'b0;
  output_sram_write_addresss <= 16'b0;
  relu_counter <= 11'b0;
  relu_done_extra <= 1'b0; 
  end
  else
  begin
  
  mult_iteration <= mult_iteration;
  mult_input_iterator <= mult_input_iterator;
  relu_done <= relu_done;
  conv_done <= conv_done;
  maxpooling_flag <= maxpooling_flag;
  maxpooling_done <= maxpooling_done;
  output_req_base <= output_req_base;
  output_req_offset <= output_req_offset;
  output_req_row_strider <= output_req_row_strider;
  output_offset <= output_offset;
  conv_in_progress <= conv_in_progress;
  output_maxpooling <= output_maxpooling;
  output_sram_write_addresss <= output_sram_write_addresss;
  relu_counter <= relu_counter;
  relu_done_extra <= relu_done_extra; 
  
  end
  case(Conv_Current_State)
  S0:
  begin
  mult_iteration <= 4'b0;
  mult_input_iterator <= 4'b0;
  relu_done <= 1'b0;
  conv_done <= 1'b0;
  maxpooling_flag <= 1'b1;
  maxpooling_done <= 1'b0;
  output_req_base <= 12'b0;
  output_req_offset <= 12'b0;
  output_req_row_strider <= 12'b0;
  //
  output_offset <= 12'b0;
  conv_in_progress <= 1'b0;
  
  Conv_Output[0][19:0] <= 20'b0;
  Conv_Output[1][19:0] <= 20'b0;
  Conv_Output[2][19:0] <= 20'b0;
  Conv_Output[3][19:0] <= 20'b0;
  output_maxpooling <= 16'b0;
  output_sram_write_addresss <= 16'b0;
  relu_counter <= 11'b0;
  relu_done_extra <= 1'b0;
  end
  S1:
  begin
  conv_temp_1 <= 16'b0;
  conv_temp_2 <= 16'b0;
  conv_temp_3 <= 16'b0;
  conv_temp_4 <= 16'b0;
  Conv_Output[0][19:0] <= 20'b0;
  Conv_Output[1][19:0] <= 20'b0;
  Conv_Output[2][19:0] <= 20'b0;
  Conv_Output[3][19:0] <= 20'b0;
  maxpooling_done <= 1'b0; //added

  if(relu_counter >= (((N_input-2)>>1) * ((N_input-2)>>1))) 
  begin
  relu_counter <= 11'b0;
  maxpooling_flag <= 1'b1;
  output_maxpooling <= 16'b0;
  //relu_done_extra <= 1'b1;
    maxpooling_done <= 1'b1;
  end
  else
  begin
   maxpooling_done <= 1'b0; //added
  end
  //end added
  end
  S2://first round
  begin
  conv_in_progress <= 1'b1;
  conv_temp_1 <= Input_Matrix_Section[8'd0 + (mult_input_iterator)] * Kernel_Matrix[(mult_iteration)];
  conv_temp_2 <= Input_Matrix_Section[8'd1 + (mult_input_iterator)] * Kernel_Matrix[(mult_iteration)];
  conv_temp_3 <= Input_Matrix_Section[8'd4 + (mult_input_iterator)] * Kernel_Matrix[(mult_iteration)];
  conv_temp_4 <= Input_Matrix_Section[8'd5 + (mult_input_iterator)] * Kernel_Matrix[(mult_iteration)];
  end
  S3://increment
  begin
  Conv_Output[0][19:0] <= Conv_Output[0] + conv_temp_1;
  Conv_Output[1][19:0] <= Conv_Output[1] + conv_temp_2;
  Conv_Output[2][19:0] <= Conv_Output[2] + conv_temp_3;
  Conv_Output[3][19:0] <= Conv_Output[3] + conv_temp_4;
  end
  S4:
  begin
  mult_iteration <= mult_iteration + 8'd1;//until 9?
  end
  S5:
  begin
   case(mult_iteration)
   4'd3:
   begin
   mult_input_iterator <= mult_input_iterator + 2'd2;
   end
   4'd6:
   begin
   mult_input_iterator <= mult_input_iterator + 2'd2;
   end
   4'd9:
   begin
   mult_input_iterator <= 1'b0;
   mult_iteration <= 1'b0;
   //relu_ready <= 1'b1;
   end
   default: mult_input_iterator <= mult_input_iterator + 1'd1;
   endcase
  end
  S6://ReLu
  begin
  relu_counter <= relu_counter + 1'b1; //added
  conv_in_progress <= 1'b0;
 if (Conv_Output[0][19] == 1'b1)//MSN 1 is -ve
    begin
      Conv_Output[0] <= 'h0;
    end 
  else if(Conv_Output[0] >= 20'd127)//saturate
    begin
      Conv_Output[0] <= 8'd127;
    end

  else
    begin
      Conv_Output[0] <= Conv_Output[0];
    end
  
if (Conv_Output[1][19] == 1'b1)//MSN 1 is -ve
    begin
      Conv_Output[1] <= 'h0;
    end
  else if(Conv_Output[1] >= 20'd127)//saturate
    begin
      Conv_Output[1] <= 8'd127;
    end

  else
    begin
      Conv_Output[1] <= Conv_Output[1];
    end

if(Conv_Output[2][19] == 1'b1)//MSN 1 is -ve
    begin
      Conv_Output[2] <= 'h0;
    end
  else if(Conv_Output[2] >= 20'd127)//saturate
    begin
      Conv_Output[2] <= 8'd127;
    end

  else
    begin
      Conv_Output[2] <= Conv_Output[2];
    end

  if(Conv_Output[3][19] == 1'b1)//MSB 1 is -ve
    begin
      Conv_Output[3] <= 'h0;
    end
  else if(Conv_Output[3] >= 20'd127)//saturate
    begin
      Conv_Output[3] <= 8'd127;
    end
  else
    begin
      Conv_Output[3] <= Conv_Output[3];
    end
  end
  S7:
  begin
    relu_done <= 1'b1;
      if(Conv_Output[0] > Conv_Output[1])
        begin
          temp_pool_1[7:0] <= Conv_Output[0];
        end
      else
        begin
          temp_pool_1[7:0] <= Conv_Output[1];
        end  

      if(Conv_Output[2] > Conv_Output[3])
        begin
          temp_pool_2[7:0] <= Conv_Output[2];
        end
      else 
        begin
          temp_pool_2[7:0] <= Conv_Output[3];
      end
  end

  S8:
  begin
    if(temp_pool_1[7:0] > temp_pool_2[7:0])
    begin
     pool_to_write[7:0] <= temp_pool_1;
    end
    else 
    begin
     pool_to_write[7:0] <= temp_pool_2;
    end

    if(maxpooling_flag)
      begin
      maxpooling_flag <= 1'b0;
      end
    else
      begin
     maxpooling_flag <= 1'b1; 
      end
  end
  S9://send data
  begin
  //only overwrite old with new 
  if(maxpooling_flag)
  begin
    output_maxpooling[7:0] <= pool_to_write[7:0];
  end
  else 
  begin
    //output_maxpooling[15:8] <= pool_to_write[7:0];
    //added below
    if(relu_counter >= ((N_input-2)>>1) * ((N_input-2)>>1)) //added
    begin
      output_maxpooling[15:8] <= pool_to_write[7:0];
      output_maxpooling[7:0] <= 8'b0;
    end
    else begin
      output_maxpooling[15:8] <= pool_to_write[7:0];
    end
  end
    

  end
  S10:
  begin

    if(maxpooling_flag || relu_counter >= (((N_input-2)>>1) * ((N_input-2)>>1)))
    begin
      output_sram_write_data[15:0] <= output_maxpooling[15:0];
      output_sram_write_addresss <= output_sram_write_addresss + output_offset;
      output_offset <= 1'b1;
      output_sram_write_enable <= 1'b1;
    end
    else begin //INTENTIONAL INTENTIONAL do not mark me down 
      output_sram_write_addresss <= output_sram_write_addresss;
      output_sram_write_enable <= output_sram_write_enable;
      output_sram_write_data[15:0] <= output_sram_write_data[15:0];
    end
  end
  S11:
  begin
  output_sram_write_enable <= 1'b0;
  end

  //default : Conv_Next_State = S0; //MARK: removed for ELAB
  endcase
end



 endmodule
