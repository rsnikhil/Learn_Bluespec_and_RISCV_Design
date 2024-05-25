import StmtFSM :: *;

Bit #(7) opcode_BRANCH = 7'b_110_0011;

function Bool is_legal_BRANCH (Bit #(32) instr);
   Bit #(7) opcode = instr [6:0];
   Bit #(3) funct3 = instr [14:12];
   Bool legal = ((opcode == opcode_BRANCH)
                 && (funct3 != 3'b010)
                 && (funct3 != 3'b011));
   return legal;
endfunction

(* synthesize *)
module mkTop (Empty);

   mkAutoFSM (
      seq
	 action
	    Bit #(32) instr_BEQ = {7'h0, 5'h9, 5'h8, 3'b000, 5'h3, 7'b_110_0011};
	    $display ("instr_BEQ %08h => ", instr_BEQ,
		      fshow (is_legal_BRANCH (instr_BEQ)));
	 endaction

	 action
	    Bit #(32) instr_BNE = {7'h0, 5'h9, 5'h8, 3'b001, 5'h3, 7'b_110_0011};
	    $display ("instr_BNE %08h => ", instr_BNE,
		      fshow (is_legal_BRANCH (instr_BNE)));
	 endaction

	 action
	    Bit #(32) instr_ILL_op = {7'h0, 5'h9, 5'h8, 3'b100, 5'h3, 7'b_110_0000};
	    $display ("instr_ILL_op %08h => ", instr_ILL_op,
		      fshow (is_legal_BRANCH (instr_ILL_op)));
	 endaction

	 action
	    Bit #(32) instr_ILL_f3 = {7'h0, 5'h9, 5'h8, 3'b010, 5'h3, 7'b_110_0011};
	    $display ("instr_ILL_f3 %08h => ", instr_ILL_f3,
		      fshow (is_legal_BRANCH (instr_ILL_f3)));
	 endaction
      endseq);

endmodule
