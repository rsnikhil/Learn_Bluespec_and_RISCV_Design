// Copyright (c) 2024 Bluespec, Inc. All Rights Reserved.

package Adapter_ReqRsp_AXI4;

// ================================================================
// Adapter from read/write CPU requests/responses to AXI4 bus master.

// On the client-side:
// - Data is always aligned to LSBs (like CPU registers)

// On the AXI4 side:
// - The bus master can be used with 32b or 64b buses.  This adapter
//     manages byte-lane alignment, number of beats in a burst,
//     write-strobes, etc.

// Successive read requests and write requests can be pipelined, but
// this module avoids interleaving read and write requests, i.e., it
// launches a read request only when no write-responses from the AXI4
// fabric are pending, and launches a write request only when no read
// reponses are pending.

// ================================================================

export  mkAdapter_ReqRsp_AXI4;

// ================================================================
// BSV lib imports

import FIFOF :: *;

// ----------------
// BSV additional libs

import Cur_Cycle  :: *;
import GetPut_Aux :: *;
import Semi_FIFOF :: *;

// ================================================================
// Project imports

import Instr_Bits  :: *;    // for funct5_LOAD/STORE
import Mem_Req_Rsp :: *;

import AXI4_Types  :: *;
import Fabric_Defs :: *;

// ================================================================
// Misc. help functions

// ----------------------------------------------------------------
// Convert size code into AXI4_Size code (number of bytes in a beat).
// It just so happens that our coding coincides with AXI4's coding.

function AXI4_Size  fv_size_code_to_AXI4_Size (Bit #(2) size_code);
   return { 1'b0, size_code };
endfunction

// ----------------------------------------------------------------
// Convert a 64-bit Address to an AXI4 Fabric Address
// For FABRIC64 this does nothing.
// For FABRIC32 it discards the upper 32 bits.

function Fabric_Addr fv_Addr_to_Fabric_Addr (Bit #(64) addr);
   return truncate (addr);
endfunction

// ================================================================
// MODULE IMPLEMENTATION
// Non-synthesizable (polymorphic in num_clients_t)

module mkAdapter_ReqRsp_AXI4 #(String instance_name,
			       Integer verbosity,
			       FIFOF_O #(Mem_Req) fo_mem_reqs,
			       FIFOF_I #(Mem_Rsp) fi_mem_rsps)
   (AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User));

   // Limit the number of reads/writes outstanding to 15
   // TODO: change these to concurrent up/down counters?
   Reg #(Bit #(4)) rg_rd_rsps_pending <- mkReg (0);
   Reg #(Bit #(4)) rg_wr_rsps_pending <- mkReg (0);

   // AXI4 fabric request/response
   AXI4_Master_Xactor_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User)
      master_xactor <- mkAXI4_Master_Xactor;

   // ****************************************************************
   // BEHAVIOR: read requests

   // ----------------
   // Control info for read-responses

   // TODO: change mkFIFOF to mkSizedFIFOF (allowing multiple outstanding reads)
   // many reads can be outstanding
   FIFOF #(Tuple3 #(Mem_Req,
		    AXI4_Size,
		    AXI4_Len))                   // arlen (= # of beats - 1)
         f_rsp_control <- mkSizedFIFOF (16);

   match {.req, .axsize, .axlen} = f_rsp_control.first;
   Bit #(3) addr_lsbs = req.addr [2:0];

   // ----------------
   // Read requests

   Reg #(AXI4_Len) rg_rd_beat <- mkReg (0);    // Read data beat counter

   rule rl_rd_req ((fo_mem_reqs.first.req_type == funct5_LOAD)
		   && (rg_rd_rsps_pending < '1)
		   && (rg_wr_rsps_pending == 0));

      let req <- pop_o (fo_mem_reqs);

      Fabric_Addr araddr = fv_Addr_to_Fabric_Addr (req.addr);
      AXI4_Size   arsize = fv_size_code_to_AXI4_Size (pack (req.size));

      // Note: AXI4 codes a burst length of 'n' as 'n-1'.
      // Only size D in 32-bit fabrics needs 2 beats.
      AXI4_Len  arlen = 0;    // 1 beat
      if ((valueOf (Wd_Data) == 32) && (pack (req.size) == 2'b11)) begin
	 arsize = axsize_4;
	 arlen  = 1;    // 2 beats
      end

      if (verbosity >= 1) begin
	 $display ("%0d: %s.rl_rd_req", cur_cycle, instance_name);
	 $display ("    AXI4_Rd_Addr {araddr %0h arlen %d ",
		   araddr,  arlen, fshow_AXI4_Size (arsize), "}");
      end

      let mem_req_rd_addr = AXI4_Rd_Addr {arid:     fabric_default_id,
					  araddr:   araddr,
					  arlen:    arlen,
					  arsize:   arsize,
					  arburst:  fabric_default_burst,
					  arlock:   fabric_default_lock,
					  arcache:  fabric_default_arcache,
					  arprot:   fabric_default_prot,
					  arqos:    fabric_default_qos,
					  arregion: fabric_default_region,
					  aruser:   fabric_default_user};
      master_xactor.i_rd_addr.enq (mem_req_rd_addr);

      f_rsp_control.enq (tuple3 (req, arsize, arlen));
      rg_rd_beat         <= 0;
      rg_rd_rsps_pending <= rg_rd_rsps_pending + 1;
   endrule: rl_rd_req

   // ----------------
   // Read responses

   Reg #(Bit #(64)) rg_rd_data_buf <- mkRegU;    // accumulate data across beats

   rule rl_rd_data (rg_rd_beat <= axlen);
      // Get read-data response from AXI4
      let       rd_data <- pop_o (master_xactor.o_rd_data);
      Bool      ok      = (rd_data.rresp == axi4_resp_okay);

      if (! ok) begin
	 if (verbosity >= 1) begin
	    $display ("%0d: ERROR: %m.rl_rd_data (%s)", cur_cycle, instance_name);
	    $display ("    AXI4 error response addr %0h arsize %0h arlen %0h beat %0d",
		      req.addr, axsize, axlen, rg_rd_beat);
	    $display ("    ", fshow (rd_data));
	 end
      end

      // Accumulate beats into word64 and rg_rd_data
      Bit #(64) word64 = rg_rd_data_buf;
      if (rg_rd_beat == 0)
	 word64 = zeroExtend (rd_data.rdata);
      else if (rg_rd_beat == 1)
	 // 2nd beat is only possible in 32-bit fabrics
	 word64 = { rd_data.rdata [31:0], word64 [31:0] };
      else begin
	 $display ("%0d: INTERNAL ERROR: %m.rl_rd_data (%s)", cur_cycle, instance_name);
	 $display ("    Unexpected beat number %0d (can only be 0 or 1)", rg_rd_beat);
	 $finish (1);
      end
      rg_rd_data_buf <= word64;

      // If last beat, deliver to CPU-side client
      Bool last_beat = rg_rd_beat == axlen;
      if (last_beat) begin
	 // Adjust alignment of B,H,W data
	 // addr [1:0] is non-zero only for B, H, W (so, single-beat, so data is in [31:0])
	 if (axsize != axsize_8) begin
	    Bit #(6) shamt_bits = ?;
	    if (valueOf (Wd_Data) == 32)
	       shamt_bits = { 1'b0, addr_lsbs [1:0], 3'b000 };
	    else if (valueOf (Wd_Data) == 64)
	       shamt_bits = { addr_lsbs [2:0], 3'b000 };
	    else begin
	       $display ("%0d: INTERNAL ERROR: %m.rl_rd_data (%s)", cur_cycle, instance_name);
	       $display ("    Unsupported fabric width %0d", valueOf (Wd_Data));
	       $finish (1);
	    end
	    word64 = (word64 >> shamt_bits);
	 end
	 // Send response to CPU
	 let rsp = Mem_Rsp {rsp_type: (ok ? MEM_RSP_OK : MEM_RSP_ERR),
			    data:     word64,
			    req_type: req.req_type,
			    size:     req.size,
			    addr:     req.addr,
			    inum:     req.inum,      // debugging only
			    pc:       req.pc,        // debugging only
			    instr:    req.instr};    // debugging only
	 fi_mem_rsps.enq (rsp);

	 f_rsp_control.deq;
	 rg_rd_rsps_pending <= rg_rd_rsps_pending - 1;

	 // Reset beat counter for next read transaction
	 rg_rd_beat <= 0;
      end
      else
	 rg_rd_beat <= rg_rd_beat + 1;

      if (verbosity >= 1) begin
	 $display ("%0d: %s.rl_rd_data: ", cur_cycle, instance_name);
	 $display ("    beat %0d (last %0d) data %0h", rg_rd_beat, last_beat, word64);
      end
   endrule: rl_rd_data

   // ****************************************************************
   // BEHAVIOR: write requests

   // Regs holding state during write-data burst
   Reg #(Bit #(8))   rg_awlen       <- mkReg (0);
   Reg #(Bit #(64))  rg_wr_data_buf <- mkRegU;
   Reg #(Bit #(8))   rg_wr_strb_buf <- mkRegU;

   // Beat counter: There are pending beats when rg_wr_beat <= rg_awlen
   Reg #(Bit #(8))  rg_wr_beat <- mkReg (1);

   rule rl_wr_req ((fo_mem_reqs.first.req_type == funct5_STORE)
		   && (rg_wr_beat > rg_awlen)
		   && (rg_rd_rsps_pending == 0)
		   && (rg_wr_rsps_pending < '1));

      let req = fo_mem_reqs.first;    // Don't deq it until data beats sent

      // Data is in lsbs
      Bit #(64) word64 = req.data;
      Bit #(8)  strb   = case (pack (req.size))
			    2'b00: 8'h_01;
			    2'b01: 8'h_03;
			    2'b10: 8'h_0F;
			    2'b11: 8'h_FF;
			 endcase;

      Fabric_Addr awaddr = fv_Addr_to_Fabric_Addr (req.addr);
      AXI4_Size   awsize = fv_size_code_to_AXI4_Size (pack (req.size));
      AXI4_Len    awlen  = 0;    // 1 beat

      // Adjustments for AXI4 data bus widths of 32-bit and 64-bit
      if (awsize == axsize_8) begin
	 if (valueOf (Wd_Data) == 32) begin
	    awsize = axsize_4;
	    awlen  = 1;     // 2 beats
	 end
      end
      else begin
	 if (valueOf (Wd_Data) == 32) begin
	    word64 = (word64 << ({ req.addr [1:0], 3'b0 }));
	    strb   = (strb   << req.addr [1:0]);
	 end
	 else if (valueOf (Wd_Data) == 64) begin
	    word64 = (word64 << ({ req.addr [2:0], 3'b0 }));
	    strb   = (strb   << req.addr [2:0]);
	 end
	 else begin
	    $display ("%0d: ERROR: %m.rl_wr_data (%s)", cur_cycle, instance_name);
	    $display ("    Unsupported fabric width %0d", valueOf (Wd_Data));
	    $finish (1);
	 end
      end
      rg_awlen        <= awlen;
      rg_wr_data_buf  <= word64;
      rg_wr_strb_buf  <= strb;
      rg_wr_beat      <= 0;

      // AXI4 Write-Address channel
      let mem_req_wr_addr = AXI4_Wr_Addr {awid:     fabric_default_id,
					  awaddr:   awaddr,
					  awlen:    awlen,
					  awsize:   awsize,
					  awburst:  fabric_default_burst,
					  awlock:   fabric_default_lock,
					  awcache:  fabric_default_awcache,
					  awprot:   fabric_default_prot,
					  awqos:    fabric_default_qos,
					  awregion: fabric_default_region,
					  awuser:   fabric_default_user};
      master_xactor.i_wr_addr.enq (mem_req_wr_addr);

      f_rsp_control.enq (tuple3 (req, awsize, awlen));
      rg_wr_rsps_pending <= rg_wr_rsps_pending + 1;

      // Debugging
      if (verbosity >= 1) begin
	 $display ("%0d: %s.rl_wr_req", cur_cycle, instance_name);
	 $display ("    AXI4_Wr_Addr{awaddr %0h awlen %0d ",
		   awaddr, awlen,
		   fshow_AXI4_Size (awsize),
		   " incr}");
      end
   endrule: rl_wr_req

   // ----------------
   // Write data (multiple beats if fabric data width < 64b)

   rule rl_wr_data (rg_wr_beat <= rg_awlen);
      Bool last = (rg_wr_beat == rg_awlen);
      if (last)
	 fo_mem_reqs.deq;
      rg_wr_beat <= rg_wr_beat + 1;

      // Send AXI write-data
      Bit #(Wd_Data)             wdata = truncate (rg_wr_data_buf);
      Bit #(TDiv #(Wd_Data, 8))  wstrb = truncate (rg_wr_strb_buf);
      let wr_data = AXI4_Wr_Data {wdata:  wdata,
				  wstrb:  wstrb,
				  wlast:  last,
				  wuser:  fabric_default_user};
      master_xactor.i_wr_data.enq (wr_data);

      // Prepare for next beat
      rg_wr_data_buf <= (rg_wr_data_buf >> valueOf (Wd_Data));
      rg_wr_strb_buf <= (rg_wr_strb_buf >> valueOf (TDiv #(Wd_Data, 8)));

      if (verbosity >= 1) begin
	 $display ("%0d: %s.rl_wr_data", cur_cycle, instance_name);
	 $display ("    beat %0d/%0d", rg_wr_beat, rg_awlen);
	 $display ("    ", fshow (wr_data));
      end
   endrule: rl_wr_data

   // ----------------
   // Write responses

   rule rl_wr_rsp;
      let wr_resp <- pop_o (master_xactor.o_wr_resp);

      if (rg_wr_rsps_pending == 0) begin
	 $display ("%0d: %m.rl_wr_rsp (%s):", cur_cycle, instance_name);
	 $display ("    ERROR write-response when not expecting any");
	 $display ("    ", fshow (wr_resp));
	 $finish (1);
      end
      else begin
	 rg_wr_rsps_pending <= rg_wr_rsps_pending - 1;
	 Bool ok = (wr_resp.bresp == axi4_resp_okay);
	 if (! ok) begin
	    ok = False;
	    $display ("%0d: %m.rl_wr_rsp (%s)", cur_cycle, instance_name);
	    $display ("    ERROR: AXI4 write-response error");
	    $display ("    ", fshow (wr_resp));
	 end
	 else if (verbosity >= 1) begin
	    $display ("%0d: %s.rl_wr_rsp: pending=%0d, ",
		      cur_cycle, instance_name, rg_wr_rsps_pending, fshow (wr_resp));
	 end

	 let rsp = Mem_Rsp {rsp_type: (ok ? MEM_RSP_OK : MEM_RSP_ERR),
			    data:     0,
			    req_type: req.req_type,
			    size:     req.size,
			    addr:     req.addr,
			    inum:     req.inum,      // debugging only
			    pc:       req.pc,        // debugging only
			    instr:    req.instr};    // debugging only
	 fi_mem_rsps.enq (rsp);
	 f_rsp_control.deq;
      end
   endrule: rl_wr_rsp

   // ================================================================
   // INTERFACE

   return master_xactor.axi_side;
endmodule

// ================================================================

endpackage
