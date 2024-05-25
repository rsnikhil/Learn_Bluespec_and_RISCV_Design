Pure Functions
==============

// ----------------------------------------------------------------
(1)

Write functions with the following types:

    function Bit #(12) instr_imm_I (Bit #(32) instr);
    function Bit #(12) instr_imm_S (Bit #(32) instr);
    function Bit #(13) instr_imm_B (Bit #(32) instr);
    function Bit #(20) instr_imm_U (Bit #(32) instr);
    function Bit #(21) instr_imm_J (Bit #(32) instr);

These pick out the "immediate" fields in I-, S-, B-, U- and J-type
instructions, respectively, and rearrange the bits as appropriate to
form the proper immediate value.

Note: These functions exist already in the Drum/Fife file
'Code/src_Common/instr_Bits.bsv'.  We recommend either writing your
solutions without looking at those solutions or, study those solutions
to understand them, put them aside, and then try writing them yourself
from scratch.

// ----------------------------------------------------------------
(2)

Write a testbench that invokes each of these functions with 32-bit
constants (representing instructions) and prints out the inputs and
outputs.  Compile and run them and visually inspect the outputs for
correctness.

// ----------------------------------------------------------------
