Simple FSM testbenches.

// ----------------------------------------------------------------
(1)

Compile and run the code using Verilator simulation or Bluesim simulation.

// ----------------------------------------------------------------
(2)

Add more actions to the testbench to test more 32-bit values with
``is_legal_BRANCH()''.

// ----------------------------------------------------------------
(3)

Delete the ``Bit #(7) opcode_BRANCH'' constant definition and the
``is_legal_BRANCH()'' function from Top.bsv.  Instead, replace them
with one line:

    import Instr_Bits :: *;

Replace the existing Makefile (which just includes ../Include.mk)
with your own (by just copying ../Include.mk as ./Makefile).

In your Makefile, edit the BSCPATH definition to include a path to
where the Instr_Bits.bsv file is located. Replace:

    BSCPATH = src_BSV:+
with
    BSCPATH = ../../Code/src_Common:src_BSV:+

Make sure your Makefile still works: compile and run the test as in
the previous exercises.

// ----------------------------------------------------------------
(4)

Modify the testbench to test more 32-bit values with other is_legal_XXX().

// ----------------------------------------------------------------
(5)

The testbench constructs 32-bit BRANCH instructions with lines like this:

    Bit #(32) instr_BEQ = {7'h0, 5'h9, 5'h8, 3'b000, 5'h3, 7'b_110_0011};

Instead, define a function to *create* a 32-bit BRANCH instruction,
given a 13-bit immediate field, rs2 and rs1 values, and a funct3
field:

   function Bit #(32) mkBRANCH_Instr (Bit #(13) pc_offset,
                                      Bit #(5)  rs2,
                                      Bit #(5)  rs1,
                                      Bit #(3)  funct3);
      ... <fill in this code> ...
   endfunction

Refer to Figure 2.5 in the book (or to RISC-V Unpriviliged ISA spec
document) for how a 13-bit PC-offset is encoded into the 12-bit
immediate of a B-type instruction.  Your code should also check that
bit [0] of the PC-offset is zero.

In the testbench, use this function to create BRANCH instructions,
instead of lines like this:

    Bit #(32) instr_BEQ = {7'h0, 5'h9, 5'h8, 3'b000, 5'h3, 7'b_110_0011};

Also: instead of a constant like 3'b000, use the symbolic name
funct3_BEQ that is defined in the file Instr_Bits.bsv.

// ----------------------------------------------------------------
