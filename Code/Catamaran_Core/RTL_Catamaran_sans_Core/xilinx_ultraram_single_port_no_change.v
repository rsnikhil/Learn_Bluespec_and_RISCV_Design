
//  Xilinx UltraRAM Single Port No Change Mode.  This code implements
//  a parameterizable UltraRAM block in No Change mode. The behavior of this RAM is
//  when data is written, the output of RAM is unchanged. Only when write is
//  inactive data corresponding to the address is presented on the output port.
//
module xilinx_ultraram_single_port_no_change #(
  parameter AWIDTH  = 12,  // Address Width
  parameter NUM_COL = 9,   // Number of columns
  parameter CWIDTH  = 8,   // Column width (byte)
  parameter DWIDTH  = 72,  // Data Width, (CWIDTH * NUM_COL)
  parameter NBPIPE  = 3    // Number of pipeline Registers
 ) (
    input clk,                    // Clock
    input rst,                    // Reset
    input [NUM_COL-1:0] we,       // Write Enable
    input regce,                  // Output Register Enable
    input mem_en,                 // Memory Enable
    input [DWIDTH-1:0] din,       // Data Input
    input [AWIDTH-1:0] addr,      // Address Input
    output reg [DWIDTH-1:0] dout  // Data Output
   );

(* ram_style = "ultra" *) // (* cascade_height  = 2 *)
reg [DWIDTH-1:0] mem[(1<<AWIDTH)-1:0];        // Memory Declaration
reg [DWIDTH-1:0] memreg;
reg [DWIDTH-1:0] mem_pipe_reg[NBPIPE-1:0];    // Pipelines for memory
reg mem_en_pipe_reg[NBPIPE:0];                // Pipelines for memory enable

integer          i;

// RAM : Read has one latency, Write has one latency as well.
always @ (posedge clk)
begin
 if(mem_en)
  begin
  for(i = 0;i<NUM_COL;i=i+1)
	 if(we[i])
    mem[addr][i*CWIDTH +: CWIDTH] <= din[i*CWIDTH +: CWIDTH];
  end
end

always @ (posedge clk)
begin
 if(mem_en)
  if(~|we)
    memreg <= mem[addr];
end

// The enable of the RAM goes through a pipeline to produce a
// series of pipelined enable signals required to control the data
// pipeline.
always @ (posedge clk)
begin
mem_en_pipe_reg[0] <= mem_en;
 for (i=0; i<NBPIPE; i=i+1)
  mem_en_pipe_reg[i+1] <= mem_en_pipe_reg[i];
end

// RAM output data goes through a pipeline.
always @ (posedge clk)
begin
 if (mem_en_pipe_reg[0])
  mem_pipe_reg[0] <= memreg;
end

always @ (posedge clk)
begin
 for (i = 0; i < NBPIPE-1; i = i+1)
  if (mem_en_pipe_reg[i+1])
    mem_pipe_reg[i+1] <= mem_pipe_reg[i];
end

// Final output register gives user the option to add a reset and
// an additional enable signal just for the data ouptut
always @ (posedge clk)
begin
 if (rst)
  dout <= 0;
 else if (mem_en_pipe_reg[NBPIPE] && regce)
  dout <= mem_pipe_reg[NBPIPE-1];
end
endmodule

/*
// The following is an instantation template for
// xilinx_ultraram_single_port_no_change

   xilinx_ultraram_single_port_no_change # (
                                             .AWIDTH(AWIDTH),
                                             .DWIDTH(DWIDTH),
                                             .NBPIPE(NBPIPE)
                                            )
                      your_instance_name    (
                                             clk(clk),
                                             rst(rst),
                                             we(we),
                                             regce(regce),
                                             mem_en(mem_en),
                                             din(din),
                                             addr(addr),
                                             dout(dout)
                                            );
*/
