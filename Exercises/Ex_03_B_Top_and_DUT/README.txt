Program with two packages/files: Top and DUT
============================================

// ----------------------------------------------------------------
(1)

Compile, link, and run the given example, in either Bluesim simulation
or in Verilator Verilog simulation, using the Makefile commands (same
as last exercise: b_compile, b_link, b_run, v_compile, v_link, v_run).

// ----------------------------------------------------------------
(2)

Try the compile steps above after removing the ``-u'' command-line
flag and observe the behavior.

// ----------------------------------------------------------------
(3)

Change Bit#(11) to Bit#(8) in DUT.bsv; retry the compile-link-run, and
observe the behavior.

// ----------------------------------------------------------------
(4)

Write down a BSV hexadecimal integer literal whose value is equal to
decimal 22 (hexadecimal integers in BSV use the same notation as in
Verilog and SystemVerilog (see book Section 4.2).

// ----------------------------------------------------------------
(5)

Add another '$display()' statement that reports the number of years
that have elapsed from the publication of Kernighan and Ritchie's book
to today.

// ----------------------------------------------------------------
