#!/usr/bin/python3 -B
# Copyright (c) 2020-2024 Bluespec, Inc., All Rights Reserved
# Author: Rishiyur Nikhil

# ================================================================

import sys
import os

# ================================================================

def print_usage (fo, argv):
    fo.write ("Usage:  {0}  <inputfile.txt>  <foo>\n".format (argv [0]))
    fo.write ("  <inputfile.txt> is trace file from Drum or Fife\n")
    fo.write ("  Writes two files, <foo>.txt and <foo>_aux.txt\n")
    fo.write ("  For each line L in inputfile, let (b,L') = xform (x,L)\n")
    fo.write ("    If b, write L' to foo.txt and L'+L to foo_aux.txt\n")
    fo.write ("    (foo.txt can be used for other tools, like diff,\n")
    fo.write ("     and the corresponding lines in foo_aux.txt provide context\n")

# ================================================================

def main (argv):
    if (("-h" in argv) or
        ("--help" in argv) or
        (len (argv) != 3)):
        print_usage (sys.stdout, argv)
        return 0

    (infilename, outfilename) = (argv [1], argv [2])
    outfilename_1 = outfilename + ".txt"
    outfilename_2 = outfilename + "_aux.txt"


    sys.stdout.write ("INFO: in file:    '{:s}'\n".format (infilename))
    sys.stdout.write ("INFO: out file_1: '{:s}'\n".format (outfilename_1))
    sys.stdout.write ("INFO: out file_2: '{:s}'\n".format (outfilename_2))

    try:
        fi = open (infilename, "r")
    except:
        sys.stdout.write ("ERROR: could not open input file: {:s}\n"
                          .format (infilename))
        return 1

    try:
        fo_1 = open (outfilename_1, "w")
    except:
        sys.stdout.write ("ERROR: could not open output file: {:s}\n"
                          .format (outfilename_1))
        return 1

    try:
        fo_2 = open (outfilename_2, "w")
    except:
        sys.stdout.write ("ERROR: could not open output file: {:s}\n"
                          .format (outfilename_2))
        return 1

    in_line_num = 1
    out_line_num = 1
    while (True):
        # Read a line from f1 containing "EXEC"
        while (True):
            line = fi.readline()
            in_line_num += 1
            if line == "": break
            (b, xline) = xform (line)
            if b: break

        if (line == ""): break    # EOF
        line = line.rstrip()

        fo_1.write ("{:s}\n".format (xline))
        fo_2.write ("{:s} ***** L{:d}: {:s}\n".format (xline, in_line_num, line))
        out_line_num += 1

    sys.stdout.write ("Num lines: input:{:d}  output:{:d}\n"
                      .format (in_line_num, out_line_num))
    fi.close()
    fo_1.close()
    fo_2.close()
    return 0

# ================================================================
# This function processes each line

def xform (line):
    # For Drum/Fife
    if not line.startswith ("Trace"): return (False, None)
    if not ("RET"          in line):   return (False, None)
    if      "RET.Drsp"     in line:    return (False, None)
    if      "RET.discard"  in line:    return (False, None)
    if      "RET.CSRRxx.X" in line:    return (False, None)
    if      "RET.Dir.X"    in line:    return (False, None)

    words = line.split ()
    pc    = int (words [3], 16)
    instr = int (words [4], 16)
    xline = "{:08x} {:08x}".format (pc, instr)
    return (True, xline)

# ================================================================
# For non-interactive invocations, call main() and use its return value
# as the exit code.
if __name__ == '__main__':
    sys.exit (main (sys.argv))
