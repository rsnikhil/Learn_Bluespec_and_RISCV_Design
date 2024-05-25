Hello World! in BSV
===================

For this, and all the remaining exercises, you will need an installation of the free and open-source tools:
    'bsc' compiler
    Verilator compiler

For bsc, see: https://github.com/B-Lang-org/bsc
    Download and installation info
    BSV Language Reference Guide (PDF)
    BSV Libraries Reference Guide (PDF)
    BSC User Guide (PDF)
    (PDFs also available in bsc installation directory).

For Verilator: https://www.veripool.org/verilator
    Download and installation info
    Verilator user manual

// ----------------------------------------------------------------
(1)

Observe the version of bsc and verilator in your installation by
typing these commands:

    $ bsc -v
    Bluespec Compiler, version 2024.01 (build ae2a2fc)
    This is free software; for source code and copying conditions, see
    https://github.com/B-Lang-org/bsc

    $ verilator --version
    Verilator 5.018 2023-10-30 rev v5.018-38-g344f87abe

Observe a a full list of command-line options for bsc and verilator by typing:


    $ bsc --help
    $ verilator --help

The "Bluespec Compiler (BSC) User Guide" is a detailed guide on using bsc.

// ----------------------------------------------------------------
(2)

Compile and run the given BSV program Top.bsv using both Bluesim
simulation and Verilator Verilog simulation.

For help:
    $ make    or    $ make help

For Bluesim:
    $ make b_compile
    $ make b_link
    $ make b_sim
    Hello, World!                        # output

For Verilator:
    $ make v_compile
    $ make v_link
    $ make v_sim
    Hello, World!                        # output

For each of the above 'make' commands, make sure you understand what
it does, by examining the Makefile, or using the --dry-run flag like
this, or examining the terminal when you actually run 'make'.

    $ make <target> --dry-run

Once you understand these actions, you should be able to create your
own Makefiles for bsc and Verilator.

// ----------------------------------------------------------------
(3)

Comment-out the '$finish ()' statement from the code in Top.bsv,
recompile and run, and observe the behavior.

// ----------------------------------------------------------------
