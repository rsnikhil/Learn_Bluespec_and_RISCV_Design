import FIFOF ::*;
import Semi_FIFOF::*;
import AXI4_Types::*;
import AXI4_Lite_Types::*;

// This part based on code written in the University of Cambridge Computer Laboratory.

typeclass ToUnguarded #(type a);
   module mkUnguarded #(a x)(a);
endtypeclass

instance ToUnguarded #(FIFOF_I #(a))
   provisos (Bits#(a, __));
   module mkUnguarded #(FIFOF_I #(a) ifc)(FIFOF_I #(a));
      let enqWire <- mkRWire;
      rule warnDoEnq (isValid(enqWire.wget) && !ifc.notFull);
	 $display("WARNING: enqing into an already full FIFOF_I");
	 $finish(0);
      endrule
      rule doEnq (isValid(enqWire.wget));
	 ifc.enq(enqWire.wget.Valid);
      endrule
      return interface FIFOF_I;
		method notFull = ifc.notFull;
		method enq     = enqWire.wset;
	     endinterface;
   endmodule
endinstance

instance ToUnguarded #(FIFOF_O #(a))
   provisos (Bits#(a, _));
   module mkUnguarded#(FIFOF_O #(a) ifc)(FIFOF_O#(a));
      let firstWire <- mkDWire(unpack(0));
      let deqWire   <- mkPulseWire;
      rule setFirst; firstWire <= ifc.first; endrule
      rule warnDoDeq (deqWire && !ifc.notEmpty);
	 $display("WARNING: deqing from empty FIFOF_O");
	 $finish(0);
      endrule
      rule doDeq (deqWire && ifc.notEmpty);
	 ifc.deq;
      endrule
      return interface FIFOF_O;
		method notEmpty = ifc.notEmpty;
		method first    = firstWire;
		method deq      = deqWire.send;
	     endinterface;
   endmodule
endinstance

// --------------------------------------

module mkAXI4_Master_Xactor_3 #(aw_t aw, w_t w, b_t b, ar_t ar, r_t r)
   (AXI4_Master_IFC #(wd_id, wd_addr, wd_data,    wd_user))
   provisos (To_FIFOF_IO #(aw_t, AXI4_Wr_Addr #(wd_id,   wd_addr, wd_user)),
	     To_FIFOF_IO #(w_t,  AXI4_Wr_Data #(wd_data, wd_user)),
	     To_FIFOF_IO #(b_t,  AXI4_Wr_Resp #(wd_id,   wd_user)),
	     To_FIFOF_IO #(ar_t, AXI4_Rd_Addr #(wd_id,   wd_addr, wd_user)),
	     To_FIFOF_IO #(r_t,  AXI4_Rd_Data #(wd_id,   wd_data, wd_user)));

   FIFOF_O #(AXI4_Wr_Addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkUnguarded (to_FIFOF_O (aw));
   FIFOF_O #(AXI4_Wr_Data #(wd_data, wd_user))         f_wr_data <- mkUnguarded (to_FIFOF_O (w));
   FIFOF_I #(AXI4_Wr_Resp #(wd_id, wd_user))           f_wr_resp <- mkUnguarded (to_FIFOF_I (b));

   FIFOF_O #(AXI4_Rd_Addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkUnguarded (to_FIFOF_O (ar));
   FIFOF_I #(AXI4_Rd_Data #(wd_id, wd_data, wd_user))  f_rd_data <- mkUnguarded (to_FIFOF_I (r));

   // ----------------------------------------------------------------
   // INTERFACE

   return interface AXI4_Master_IFC;
	     // Wr Addr channel
	     method Bool            m_awvalid  = f_wr_addr.notEmpty;
	     method Bit #(wd_id)    m_awid     = f_wr_addr.first.awid;
	     method Bit #(wd_addr)  m_awaddr   = f_wr_addr.first.awaddr;
	     method Bit #(8)        m_awlen    = f_wr_addr.first.awlen;
	     method AXI4_Size       m_awsize   = f_wr_addr.first.awsize;
	     method Bit #(2)        m_awburst  = f_wr_addr.first.awburst;
	     method Bit #(1)        m_awlock   = f_wr_addr.first.awlock;
	     method Bit #(4)        m_awcache  = f_wr_addr.first.awcache;
	     method Bit #(3)        m_awprot   = f_wr_addr.first.awprot;
	     method Bit #(4)        m_awqos    = f_wr_addr.first.awqos;
	     method Bit #(4)        m_awregion = f_wr_addr.first.awregion;
	     method Bit #(wd_user)  m_awuser   = f_wr_addr.first.awuser;
	     method Action m_awready (Bool awready);
		if (f_wr_addr.notEmpty && awready) f_wr_addr.deq;
	     endmethod

		// Wr Data channel
	     method Bool                       m_wvalid = f_wr_data.notEmpty;
	     method Bit #(wd_data)             m_wdata  = f_wr_data.first.wdata;
	     method Bit #(TDiv #(wd_data, 8))  m_wstrb  = f_wr_data.first.wstrb;
	     method Bool                       m_wlast  = f_wr_data.first.wlast;
	     method Bit #(wd_user)             m_wuser  = f_wr_data.first.wuser;
	     method Action m_wready (Bool wready);
		if (f_wr_data.notEmpty && wready) f_wr_data.deq;
	     endmethod

		// Wr Response channel
	     method Action m_bvalid (Bool           bvalid,
				     Bit #(wd_id)   bid,
				     Bit #(2)       bresp,
				     Bit #(wd_user) buser);
		if (bvalid && f_wr_resp.notFull)
		   f_wr_resp.enq (AXI4_Wr_Resp {bid:   bid,
						bresp: bresp,
						buser: buser});
	     endmethod

	     method Bool m_bready;
		return f_wr_resp.notFull;
	     endmethod

		// Rd Addr channel
	     method Bool            m_arvalid  = f_rd_addr.notEmpty;
	     method Bit #(wd_id)    m_arid     = f_rd_addr.first.arid;
	     method Bit #(wd_addr)  m_araddr   = f_rd_addr.first.araddr;
	     method Bit #(8)        m_arlen    = f_rd_addr.first.arlen;
	     method AXI4_Size       m_arsize   = f_rd_addr.first.arsize;
	     method Bit #(2)        m_arburst  = f_rd_addr.first.arburst;
	     method Bit #(1)        m_arlock   = f_rd_addr.first.arlock;
	     method Bit #(4)        m_arcache  = f_rd_addr.first.arcache;
	     method Bit #(3)        m_arprot   = f_rd_addr.first.arprot;
	     method Bit #(4)        m_arqos    = f_rd_addr.first.arqos;
	     method Bit #(4)        m_arregion = f_rd_addr.first.arregion;
	     method Bit #(wd_user)  m_aruser   = f_rd_addr.first.aruser;

	     method Action m_arready (Bool arready);
		if (f_rd_addr.notEmpty && arready) f_rd_addr.deq;
	     endmethod

		// Rd Data channel
	     method Action m_rvalid (Bool           rvalid,    // in
				     Bit #(wd_id)   rid,       // in
				     Bit #(wd_data) rdata,     // in
				     Bit #(2)       rresp,     // in
				     Bool           rlast,     // in
				     Bit #(wd_user) ruser);    // in
		if (rvalid && f_rd_data.notFull)
		   f_rd_data.enq (AXI4_Rd_Data {rid:   rid,
						rdata: rdata,
						rresp: rresp,
						rlast: rlast,
						ruser: ruser});
	     endmethod

	     method Bool m_rready;
		return f_rd_data.notFull;
	     endmethod

	  endinterface;
endmodule: mkAXI4_Master_Xactor_3

module mkAXI4_Slave_Xactor_3 #(aw_t aw, w_t w, b_t b, ar_t ar, r_t r)
   (AXI4_Slave_IFC #(wd_id, wd_addr, wd_data, wd_user))
   provisos (To_FIFOF_IO #(aw_t, AXI4_Wr_Addr #(wd_id,   wd_addr, wd_user)),
	     To_FIFOF_IO #(w_t,  AXI4_Wr_Data #(wd_data, wd_user)),
	     To_FIFOF_IO #(b_t,  AXI4_Wr_Resp #(wd_id,   wd_user)),
	     To_FIFOF_IO #(ar_t, AXI4_Rd_Addr #(wd_id,   wd_addr, wd_user)),
	     To_FIFOF_IO #(r_t,  AXI4_Rd_Data #(wd_id,   wd_data, wd_user)));

   FIFOF_I #(AXI4_Wr_Addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkUnguarded (to_FIFOF_I (aw));
   FIFOF_I #(AXI4_Wr_Data #(wd_data, wd_user))         f_wr_data <- mkUnguarded (to_FIFOF_I (w));
   FIFOF_O #(AXI4_Wr_Resp #(wd_id, wd_user))           f_wr_resp <- mkUnguarded (to_FIFOF_O (b));

   FIFOF_I #(AXI4_Rd_Addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkUnguarded (to_FIFOF_I (ar));
   FIFOF_O #(AXI4_Rd_Data #(wd_id, wd_data, wd_user))  f_rd_data <- mkUnguarded (to_FIFOF_O (r));

   // ----------------------------------------------------------------
   // INTERFACE

   return interface AXI4_Slave_IFC;
			   // Wr Addr channel
			   method Action m_awvalid (Bool            awvalid,
						    Bit #(wd_id)    awid,
						    Bit #(wd_addr)  awaddr,
						    Bit #(8)        awlen,
						    AXI4_Size       awsize,
						    Bit #(2)        awburst,
						    Bit #(1)        awlock,
						    Bit #(4)        awcache,
						    Bit #(3)        awprot,
						    Bit #(4)        awqos,
						    Bit #(4)        awregion,
						    Bit #(wd_user)  awuser);
			      if (awvalid && f_wr_addr.notFull)
				 f_wr_addr.enq (AXI4_Wr_Addr {awid:     awid,
							      awaddr:   awaddr,
							      awlen:    awlen,
							      awsize:   awsize,
							      awburst:  awburst,
							      awlock:   awlock,
							      awcache:  awcache,
							      awprot:   awprot,
							      awqos:    awqos,
							      awregion: awregion,
							      awuser:   awuser});
			   endmethod

			   method Bool m_awready;
			      return f_wr_addr.notFull;
			   endmethod

			   // Wr Data channel
			   method Action m_wvalid (Bool                       wvalid,
						   Bit #(wd_data)             wdata,
						   Bit #(TDiv #(wd_data, 8))  wstrb,
						   Bool                       wlast,
						   Bit #(wd_user)             wuser);
			      if (wvalid && f_wr_data.notFull)
				 f_wr_data.enq (AXI4_Wr_Data {wdata: wdata,
							      wstrb: wstrb,
							      wlast: wlast,
							      wuser: wuser});
			   endmethod

			   method Bool m_wready;
			      return f_wr_data.notFull;
			   endmethod

			   // Wr Response channel
			   method Bool           m_bvalid = f_wr_resp.notEmpty;
			   method Bit #(wd_id)   m_bid    = f_wr_resp.first.bid;
			   method Bit #(2)       m_bresp  = f_wr_resp.first.bresp;
			   method Bit #(wd_user) m_buser  = f_wr_resp.first.buser;
			   method Action m_bready (Bool bready);
			      if (bready && f_wr_resp.notEmpty)
				 f_wr_resp.deq;
			   endmethod

			   // Rd Addr channel
			   method Action m_arvalid (Bool            arvalid,
						    Bit #(wd_id)    arid,
						    Bit #(wd_addr)  araddr,
						    Bit #(8)        arlen,
						    AXI4_Size       arsize,
						    Bit #(2)        arburst,
						    Bit #(1)        arlock,
						    Bit #(4)        arcache,
						    Bit #(3)        arprot,
						    Bit #(4)        arqos,
						    Bit #(4)        arregion,
						    Bit #(wd_user)  aruser);
			      if (arvalid && f_rd_addr.notFull)
				 f_rd_addr.enq (AXI4_Rd_Addr {arid:     arid,
							      araddr:   araddr,
							      arlen:    arlen,
							      arsize:   arsize,
							      arburst:  arburst,
							      arlock:   arlock,
							      arcache:  arcache,
							      arprot:   arprot,
							      arqos:    arqos,
							      arregion: arregion,
							      aruser:   aruser});
			   endmethod

			   method Bool m_arready;
			      return f_rd_addr.notFull;
			   endmethod

			   // Rd Data channel
			   method Bool           m_rvalid = f_rd_data.notEmpty;
			   method Bit #(wd_id)   m_rid    = f_rd_data.first.rid;
			   method Bit #(wd_data) m_rdata  = f_rd_data.first.rdata;
			   method Bit #(2)       m_rresp  = f_rd_data.first.rresp;
			   method Bool           m_rlast  = f_rd_data.first.rlast;
			   method Bit #(wd_user) m_ruser  = f_rd_data.first.ruser;
			   method Action m_rready (Bool rready);
			      if (rready && f_rd_data.notEmpty)
				 f_rd_data.deq;
			   endmethod
			endinterface;
endmodule: mkAXI4_Slave_Xactor_3

// --------------------------------------

module mkAXI4_Lite_Master_Xactor_3 #(aw_t aw, w_t w, b_t b, ar_t ar, r_t r)
   (AXI4_Lite_Master_IFC #(wd_addr, wd_data,    wd_user))
   provisos (To_FIFOF_IO #(aw_t, AXI4_Lite_Wr_Addr #(wd_addr, wd_user)),
	     To_FIFOF_IO #(w_t,  AXI4_Lite_Wr_Data #(wd_data)),
	     To_FIFOF_IO #(b_t,  AXI4_Lite_Wr_Resp #(wd_user)),
	     To_FIFOF_IO #(ar_t, AXI4_Lite_Rd_Addr #(wd_addr, wd_user)),
	     To_FIFOF_IO #(r_t,  AXI4_Lite_Rd_Data #(wd_data, wd_user)));

   FIFOF_O #(AXI4_Lite_Wr_Addr #(wd_addr, wd_user))  f_wr_addr <- mkUnguarded (to_FIFOF_O (aw));
   FIFOF_O #(AXI4_Lite_Wr_Data #(wd_data))         f_wr_data <- mkUnguarded (to_FIFOF_O (w));
   FIFOF_I #(AXI4_Lite_Wr_Resp #(wd_user))           f_wr_resp <- mkUnguarded (to_FIFOF_I (b));

   FIFOF_O #(AXI4_Lite_Rd_Addr #(wd_addr, wd_user))  f_rd_addr <- mkUnguarded (to_FIFOF_O (ar));
   FIFOF_I #(AXI4_Lite_Rd_Data #(wd_data, wd_user))  f_rd_data <- mkUnguarded (to_FIFOF_I (r));

   // ----------------------------------------------------------------
   // INTERFACE

   return interface AXI4_Lite_Master_IFC;
	     // Wr Addr channel
	     method Bool           m_awvalid = f_wr_addr.notEmpty;
	     method Bit #(wd_addr) m_awaddr  = f_wr_addr.first.awaddr;
	     method Bit #(3)       m_awprot  = f_wr_addr.first.awprot;
	     method Bit #(wd_user) m_awuser  = f_wr_addr.first.awuser;
	     method Action m_awready (Bool awready);
		if (f_wr_addr.notEmpty && awready) f_wr_addr.deq;
	     endmethod

	     // Wr Data channel
	     method Bool                       m_wvalid = f_wr_data.notEmpty;
	     method Bit #(wd_data)             m_wdata  = f_wr_data.first.wdata;
	     method Bit #(TDiv #(wd_data, 8))  m_wstrb  = f_wr_data.first.wstrb;
	     method Action m_wready (Bool wready);
		if (f_wr_data.notEmpty && wready) f_wr_data.deq;
	     endmethod

	     // Wr Response channel
	     method Action m_bvalid (Bool bvalid, Bit #(2) bresp, Bit #(wd_user) buser);
		if (bvalid && f_wr_resp.notFull)
		   f_wr_resp.enq (AXI4_Lite_Wr_Resp {bresp: unpack (bresp), buser: buser});
	     endmethod

	     method Bool m_bready;
		return f_wr_resp.notFull;
	     endmethod

	     // Rd Addr channel
	     method Bool           m_arvalid = f_rd_addr.notEmpty;
	     method Bit #(wd_addr) m_araddr  = f_rd_addr.first.araddr;
	     method Bit #(3)       m_arprot  = f_rd_addr.first.arprot;
	     method Bit #(wd_user) m_aruser  = f_rd_addr.first.aruser;
	     method Action m_arready (Bool arready);
		if (f_rd_addr.notEmpty && arready) f_rd_addr.deq;
	     endmethod

	     // Rd Data channel
	     method Action m_rvalid (Bool           rvalid,
				     Bit #(2)       rresp,
				     Bit #(wd_data) rdata,
				     Bit #(wd_user) ruser);
		if (rvalid && f_rd_data.notFull)
		   f_rd_data.enq (AXI4_Lite_Rd_Data {rresp: unpack (rresp),
						     rdata: rdata,
						     ruser: ruser});
	     endmethod

	     method Bool m_rready;
		return f_rd_data.notFull;
	     endmethod
	  endinterface;
endmodule: mkAXI4_Lite_Master_Xactor_3

module mkAXI4_Lite_Slave_Xactor_3 #(aw_t aw, w_t w, b_t b, ar_t ar, r_t r)
   (AXI4_Lite_Slave_IFC #(wd_addr, wd_data, wd_user))
   provisos (To_FIFOF_IO #(aw_t, AXI4_Lite_Wr_Addr #(wd_addr, wd_user)),
	     To_FIFOF_IO #(w_t,  AXI4_Lite_Wr_Data #(wd_data)),
	     To_FIFOF_IO #(b_t,  AXI4_Lite_Wr_Resp #(wd_user)),
	     To_FIFOF_IO #(ar_t, AXI4_Lite_Rd_Addr #(wd_addr, wd_user)),
	     To_FIFOF_IO #(r_t,  AXI4_Lite_Rd_Data #(wd_data, wd_user)));

   FIFOF_I #(AXI4_Lite_Wr_Addr #(wd_addr, wd_user))  f_wr_addr <- mkUnguarded (to_FIFOF_I (aw));
   FIFOF_I #(AXI4_Lite_Wr_Data #(wd_data))         f_wr_data <- mkUnguarded (to_FIFOF_I (w));
   FIFOF_O #(AXI4_Lite_Wr_Resp #(wd_user))           f_wr_resp <- mkUnguarded (to_FIFOF_O (b));

   FIFOF_I #(AXI4_Lite_Rd_Addr #(wd_addr, wd_user))  f_rd_addr <- mkUnguarded (to_FIFOF_I (ar));
   FIFOF_O #(AXI4_Lite_Rd_Data #(wd_data, wd_user))  f_rd_data <- mkUnguarded (to_FIFOF_O (r));

   // ----------------------------------------------------------------
   // INTERFACE

   return interface AXI4_Lite_Slave_IFC;
	     // Wr Addr channel
	     method Action m_awvalid (Bool           awvalid,
				      Bit #(wd_addr) awaddr,
				      Bit #(3)       awprot,
				      Bit #(wd_user) awuser);
		if (awvalid && f_wr_addr.notFull)
		   f_wr_addr.enq (AXI4_Lite_Wr_Addr {awaddr: awaddr,
						     awprot: awprot,
						     awuser: awuser});
	     endmethod

	     method Bool m_awready;
		return f_wr_addr.notFull;
	     endmethod

	     // Wr Data channel
	     method Action m_wvalid (Bool                      wvalid,
				     Bit #(wd_data)            wdata,
				     Bit #(TDiv #(wd_data, 8)) wstrb);
		if (wvalid && f_wr_data.notFull)
		   f_wr_data.enq (AXI4_Lite_Wr_Data {wdata: wdata, wstrb: wstrb});
	     endmethod

	     method Bool m_wready;
		return f_wr_data.notFull;
	     endmethod

	     // Wr Response channel
	     method Bool           m_bvalid = f_wr_resp.notEmpty;
	     method Bit #(2)       m_bresp  = pack (f_wr_resp.first.bresp);
	     method Bit #(wd_user) m_buser  = f_wr_resp.first.buser;
	     method Action m_bready (Bool bready);
		if (bready && f_wr_resp.notEmpty)
		   f_wr_resp.deq;
	     endmethod

	     // Rd Addr channel
	     method Action m_arvalid (Bool           arvalid,
				      Bit #(wd_addr) araddr,
				      Bit #(3)       arprot,
				      Bit #(wd_user) aruser);
		if (arvalid && f_rd_addr.notFull)
		   f_rd_addr.enq (AXI4_Lite_Rd_Addr {araddr: araddr,
						     arprot: arprot,
						     aruser: aruser});
	     endmethod

	     method Bool m_arready;
		return f_rd_addr.notFull;
	     endmethod

	     // Rd Data channel
	     method Bool           m_rvalid = f_rd_data.notEmpty;
	     method Bit #(2)       m_rresp  = pack (f_rd_data.first.rresp);
	     method Bit #(wd_data) m_rdata  = f_rd_data.first.rdata;
	     method Bit #(wd_user) m_ruser  = f_rd_data.first.ruser;
	     method Action m_rready (Bool rready);
		if (rready && f_rd_data.notEmpty)
		   f_rd_data.deq;
	     endmethod
	  endinterface;
endmodule: mkAXI4_Lite_Slave_Xactor_3

// --------------------------------------

typedef union tagged {
   AXI4_Rd_Addr #(wd_id, wd_addr, wd_user) Read;
   AXI4_Wr_Addr #(wd_id, wd_addr, wd_user) Write;
   } AXI4_RdWr_Addr #(numeric type wd_id,
		      numeric type wd_addr,
		      numeric type wd_user)
deriving (Bits, FShow);

interface Addr_FIFOF_Pair #(numeric type wd_id,
			    numeric type wd_addr,
			    numeric type wd_user);
   interface FIFOF #(AXI4_Rd_Addr #(wd_id, wd_addr, wd_user)) ff_read;
   interface FIFOF #(AXI4_Wr_Addr #(wd_id, wd_addr, wd_user)) ff_write;
endinterface

module mkAddr_FIFOF_Pair (Addr_FIFOF_Pair #(wd_id, wd_addr, wd_user));
   Bool unguarded = True;
   Bool guarded   = False;

   FIFOF #(AXI4_RdWr_Addr #(wd_id, wd_addr, wd_user)) ff <- mkGFIFOF (guarded, unguarded);

   interface FIFOF ff_read;
      method notFull  = ff.notFull;
      method Action enq(x);
	 ff.enq(tagged Read x);
      endmethod

      method notEmpty = (ff.notEmpty && (ff.first matches tagged Read .x ? True : False));
      method first () if (ff.notEmpty &&& ff.first matches tagged Read .x);
	 return x;
      endmethod

      method Action deq () if (ff.notEmpty &&& ff.first matches tagged Read .x);
	 ff.deq;
      endmethod

      method Action clear;
	 ff.clear;
      endmethod
   endinterface
   interface FIFOF ff_write;
      method notFull  = ff.notFull;
      method Action enq(x);
	 ff.enq(tagged Write x);
      endmethod

      method notEmpty = (ff.notEmpty && (ff.first matches tagged Write .x ? True : False));
      method first () if (ff.notEmpty &&& ff.first matches tagged Write .x);
	 return x;
      endmethod

      method Action deq () if (ff.notEmpty &&& ff.first matches tagged Write .x);
	 ff.deq;
      endmethod

      method Action clear;
	 ff.clear;
      endmethod
   endinterface
endmodule

module mkAXI4_Serializing_Master_Xactor (AXI4_Master_Xactor_IFC #(wd_id, wd_addr, wd_data, wd_user));
   Addr_FIFOF_Pair #(wd_id, wd_addr, wd_user) f_rdwr_addr <- mkAddr_FIFOF_Pair;

   FIFOF #(AXI4_Wr_Addr #(wd_id, wd_addr, wd_user))  f_wr_addr = f_rdwr_addr.ff_write;
   FIFOF #(AXI4_Wr_Data #(wd_data, wd_user))         f_wr_data <- mkFIFOF;
   FIFOF #(AXI4_Wr_Resp #(wd_id, wd_user))           f_wr_resp <- mkFIFOF;

   FIFOF #(AXI4_Rd_Addr #(wd_id, wd_addr, wd_user))  f_rd_addr = f_rdwr_addr.ff_read;
   FIFOF #(AXI4_Rd_Data #(wd_id, wd_data, wd_user))  f_rd_data <- mkFIFOF;

   AXI4_Master_IFC #(wd_id, wd_addr, wd_data, wd_user) master_xactor <- mkAXI4_Master_Xactor_3(f_wr_addr,
											       f_wr_data,
      											       f_wr_resp,
      											       f_rd_addr,
											       f_rd_data);
   // ----------------------------------------------------------------
   // INTERFACE

   method Action reset;
      f_wr_addr.clear;
      f_wr_data.clear;
      f_wr_resp.clear;
      //f_rd_addr.clear;
      f_rd_data.clear;
   endmethod

   // AXI side
   interface axi_side = master_xactor;

   // FIFOF side
   interface i_wr_addr = to_FIFOF_I (f_wr_addr);
   interface i_wr_data = to_FIFOF_I (f_wr_data);
   interface o_wr_resp = to_FIFOF_O (f_wr_resp);

   interface i_rd_addr = to_FIFOF_I (f_rd_addr);
   interface o_rd_data = to_FIFOF_O (f_rd_data);
endmodule
