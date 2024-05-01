Conditionals and Muxes
======================

// ----------------------------------------------------------------
(1)

Write a testbench for the instr_opclass() function: try it with
different 32-bit instructions to produce the op class, and print out
the op class.  When printing the class, try printing it as an integer,
and also symbolically using fshow().

// ----------------------------------------------------------------
(2)

Write a new version of the instr_opclass() function that expresses a
parallel MUX instead of a priority MUX (see Figure 4.6 in the book).

The key ideas are:

* Define a value x_CONTROL that is either OPCLASS_CONTROL, or 0 (of
  the same bit-width) if the boolean values of is_legal_BRANCH()|,
  is_legal_JAL() and is_legal_JALR() are all False.  We can implement
  this by replicating the 1-bit boolean condition to the width of the
  OpClass type and bitwise-AND'ing this with OPCLASS_CONTROL.

* Similarly, define values x_INT, x_MEM and x_SYSTEM that are either
  OPCLASS_INT, OPCLASS_MEM, OPCLASS_SYSTEM or 0 depending on whether
  the instruction is an integer, memory or system instruction.

* Finally, bitwise-OR the four x_XXX values together to produce the
  result.

// ----------------------------------------------------------------
(3)

Test your new version of the instr_opclass() function in your
testbench.

// ----------------------------------------------------------------
(4)

There are three ways to write conditionals: if-then-else, conditional
expressions (eb ? e1 ? e2), and case expressions.

Try some of these alternatives in any of the previous examples or the
Drum/Fife code files.

// ----------------------------------------------------------------
