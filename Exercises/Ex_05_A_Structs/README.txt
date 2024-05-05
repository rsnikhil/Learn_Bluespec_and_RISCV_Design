Structs
=======

In this exercise we are going to use some actual Drum/Fife code;
specifically, these files:

    $(BOOK_REPO)/Code/src_Common/Instr_Bits.bsv
    $(BOOK_REPO)/Code/src_Common/Mem_Req_Rsp.bsv

// ----------------------------------------------------------------
(1)

In file 'Makefile', observe and understand the new additions for this exercise.
(Hint: think about the 'import' statements in src_BSV/Top.bsv.)

In order to build with this Makefile you will likely have to edit the
definition of BOOK_REPO to point at the correct directory in your
environment.

// ----------------------------------------------------------------
(2)

Compile and run the code using Verilator simulation or Bluesim simulation.
Observe and understand the output.

// ----------------------------------------------------------------
(3)

Comment-out the 'import Instr_Bits' and 'import Mem_Req_Rsp'
statements, one at a time, and try to recompile.
Compilation will fail: in each case, observe and understand the error message.

// ----------------------------------------------------------------
(4)

Comment-out the 'data' field definition in the struct definition.

Recompile, and observe and understand the compiler message.

Recompile and link and run.  What is the difference between the value
printed for the 'data' field and what was printed earlier?

// ----------------------------------------------------------------
(5)

Duplicate the '$display()' statement twice.

In the first new copy of the statement, replace:
    fshow (mem_req)
with:
    mem_req

In the second new copy of the staement, replace:
    fshow (mem_req)
with
    fshow_Mem_Req (mem_req)
Note, you can find the definition of the 'fshow_Mem_Req()' function in
the file $(BOOK_REPO)/Code/src_Common/Mem_Req_Rsp.bsv

Recompile and run.
Observe and understand the differences in the outputs from the
original and from the two new statements.

// ----------------------------------------------------------------
(6)

In file 'Mem_Req_Rsp.bsv', locate the function 'fshow_Mem_Req_Type()'.
Understand the code (see section "11.3.2 Fmt formatted values" in the
book which explains the Fmt type and the $format() function).

After the existing $display() statement, add a line like this:
    $display ("mem_req.req_type = ", fshow_Mem_Req_Type (mem_req.req_type));
Recompile and run.

Observe and understand the outputs.

Compare the value printed for the 'req_type' field from the two
$display() statements.

// ----------------------------------------------------------------
(7)

After the $display() statement, add a line that updates the
mem_req_type field of the struct by assigning funct5_STORE to the
field (replacing its current value of funct5_LOAD). Then, replicate
the $display() statement to print the new value of the struct.

Recompile and run (should see output of original and new $display).
Observe and understand the output.

// ----------------------------------------------------------------
