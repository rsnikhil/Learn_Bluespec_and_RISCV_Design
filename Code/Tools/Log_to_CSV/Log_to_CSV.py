#!/usr/bin/python3

# ================================================================
# Copyright (c) 2023-2024 Bluespec, Inc., All Rights Reserved
# Author: Rishiyur Nikhil

# ================================================================

def print_usage (argv):
    sys.stdout.write ("Usage:\n")
    sys.stdout.write ("  {0}  <log.txt>  <inum1  <inum2>\n".format (argv [0]))
    sys.stdout.write ("  where <log.txt> is a log file from Fife or Drum\n")
    sys.stdout.write ("        <inum1>   is an instruction-number\n")
    sys.stdout.write ("        <inum2>   is an instruction-number\n")
    sys.stdout.write ("  Creates two output files:")
    sys.stdout.write ("    <log.txt>.data    Pipeline events data\n")
    sys.stdout.write ("                        for instructions <inum1> thru <inum2>\n")
    sys.stdout.write ("    <log.txt>.csv     CSV version of data, viewable in a spreadsheet\n")
    sys.stdout.write ("                        as a pipeline visualization\n")

# ================================================================

debug = False

# ================================================================
# Import standard libs

import sys
import fileinput

# ----------------
# Import our libs

import disasm_lib

# ================================================================

def main (argv = None):
    if (len (argv) <= 1) or ("-h" in argv) or ("--help" in argv):
        print_usage (argv)
        return 0

    if (len (argv) != 4):
        print_usage (argv)
        return 1

    in_filename = argv [1]
    inum1       = int (argv [2])
    inum2       = int (argv [3])

    sys.stdout.write ("INFO: Inum range is [{:0d}..{:0d}]\n".format (inum1, inum2))

    if (inum1 > inum2):
        sys.stdout.write ("ERROR: inum2 should be > inum1\n");
        return 1;

    f_in = open (in_filename, "r")
    sys.stdout.write ("INFO: Input file is {:s}\n".format (in_filename))

    (min_tick, max_tick, events) = read_trace_file (f_in, inum1, inum2)
    sys.stdout.write ("INFO: tick range is [{:0d}..{:0d}]\n".format (min_tick, max_tick))

    # ----------------
    # Output raw data
    data_filename = in_filename + ".data"
    sys.stdout.write ("INFO: Raw data output file is {:s}\n".format (data_filename))
    f_data = open (data_filename, "w")
    cur_inum = 0
    for e in events:
        (inum, pc, instr, tick, stage) = e
        if (inum > cur_inum):
            f_data.write ("Inum:{:0d} PC:{:08x} instr:{:08x}\n".format (inum, pc, instr))
            cur_inum = inum
        f_data.write ("    {:0d} {:s}\n".format (tick, stage))
    f_data.close()

    # ----------------
    # Output CSV data
    csv_filename = in_filename + ".csv"
    sys.stdout.write ("INFO: CSV output file is {:s}\n".format (csv_filename))
    f_csv = open (csv_filename, "w")
    emit_csv (f_csv, inum2, min_tick, max_tick, events)
    return 0

# ================================================================
# Emit to output file(s)

def emit_csv (f_csv, inum2, min_tick, max_tick, events):
    emit_header (f_csv, min_tick, max_tick)

    tick_offset     = 0
    cur_inum        = 0
    cur_inum_events = []
    for e in events:
        (inum, pc, instr, tick, stage) = e
        if (tick_offset == 0):
            tick_offset = tick
        if (inum > inum2):
            break
        elif (inum > cur_inum):
            if (cur_inum != 0):
                emit_instr (f_csv, cur_inum, tick_offset, cur_inum_events)
            cur_inum = inum
            cur_inum_events = [e]
        elif (inum == cur_inum):
            cur_inum_events.append (e)
        else:
            sys.stderr.write ("ERROR: inum in file ({:0d}) < cur_inum ({:0d})\n"
                              .format (inum, cur_inum));
            sys.exit (1)

    if (cur_inum != 0):
        emit_instr (f_csv, cur_inum, tick_offset, cur_inum_events)

# Emit instr info
def emit_header (f_csv, min_tick, max_tick):
    f_csv.write ("inum, PC, Instr")
    for tick in range (min_tick, max_tick):
        (q,r) = divmod (tick, 10)
        if (r == 0) or (tick == min_tick):
            f_csv.write (",{:d}".format (tick))
        elif (r == 5):
            f_csv.write (",5")
        else:
            f_csv.write (", ")
    f_csv.write ("\n")

# Emit stages of instruction
def emit_instr (f_csv, inum, tick_offset, events):
    f_csv.write ("{:0d}".format (inum))

    instr = 0
    for (_,pc,instrj,_,_) in events:
        if (instrj != 0):
            instr = instrj;
            break
    f_csv.write (',0x{:08x},"{:s}"'.format (pc, disasm_lib.disasm (64, instr)))

    tick = tick_offset
    for j in range (len (events)):
        (_, _, _, tickj, stage) = events [j]
        for j in range (tickj - tick):
            f_csv.write (", ")
        tick = tickj + 1
        f_csv.write (",{:s}".format (stage))
    f_csv.write ("\n")

# ================================================================
# Read file discarding items with inums outside the (inum,inum+n) rant
# return (min_tick, max_tick, events)    where events are sorted by inum

def read_trace_file (f_in, inum1, inum2):
    # Process file
    line_num   = 0
    min_tick   = 0
    max_tick   = 0

    events = []
    while True:
        line = f_in.readline()
        if line == "": break
        line_num += 1
        words = line.split()
        # Ignore lines that dont's begin with "Trace"
        if words [0] != "Trace": continue

        if (debug):
            sys.stdout.write ("Line {:d} '{:s}'\n".format(line_num, line.strip()))

        tick  = int (words [1])
        inum  = int (words [2])
        pc    = int (words [3], 16)
        instr = int (words [4], 16)
        stage = words [5]

        if (inum < inum1): continue
        if ((inum2 + 20) < inum): break

        event = (inum, pc, instr, tick, stage)
        events.append (event)
        if (min_tick == 0):
            min_tick = tick
        if (inum <= inum2) and (max_tick < tick):
            max_tick = tick

    # Sort events by inum
    events.sort (key = (lambda e: e[0]))

    return (min_tick, max_tick, events)

# ****************************************************************
# ****************************************************************
# ****************************************************************
# For non-interactive invocations, call main() and use its return value
# as the exit code.
if __name__ == '__main__':
  sys.exit (main (sys.argv))
