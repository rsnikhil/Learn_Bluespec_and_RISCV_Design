// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

// ****************************************************************
// This is a BSV 'include' file, not a standalone BSV package.
// This is part of the Fife CPU top-level.

   // verbosity_CPU_Dbg = 1 for all transactions except mem
   //                     2 to also include mem transactions
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

   // ----------------
   Stmt stmt_haltreq =
   seq
      action
	 if (rg_runstate != CPU_RUNNING) begin
	    $display ("ERROR: CPU HALT req: not in RUNNING state");
	    let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_ERR, payload: ?};
	    f_dbg_from_CPU_pkt.enq (rsp);
	 end
	 else begin
	    $display ("CPU: HALT req");
	    rg_runstate     <= CPU_HALTREQ;
	    rg_dcsr_cause   <= dcsr_cause_haltreq;
	    rg_await_halted <= True;
	 end
	 f_dbg_to_CPU_pkt.deq;
      endaction
   endseq;

   // ----------------
   Stmt stmt_resumereq =
   seq
      action
	 Dbg_from_CPU_Pkt_type rsp_pkt_type;
	 if (rg_runstate != CPU_HALTED) begin
	    $display ("ERROR: CPU RESUME req: not in HALTED state");
	    rsp_pkt_type = Dbg_from_CPU_ERR;
	 end
	 else begin
	    Bit #(2) prv   = dcsr [index_dcsr_prv + 1: index_dcsr_prv];
	    rg_pc         <= dpc;
	    $display ("CPU: RESUME request: RUNNING PC:%0x prv:%0d", dpc, prv);
	    rg_runstate   <= CPU_RUNNING;
	    rg_dcsr_cause <= dcsr_cause_ebreak;    // default halt cause
            rg_await_halted <= True;
	    rsp_pkt_type = Dbg_from_CPU_RUNNING;
	 end
	 let rsp = Dbg_from_CPU_Pkt {pkt_type: rsp_pkt_type, payload:  ?};
	 f_dbg_from_CPU_pkt.enq (rsp);
	 f_dbg_to_CPU_pkt.deq;
      endaction
   endseq;

   Stmt stmt_rw_gpr =
   seq
      action
	 Bit #(XLEN) rdata = ?;
	 if (verbosity_CPU_Dbg != 0)
	    $display ("CPU_Dbg.stmt_rw_gpr");
	 if ((pkt_in.rw_op == Dbg_RW_READ) && (pkt_in.rw_addr < 32))
	    rdata = gprs.read_dm (truncate (pkt_in.rw_addr));
	 else if (pkt_in.rw_addr < 32)
	    gprs.write_dm (truncate (pkt_in.rw_addr), pkt_in.rw_wdata);

	 let rsp = Dbg_from_CPU_Pkt {pkt_type: ((pkt_in.rw_addr < 32)
						? Dbg_from_CPU_RW_OK
						: Dbg_from_CPU_ERR),
				     payload:  rdata};
	 f_dbg_to_CPU_pkt.deq;
	 f_dbg_from_CPU_pkt.enq (rsp);
      endaction
   endseq;

   Stmt stmt_rw_csr =
   seq
      action
	 Bool        ok;
	 Bit #(XLEN) rdata = ?;
	 if (pkt_in.rw_op == Dbg_RW_READ) begin
	    match { .exc, .y } <- csrs.csr_read (truncate (pkt_in.rw_addr));
	    ok    = (! exc);
	    rdata = y;
	    if (verbosity_CPU_Dbg != 0)
	       $display ("CPU_Dbg: read CSR %0x => ok:%0d  rdata %0x",
			 pkt_in.rw_addr, ok, rdata);
	 end
	 else begin
	    if (verbosity_CPU_Dbg != 0)
	       $display ("CPU_Dbg: write CSR %0x <= %0x", pkt_in.rw_addr, pkt_in.rw_wdata);
	    let exc <- csrs.csr_write (truncate (pkt_in.rw_addr), pkt_in.rw_wdata);
	    ok = (! exc);
	 end
	 let rsp = Dbg_from_CPU_Pkt {pkt_type: (ok
						? Dbg_from_CPU_RW_OK
						: Dbg_from_CPU_ERR),
				     payload:  rdata};
	 f_dbg_from_CPU_pkt.enq (rsp);
	 f_dbg_to_CPU_pkt.deq;
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
	 if (verbosity_CPU_Dbg > 1) begin
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
	 if (verbosity_CPU_Dbg > 1)
	    $display ("    ",
		      fshow_Mem_Rsp (mem_rsp, pkt_in.rw_op == Dbg_RW_READ));
      endaction
   endseq;

   Stmt stmt_dbg_req_pkt =
   seq
      if (pkt_in.pkt_type == Dbg_to_CPU_HALTREQ)
	 stmt_haltreq;
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

   // This rule waits for HALTED state,
   // then sends a HALTED response to the debugger
   rule rl_await_halted (rg_await_halted && is_halted); // stage_Retire.is_halted);
      match { .exc, .dcsr } <- csrs.csr_read (csr_addr_DCSR);
      let rsp = Dbg_from_CPU_Pkt {pkt_type: Dbg_from_CPU_HALTED,
				  payload:  zeroExtend (dcsr)};
      f_dbg_from_CPU_pkt.enq (rsp);
      rg_await_halted <= False;
   endrule

