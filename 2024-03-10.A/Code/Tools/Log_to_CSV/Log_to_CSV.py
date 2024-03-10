#!/usr/bin/python3

# ================================================================
# Copyright (c) 2023-2024 Bluespec, Inc., All Rights Reserved
# Author: Rishiyur Nikhil

# Processes Fife log into a CSV file that can be loaded into a
# spreadsheet to display the pipeline behavior

# Contains independent parts:
# Reading:
#    read_trace_file ()    reads the file into a Matrix data structure
# Writing:
#    print_matrix ()       For debugging: pretty-print the Matrix
#    print_csv ()          print a Matrix as a CSV file (ready to load into a spreadsheet)

# ================================================================
# Import standard libs

import sys

# ----------------
# Import our libs

import disasm_lib

# ================================================================

def print_usage (argv):
    sys.stdout.write ("Usage:\n")
    sys.stdout.write ("  {0}  <foo>        (foo is a Fife log file)\n".format (argv [0]))
    sys.stdout.write ("  Creates output CSV file <foo>.csv for spreadsheet (pipeline view)\n")

debug = False

# ================================================================
# Matrix data structure

class Matrix:
    #                  int       int       [Inum_Info]
    def __init__(self, max_inum, max_tick, list_inum_info):
        assert (type (max_inum) == int)
        assert (type (max_tick) == int)
        assert (type (list_inum_info) == list)

        # list_inum_info is sorted on increasing inum
        # with each item having a unique inum

        self.max_inum = max_inum
        self.max_tick = max_inum
        self.list_inum_info = list_inum_info

class INum_Info:
    #                  int   int int    [Tick_Events]
    def __init__(self, inum, pc, instr, list_tick_events):
        assert (type (inum)             == int)
        assert (type (pc)               == int)
        assert (type (instr)            == int)
        assert (type (list_tick_events) == list)

        # list_tick_events is sorted on increasing tick
        # with each item having a unique tick (no duplicates)

        self.inum             = inum
        self.pc               = pc
        self.instr            = instr
        self.list_tick_events = list_tick_events

class Tick_Events:
    #                  int    [str]
    def __init__(self, tick,  list_event):
        assert (type (tick)       == int)
        assert (type (list_event) == list)

        # list_event is list of all events at the same tick

        self.tick       = tick
        self.list_event = list_event

# ================================================================

def main (argv = None):
    if (len (argv) == 0) or ("-h" in argv) or ("--help" in argv):
        print_usage (argv)
        return 0

    if (len (argv) != 2):
        print_usage (argv)
        return 1

    in_filename = argv [1]
    f_in = open (in_filename, "r")
    sys.stdout.write ("INFO: Input file is {:s}\n".format (in_filename))

    out_filename = in_filename + ".csv"

    f_out = open (out_filename, "w")
    sys.stdout.write ("INFO: Output file is {:s}\n".format (out_filename))

    matrix = read_trace_file (f_in)

    print_matrix (matrix)
    print_csv (f_out, matrix)

    return 0

# ================================================================
# Read file and insert data into initially empty matrix;
# return final matrix

#                    file -> Matrix
def read_trace_file (f_in):
    # Process file
    line_num   = 0
    last_cycle = 0
    last_inum  = -1
    matrix = Matrix (-1, -1, [])

    for line in f_in.readlines():
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

        # Bump max inum and tick if needed
        if (tick > matrix.max_tick):
            matrix.max_tick = tick
        if (inum > matrix.max_inum):
            matrix.max_inum = inum

        # Insert new event into matrix
        matrix.list_inum_info = insert_in_list_inum_info (matrix.list_inum_info,
                                                          tick, inum, pc, instr, stage)
        if (debug):
            print_matrix (matrix)
    return matrix

# ----------------
# Modify list_inum_info by inserting new event.
# Return list_inum_info (possibly new, possibly modified).

#                             [INum_Info]     int   int   int int    str      -> [INum_Info]
def insert_in_list_inum_info (list_inum_info, tick, inum, pc, instr, event):
    assert (type (list_inum_info) == list)
    assert (type (tick)  == int)
    assert (type (inum)  == int)
    assert (type (pc)    == int)
    assert (type (instr) == int)
    assert (type (event) == str)

    # list_inum_info is sorted by increasing inum
    for j in range (len (list_inum_info)):
        inum_info = list_inum_info [j]

        if (inum < inum_info.inum):
            new_tick_events = Tick_Events (tick, [event])
            new_inum_info   = INum_Info (inum, pc, instr, [new_tick_events])
            list_inum_info  = list_inum_info [:j] + [new_inum_info] + list_inum_info [j:]
            return list_inum_info

        elif (inum == inum_info.inum):
            assert (inum_info.pc == pc)
            if (inum_info.instr == 0):
                inum_info.instr = instr
            else:
                if (inum_info.instr != instr):
                    sys.stdout.write ("ERROR ****************")
                    sys.stdout.write ("instr mismatch on tick {:d}\n".format (tick))
                    sys.stdout.write ("  inum_info inum:{:d} pc:{:x} instr:{:x}\n"
                                      .format (inum_info.inum, inum_info.pc, inum_info.instr))
                    sys.stdout.write ("  New info  inum:{:d} pc:{:x} instr:{:x}\n"
                                      .format (inum, pc, instr))
                assert (inum_info.instr == instr)
            new_list_tick_events = insert_in_list_tick_events (inum_info.list_tick_events,
                                                               tick, event)
            inum_info.list_tick_events = new_list_tick_events
            return list_inum_info
        
        else:
            # Further down the the list
            pass

    # Fall-through: empty inums or (current inum > existing inums)
    new_tick_events = Tick_Events (tick, [event])
    new_inum_info   = INum_Info (inum, pc, instr, [new_tick_events])
    return list_inum_info + [new_inum_info]

# ----------------
# Modify list_tick_events by inserting new info.
# Return list_tick_events (possibly new, possibly modified).
# If list_tick_events already contains an item with the same tick,
#    just append this event to its list of events

#                               [Tick_Events]     int   str      -> [Tick_Events]
def insert_in_list_tick_events (list_tick_events, tick, event):
    assert (type (list_tick_events) == list)
    assert (type (tick)   == int)
    assert (type (event)  == str)

    if (list_tick_events == []):
        return [Tick_Events (tick, [event])]

    x_0 = list_tick_events [0]
    if (x_0.tick < tick):
        x_rest     = list_tick_events [1:]
        x_rest_new = insert_in_list_tick_events (x_rest, tick, event)
        return [x_0] + x_rest_new

    elif (x_0.tick == tick):
        x_0.list_event = x_0.list_event + [event]
        return list_tick_events

    else:
        return [Tick_Events (tick, event)] + list_tick_events

# ================================================================

def print_matrix (matrix):
    sys.stdout.write ("MATRIX max_inum {:d} max_tick {:d} ================\n"
                      .format (matrix.max_inum, matrix.max_tick))
    for inum_info in matrix.list_inum_info:
        sys.stdout.write ("I{:d} PC:0x{:x} instr:0x{:x}\n"
                          .format (inum_info.inum, inum_info.pc, inum_info.instr))
        for tick_events in inum_info.list_tick_events:
            sys.stdout.write ("    tick {:d}".format (tick_events.tick))
            for event in tick_events.list_event:
                sys.stdout.write (" {:s}".format(event))
            sys.stdout.write ("\n")
    sys.stdout.write ("================\n")

def print_csv (f_out, matrix):
    # Print table header
    f_out.write ("inum,PC,instr")
    for tick in range (1, matrix.max_tick + 1):
        (q,r) = divmod (tick, 10)
        if (r == 0) or (tick == 1):
            f_out.write (",{:d}".format (tick))
        elif (r == 5):
            f_out.write (",5")
        else:
            f_out.write (", ")
    f_out.write ("\n")

    # Print table contents
    for inum_info in matrix.list_inum_info:
        # DELETE f_out.write ("{:d},0x{:08x},0x{:08x}"
        #             .format (inum_info.inum, inum_info.pc, inum_info.instr))
        f_out.write ('{:d},0x{:08x},"{:s}"'
                     .format (inum_info.inum, inum_info.pc,
                              disasm_lib.disasm (64, inum_info.instr)))
        last_tick = 0
        for tick_events in inum_info.list_tick_events:
            # Skip columns until tick
            for j in range (last_tick + 1, tick_events.tick):
                f_out.write (",")
            last_tick = tick
            # Print all events for this (inum,tick)
            num_events = len (tick_events.list_event)
            assert (num_events > 0)
            if (num_events == 1):
                s = tick_events.list_event [0]
            else:
                s = '"'
                list_event = tick_events.list_event
                for k in range (len (list_event)):
                    event = list_event [k]
                    if (k == 0):
                        s = s + event
                    else:
                        s = s + "\n" + event
                s = s + '"'
            f_out.write (",{:s}".format (s))
        f_out.write ("\n")

# ****************************************************************
# ****************************************************************
# ****************************************************************
# For non-interactive invocations, call main() and use its return value
# as the exit code.
if __name__ == '__main__':
  sys.exit (main (sys.argv))
