// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

// WARNING! WARNING! WARNING!
// This is just a placeholder file, needs to be fixed up (2024-09-11).

// ****************************************************************
// This is a BSV 'include' file, not a standalone BSV package.
// This is part of the Fife CPU top-level.

   Integer verbosity_CPU_Dbg = 0;

   // Requests from/Responses to remote debugger
   FIFOF #(Dbg_to_CPU_Pkt)   f_dbg_to_CPU_pkt   <- mkFIFOF;
   FIFOF #(Dbg_from_CPU_Pkt) f_dbg_from_CPU_pkt <- mkFIFOF;

   // Memory requests from/responses to remote debugger
   FIFOF #(Mem_Req) f_dbg_to_mem_req   <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_dbg_from_mem_rsp <- mkFIFOF;

   Reg #(Bool)        rg_ok   <- mkRegU;
   Reg #(Bit #(XLEN)) rg_data <- mkRegU;
   Reg #(Bool)        rg_await_halted <- mkReg (False);

   let pkt_in = f_dbg_to_CPU_pkt.first;

   Stmt stmt_HALTREQ =
   seq
      if (verbosity_CPU_Dbg != 0)
	 $display ("CPU_Dbg.stmt_HALTREQ");
      action
	 // DELETE let ok <- stage_Retire.haltreq;
	 let ok = True;
	 rg_ok <= ok;
      endaction
      if (! rg_ok)
	 action
	    let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_ERR,
					payload:  ?};
	    f_dbg_from_CPU_pkt.enq (rsp);
	 endaction
      else
         rg_await_halted <= True;
      f_dbg_to_CPU_pkt.deq;
   endseq;

   Stmt stmt_resumereq =
   seq
      if (verbosity_CPU_Dbg != 0)
	 $display ("CPU_Dbg.stmt_resumereq");
      action
	 // DELETE let ok <- stage_Retire.resumereq;
	 let ok = True;
	 rg_ok <= ok;
      endaction
      if (! rg_ok)
	 action
	    let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_ERR,
					payload:  ?};
	    f_dbg_from_CPU_pkt.enq (rsp);
	 endaction
      else
	 seq
	    // DELETE await (stage_Retire.is_running);
	    action
	       let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_RUNNING,
					   payload:  ?};
	       f_dbg_from_CPU_pkt.enq (rsp);
               rg_await_halted <= True;
	    endaction
	 endseq
      f_dbg_to_CPU_pkt.deq;
   endseq;

   Stmt stmt_rw_gpr =
   seq
      if (verbosity_CPU_Dbg != 0)
	 $display ("CPU_Dbg.stmt_rw_gpr");
      if ((pkt_in.rw_op == Dbg_RW_READ) && (pkt_in.rw_addr < 32))
	 rg_data <= 0; // DELETE stage_RR_RW.gpr_read (truncate (pkt_in.rw_addr));
      else if (pkt_in.rw_addr < 32)
	 noAction; // DELETE stage_RR_RW.gpr_write (truncate (pkt_in.rw_addr), pkt_in.rw_wdata);
      action
	 let rsp = Dbg_from_CPU_Pkt {pkt_type: ((pkt_in.rw_addr < 32)
						? Dbg_from_CPU_RW_OK
						: Dbg_from_CPU_ERR),
				     payload:  rg_data};
	 f_dbg_to_CPU_pkt.deq;
	 f_dbg_from_CPU_pkt.enq (rsp);
      endaction
   endseq;

   Stmt stmt_rw_csr =
   seq
      if (verbosity_CPU_Dbg != 0)
	 $display ("CPU_Dbg.stmt_rw_csr");
      if (pkt_in.rw_op == Dbg_RW_READ)
	 action
	    // DELETE match { .exc, .y } <- stage_Retire.csr_read (truncate (pkt_in.rw_addr));
	    let exc = False;
	    let y   = 0;
	    rg_ok   <= exc;
	    rg_data <= y;
	 endaction
      else
	 action
	    // DELETE let exc <- stage_Retire.csr_write (truncate (pkt_in.rw_addr), pkt_in.rw_wdata);
	    let exc = False;
	    rg_ok   <= (! exc);
	    rg_data <= pkt_in.rw_wdata;
	 endaction
      action
	 let rsp = Dbg_from_CPU_Pkt {pkt_type: (rg_ok
						? Dbg_from_CPU_RW_OK
						: Dbg_from_CPU_ERR),
				     payload:  rg_data};
	 f_dbg_to_CPU_pkt.deq;
	 f_dbg_from_CPU_pkt.enq (rsp);
      endaction
   endseq;

   Stmt stmt_rw_mem =
   seq
      action
	 let mem_req = Mem_Req {req_type: ((pkt_in.rw_op == Dbg_RW_READ)
					   ? funct5_LOAD
					   : funct5_STORE),
				size: case (pkt_in.rw_size)
					 Dbg_MEM_1B: MEM_1B;
					 Dbg_MEM_2B: MEM_2B;
					 Dbg_MEM_4B: MEM_4B;
					 Dbg_MEM_8B: MEM_8B;
				      endcase,
				addr: zeroExtend (pkt_in.rw_addr),
				data: zeroExtend (pkt_in.rw_wdata),
				inum: 0,
				pc: 0,
				instr: 0};
	 f_dbg_to_mem_req.enq (mem_req);
	 if (verbosity_CPU_Dbg != 0) begin
	    $display ("CPU_Dbg.stmt_rw_mem");
	    $display ("    ", fshow_Mem_Req (mem_req));
	 end
      endaction
      action
	 let mem_rsp <- pop_o (to_FIFOF_O (f_dbg_from_mem_rsp));
	 let dbg_rsp
	 = Dbg_from_CPU_Pkt {pkt_type: ((mem_rsp.rsp_type == MEM_RSP_OK)
					? Dbg_from_CPU_RW_OK
					: Dbg_from_CPU_ERR),
			     payload: truncate (mem_rsp.data)};
	 f_dbg_to_CPU_pkt.deq;
	 f_dbg_from_CPU_pkt.enq (dbg_rsp);
	 if (verbosity_CPU_Dbg != 0)
	    $display ("    ",
		      fshow_Mem_Rsp (mem_rsp, pkt_in.rw_op == Dbg_RW_READ));
      endaction
   endseq;

   Stmt stmt_dbg_req_pkt =
   seq
      if (pkt_in.pkt_type == Dbg_to_CPU_HALTREQ)
	 stmt_HALTREQ;
      else if (pkt_in.pkt_type == Dbg_to_CPU_RESUMEREQ)
	 stmt_resumereq;
      else if (pkt_in.pkt_type == Dbg_to_CPU_RW)
	 if (pkt_in.rw_target == Dbg_RW_GPR)
	    stmt_rw_gpr;
	 else if (pkt_in.rw_target == Dbg_RW_CSR)
	    stmt_rw_csr;
	 else if (pkt_in.rw_target == Dbg_RW_MEM)
	    stmt_rw_mem;
	 else
	    action
	       $display ("ERROR: unrecognized debugger request: ",
			 fshow (pkt_in));
	       $finish (1);
	    endaction
   endseq;

   mkAutoFSM (
      seq
	 while (True)
	    stmt_dbg_req_pkt;
      endseq);

   Bool is_halted = False;
   rule rl_await_halted (rg_await_halted && is_halted); // stage_Retire.is_halted);
      // DELETE match { .exc, .dcsr } <- stage_Retire.csr_read (csr_addr_DCSR);
      Bool      exc  = False;
      Bit #(32) dcsr = 0;
      let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_HALTED,
				  payload:  zeroExtend (dcsr)};
      f_dbg_from_CPU_pkt.enq (rsp);
      rg_await_halted <= False;
   endrule

