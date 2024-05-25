Testing for legal BRANCH (and other) instructions.

(1) In the file:    Code/src Common/Instr Bits.bsv
    locate the functions:

      instr_opcode()
      instr_funct3()
      is_legal_BRANCH()

and make sure you understand them thoroughly.

// ----------------------------------------------------------------
(2) Observe that the file contains similar functions, such as:


      is_legal_JAL()|        for the JAL opcode
      is_legal_JALR()|       for the (JALR opcode
      is_legal_OP()|         for LUI, AUIPC, ADD, SLT, OR, AND, ... opcodes
      is_legal_OP_IMM()|     for ADDI, SLTI, ..., ORI, ANDI, ... opcodes
      is_legal_LOAD()|       for LB, LH, LW, LBU, LHU opcodes
      is_legal_Mem()|        for SB, SH, SW opcodes


which, in turn, use functions like
      instr_rs1()
      instr_rs2()
      instr_rd()
which are also in the file.

Study the code and check that the functions are correct (refer to the
``RV32I Base Instruction Set'' listing in ``Chapter 24 RV32/64G
Instruction Set Listings'' in the RISC-V Unprivileged ISA
specification document, which lists 40 RV32I instructions).

A visual check is sufficient, but feel free to write a testbench and
tests and run them if you feel inspired to do so.

// ----------------------------------------------------------------
