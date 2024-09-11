These "log processing" tools are scripts that read the "log.txt" log
produced by Fife and Drum, and output files suitable for various
purposes.  Each tool provides documentation when invoked with '--help'
on the command line.

Note: 'disasm_lib.py' is not a tool by itself. It is a library used by
      some of the tools to disassemble a RISC-V instruction.

Examples:

  Log_to_CSV.py (Python) for pipeline visualization.

  xform_trace.py (Python) for comparing instruction trace with a
      RISC-V reference model
