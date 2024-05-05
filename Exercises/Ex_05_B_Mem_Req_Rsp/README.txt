Memory Requests and Responses
=============================

In these exercises we will write a testbench that sends read requests
to a memory model and examines the memory responses.

We are going to use some additional actual Drum/Fife code;
specifically, these files:

    $(BOOK_REPO)/Code/src_Common/Utils.bsv
    $(BOOK_REPO)/Code/src_Top/Mems_Devices.bsv
    $(BOOK_REPO)/Code/src_Top/C_Mems_Devices.c
    $(BOOK_REPO)/Code/src_Top/UART_model.c
    $(BOOK_REPO)/Code/vendor/bluespec_BSV_Additional_Libs/Semi_FIFOF.bsv

Utils.bsv is needed for the is Initial_Params struct definition.

Mems_Devices.bsv, C_Mems_Devices.c and UART_model.c constitute the
"memory system model" used in the Drum and Fife testbenches.

Semi_FIFOF.bsv is for some FIFO definitions for connecting to the
    memory system model.

// ----------------------------------------------------------------
(1)

In file 'Makefile', study and understand the new additions for this exercise.

Hint 1: think about the 'import' statements in src_BSV/Top.bsv.
Hint 2: In file $(BOOK_REPO)/Code/src_Top/Mems_Devices.bsv
        there are some 'import "BDPI"' statements that refer
        to C functions that are defined in the C files mentioned above.

In order to build with this Makefile you will likely have to edit the
definition of BOOK_REPO to point at the correct directory in your
environment.

// ----------------------------------------------------------------
(2)

Study and understand the code in Top.bsv.

When the program is run, the statement:
    mems_devices.init (init_params);
will initialize the memory model and load it with data from file
'test.memhex32'.

Study and understand the contents of file 'test.memhex32'.

This file contains 16 instructions from the 'Hello World!' program,
starting at address 0x_8000_0000.
Study the file:
    $(BOOK_REPO)/Tools/Hello_World_Example_Code/hello.RV32.bare.objdump
and locate these 16 instructions. Then, you can see the assembly
language for these instructions.

// ----------------------------------------------------------------
(3)

Compile and run the code using Verilator simulation or Bluesim simulation.
Observe and understand the output.

// ----------------------------------------------------------------
(4)

There are two 'Top.bsv' files visible:
  (A) In this exercise: ./src_BSV/Top.bsv)
  (B) In Drum/Fife:     $(BOOK_REPO)/Code/src_Top/Top.bsv

When we compile, why does 'bsc' pick (A) and not (B)?

// ----------------------------------------------------------------
(5)

In ./src_BSV/Top.bsv, in module mkTop, just before mkAutoFSM, define a
function to encapsulate and generalize the 'a_req' action:

  function Action a_req (Mem_Req_Type t,
                         Mem_Req_Size s,
                         Bit #(64)    a,    // addr
                         Bit #(64)    d,    // data
                         Bit #(64)    i);   // inum
    ... body is a_req action with above arguments instead of constants ...

Similarly, define a function to encapsulate and generalize the 'a_rsp' action:

  function Action a_rsp ();
    ... body is a_rsp action ...

Replace the original 'a_req' and 'a_rsp' actions with calls to these
functions.  Note, you won't need 'action-endaction' brackets any more.

Recompile and run and verify that the output is the same as before.

// ----------------------------------------------------------------
(6)

Add an additional memory request and response for the next instruction
(address = 'h_8000_0004, inum = 2):

    // Original addr
    a_req (..., 'h_8000_0000, ..., 1);
    a_rsp;    
    // Next instruction addr
    a_req (..., 'h_8000_0004, ..., 2);
    a_rsp;    

Recompile and run and verify that the output is as expected (matches
contents of test.memhex32).

// ----------------------------------------------------------------
(7)

Add more calls to a_req()/a_rsp() (or replace the earlier ones):

(6A) Vary the Mem_Req_Size argument to be, variously, MEM_1B, MEM_2B and MEM_4B.

(6B) For MEM_2B and MEM_4B, try both aligned and unaligned addresses.

In each case, recompile and run, and observe and understand the output.

// ----------------------------------------------------------------
(8)

In each run so far, observe that the memory system announces the range
of addresses that it implements for the memory model:

  INFO: c_mems_devices_init
    Mem system model
     ADDR_BASE_MEM:  0x80000000 SIZEB_MEM:  0x10000000 (268435456) bytes

Note that the memory size is much larger than the contents of test.memhex32.

Add more calls to a_req()/a_rsp() (or replace the earlier ones):

(7A) Try a LOAD from address 'h_8000_0040
     (This address is implemented by the memory model, but is not defined in
      test.memhex32).

(7B) Try a LOAD from address 'h_9000_0000
     (This address is not implemented by the memory model).

In each case, recompile and run, and observe and understand the output.

// ----------------------------------------------------------------
(9)

Add more calls to a_req()/a_rsp() (or replace the earlier ones):
* Do a STORE to some memory location
* Then do a LOAD to read it back, and verify that the loaded value is
  indeed what we stored.
* Do LOADs with addresses on either side of the STORE address/size and
  verify that the STORE did not disturb those locations.

In each case, recompile and run, and observe and understand the output.

// ----------------------------------------------------------------
(10)

In each run so far, observe that the memory system announces the range
of MMIO addresses that it implements for the UART model:

  INFO: c_mems_devices_init
     ...
     ADDR_BASE_UART: 0x60100000 SIZEB_UART: 0x00001000 (4096) bytes

The UART models a standard 16550 UART, which has several memory-mapped
registers, but for this test we will only use 'h_6010_0000 which is
the "transmit buffer".  Every time we write a byte to the transmit
buffer, it gets "transmitted" and displayed on the screen.

Add more calls to a_req()/a_rsp() (or replace the earlier ones):

  Do a series of a_req() calls, one for each character in "Hello World!\r\n".
  Each call should be for a 1-byte STORE, to address 'h_6010_0000,
  with data being the ASCII hex code of that character..

Recompile and run, and observe and understand the output.

[More difficult] Why is "Hello World!\r\n" all printed together,
  instead of each character being printed as soon as we do the
  corresponding STORE?

  Hint: See "// Write the char to the output line buffer" and
        lines 526-535 that follow in UART_Model.c

// ----------------------------------------------------------------
(11)

When printing "Hello World!\r\n" (i.e., 14 characters) in (9), we
alternated fourteen a_req()'s with fourteen a_rsp()'s, like this:

    a_req(); a_rsp(); ...; a_req(); a_rsp();    // 14 pairs

Reorganize the code so that we first have all fourteen a_req()'s
followed by all fourteen a_rsp()'s.

    a_req(); ...; a_req();    // 14 requests
    a_rsp; ...; a_rsp();      // 14 responses

Recompile and run, and observe and understand the behavior.

Hint: the path in and out of memory is pipelined (so we can send in
multiple requests before retrieving a response).  But it has a finite
depth, so when it "fills up", the pipeline gets stuck; it cannot
accept any more requests until we drain some responses.

// ----------------------------------------------------------------
(12)

Reorganize the code from this:

    a_req(); ...; a_req();    // 14 requests
    a_rsp; ...; a_rsp();      // 14 responses

to this:

    par
      seq a_req(); ...; a_req(); endseq
      seq a_rsp; ...; a_rsp(); endseq
    endpar

The 'par-endpar' block allows its two components to run concurrently.

Recompile and run, and observe and understand the behavior.

// ----------------------------------------------------------------
(13)

Study the C files to see how the memory model and UART model are implemented.

// ----------------------------------------------------------------
