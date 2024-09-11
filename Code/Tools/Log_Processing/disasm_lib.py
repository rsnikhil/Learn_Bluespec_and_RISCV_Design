#!/usr/bin/python3

# Library function to disassemble a RISC-V instruction
# Copyright (c) 2020-2023 Rishiyur S. Nikhil and Bluespec, Inc., All Rights Reserved
# Author: Rishiyur Nikhil

# TODO (2020-10-07):
#  - Only first-pass coding done; Needs careful code-review and cleanup
#  - Each 'immed' needs proper treatment (zero/sign-extension, shifting, ...)
#  - Show 32-bit expansion of Compressed instrs
#  - More args to restrict ISA options (making some instrs illegal)

# ================================================================
# Disassemble a single instruction
# xlen must be 32, 64 or 128
# instr is an integer, encoding an instruction
# Returns a string, the disassembly of the instruction

def disasm (xlen, instr):
    if (instr < 0):
        return "[ERROR: 'instr' is negative: {:_x}]".format (instr)

    if (bitsel (instr,1,0) == 0x3):
        return disasm_32b_instr (xlen, instr)
    else:
        return disasm_16b_instr (xlen, instr)

# ================================================================

def disasm_32b_instr (xlen, instr):
    if ((instr >> 32) != 0):
        return "[ERROR: 'instr' is > 32 bits: {:_x}]".format (instr)

    s = ""

    opcode7 = bitsel (instr,  6,  0)
    rd      = bitsel (instr, 11,  7)
    funct3  = bitsel (instr, 14, 12)
    rm      = bitsel (instr, 14, 12)
    rs1     = bitsel (instr, 19, 15)
    rs2     = bitsel (instr, 24, 20)
    rs3     = bitsel (instr, 31, 27)
    funct7  = bitsel (instr, 31, 25)
    imm12   = bitsel (instr, 31, 20)
    imm20   = bitsel (instr, 31, 12)
    shamt32 = bitsel (instr, 24, 20)

    shamt64 = bitsel (instr, 25, 20)
    funct6  = bitsel (instr, 31, 26)

    immS    = ((  bitsel (instr, 11,  7) <<  0)
               | (bitsel (instr, 31, 25) <<  5))

    immB    = ((  bitsel (instr,  7,  7) << 11)
               | (bitsel (instr, 11,  8) <<  1)
               | (bitsel (instr, 30, 25) <<  5)
               | (bitsel (instr, 31, 31) << 12))

    immU    = (imm20 << 12)

    immJ    = ((  bitsel (instr, 19, 12) << 12)
               | (bitsel (instr, 20, 20) << 11)
               | (bitsel (instr, 30, 21) <<  1)
               | (bitsel (instr, 31, 31) << 20))

    rl      = bitsel (instr, 25, 25)
    aq      = bitsel (instr, 26, 26)
    funct5  = bitsel (instr, 31, 27)

    # ---- LUI
    if (opcode7 == 0b_011_0111):
        s += "LUI " + r_s (rd) + " := " + x_s(immU)
        s += "    (class_LUI)"

    # ---- AUIPC
    elif (opcode7 == 0b_001_0111):
        s += "AUIPC " + r_s (rd) + " := PC+" + x_s(immU)
        s += "    (class_AUIPC)"

    # ---- JUMP
    elif (opcode7 == 0b_110_1111):
        s += "JAL PC+" + x_s(immJ) + "; " + r_s (rd) + " := PC"
        s += "    (class_JAL)"

    elif (funct3 == 0) and (opcode7 == 0b_110_0111):
        s += "JALR PC+" + r_s (rs1) + "+" + x_s(imm12) + "; " + r_s(rd) + " := PC"
        s += "    (class_JALR)"

    # ---- BRANCH
    elif (opcode7 == 0b_110_0011):
        if   (funct3 == 0b_000): op_s = "BEQ"
        elif (funct3 == 0b_001): op_s = "BNE"
        elif (funct3 == 0b_100): op_s = "BLT"
        elif (funct3 == 0b_101): op_s = "BGE"
        elif (funct3 == 0b_110): op_s = "BLTU"
        elif (funct3 == 0b_111): op_s = "BGEU"
        else:                    op_s = "<UNKNOWN>"

        s += op_s + " " + r_s (rs1) + " " + r_s (rs2) + "; PC+" + x_s(immB)
        s += "    (class_BRANCH)"

    # ---- LOAD
    elif (opcode7 == 0b_000_0011):
        if   (funct3 == 0b_000): size_s = "B"
        elif (funct3 == 0b_001): size_s = "H"
        elif (funct3 == 0b_010): size_s = "W"
        elif (funct3 == 0b_011): size_s = "D"
        elif (funct3 == 0b_100): size_s = "BU"
        elif (funct3 == 0b_101): size_s = "HU"
        elif (funct3 == 0b_110): size_s = "WU"
        else:                    size_s = "<UNKNOWN>"

        s += "L" + size_s + " " + r_s(rd) + " := MEM [" + r_s(rs1) + " + " + x_s(imm12) + "]"
        s += "    (class_LOAD)"

    # ---- STORE
    elif (opcode7 == 0b_010_0011):
        if   (funct3 == 0b_000): size_s = "B"
        elif (funct3 == 0b_001): size_s = "H"
        elif (funct3 == 0b_010): size_s = "W"
        elif (funct3 == 0b_011): size_s = "D"
        else:                    size_s = "<UNKNOWN>"

        s += "S" + size_s + " MEM [" + r_s(rs1) + " + " + x_s(imm12) + "] := " + r_s (rs2)
        s += "    (class_STORE)"

    # ---- ALU Imm
    elif (opcode7 == 0b_001_0011):
        op_s = "<UNKNOWN>"
        if   (funct3 == 0b_000): op_s = "ADDI"
        elif (funct3 == 0b_010): op_s = "SLTI"
        elif (funct3 == 0b_011): op_s = "SLTIU"
        elif (funct3 == 0b_100): op_s = "XORI"
        elif (funct3 == 0b_110): op_s = "ORI"
        elif (funct3 == 0b_111): op_s = "ANDI"
        elif (funct3 == 0b_001) and (funct6 == 0b_00_0000): op_s = "SLLI"
        elif (funct3 == 0b_101) and (funct6 == 0b_00_0000): op_s = "SRLI"
        elif (funct3 == 0b_101) and (funct6 == 0b_01_0000): op_s = "SRAI"

        if (op_s == "SLLI") or (op_s == "SRLI") or (op_s == "SRAI"):
            s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + " shiftby " + x_s(shamt64)
            if (xlen == 32) and (bitsel (instr, 25, 25) == 1): s+= "(ILLEGAL for RV32)"
        else:
            s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)

        s += "    (class_ALU_I)"

    # ---- ALU
    elif (opcode7 == 0b_011_0011):
        op_s = "<UNKNOWN>"
        if   (funct3 == 0b_000) and (funct7 == 0b_000_0000): op_s = "ADD"
        elif (funct3 == 0b_000) and (funct7 == 0b_010_0000): op_s = "SUB"
        elif (funct3 == 0b_001) and (funct7 == 0b_000_0000): op_s = "SLL"
        elif (funct3 == 0b_010) and (funct7 == 0b_000_0000): op_s = "SLT"
        elif (funct3 == 0b_011) and (funct7 == 0b_000_0000): op_s = "SLTU"
        elif (funct3 == 0b_100) and (funct7 == 0b_000_0000): op_s = "XOR"
        elif (funct3 == 0b_101) and (funct7 == 0b_000_0000): op_s = "SRL"
        elif (funct3 == 0b_101) and (funct7 == 0b_010_0000): op_s = "SRA"
        elif (funct3 == 0b_110) and (funct7 == 0b_000_0000): op_s = "OR"
        elif (funct3 == 0b_111) and (funct7 == 0b_000_0000): op_s = "AND"

        s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)
        s += "    (class_ALU)"

    # ---- ALU Imm W
    elif (opcode7 == 0b_001_1011):
        op_s = "<UNKNOWN>"
        if   (funct3 == 0b_000):                             op_s = "ADDIW"
        elif (funct3 == 0b_001) and (funct7 == 0b_000_0000): op_s = "SLLIW"
        elif (funct3 == 0b_101) and (funct7 == 0b_000_0000): op_s = "SRLIW"
        elif (funct3 == 0b_101) and (funct7 == 0b_010_0000): op_s = "SRAIW"

        if (op_s == "SLLIW") or (op_s == "SRLIW") or (op_s == "SRAIW"):
            s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + " shiftby " + x_s(shamt32)
        else:
            s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)

        s += "    (class_ALU_IW)"

    # ---- ALU W
    elif (opcode7 == 0b_011_1011):
        op_s = "<UNKNOWN>"
        if   (funct3 == 0b_000) and (funct7 == 0b_000_0000): op_s = "ADDW"
        elif (funct3 == 0b_000) and (funct7 == 0b_010_0000): op_s = "SUBW"
        elif (funct3 == 0b_101) and (funct7 == 0b_000_0000): op_s = "SLLW"
        elif (funct3 == 0b_101) and (funct7 == 0b_010_0000): op_s = "SRLW"
        elif (funct3 == 0b_101) and (funct7 == 0b_010_0000): op_s = "SRAW"

        s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)
        s += "    (class_ALU_W)"

    # ---- FENCE
    elif (opcode7 == 0b_000_1111):
        op_s = "<UNKNOWN>"
        if (funct3 == 0b_000): op_s = "FENCE"
        elif (funct3 == 0b_001): op_s = "FENCE.I"

        if (op_s == "FENCE"):
            s += (op_s
                  + " fm " + x_s (bitsel (instr, 31, 28))
                  + " pred " + x_s (bitsel (instr, 27, 24))
                  + " succ " + x_s (bitsel (instr, 23, 20)))

        elif (op_s == "FENCE.I"):
            s += (op_s
                  + " " + r_s (rd)
                  + " := " + r_s (rs1)
                  + ", " + x_s (imm12))

        s += "    (class_FENCE)"

    # ---- MULDIV
    elif (opcode7 == 0b_011_0011):
        op_s = "UNKNOWN"
        if (funct7 == 0b_000_0001):
            if   (funct3 == 0b_000): op_s = "MUL"
            elif (funct3 == 0b_001): op_s = "MULH"
            elif (funct3 == 0b_010): op_s = "MULHSU"
            elif (funct3 == 0b_011): op_s = "MULHU"
            elif (funct3 == 0b_100): op_s = "DIV"
            elif (funct3 == 0b_101): op_s = "DIVU"
            elif (funct3 == 0b_110): op_s = "REM"
            elif (funct3 == 0b_111): op_s = "REMU"

        s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(rs2)
        s += "    (class_MULDIV)"

    elif (opcode7 == 0b_011_1011):
        op_s = "UNKNOWN"
        if (funct7 == 0b_000_0001):
            if   (funct3 == 0b_000): op_s = "MULW"
            elif (funct3 == 0b_100): op_s = "DIVW"
            elif (funct3 == 0b_101): op_s = "DIVUW"
            elif (funct3 == 0b_110): op_s = "REMW"
            elif (funct3 == 0b_110): op_s = "REMUW"

        s += op_s + " " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(rs2)
        s += "    (class_MULDIV_W)"

    # ---- AMO
    elif (opcode7 == 0b_010_1111):
        op_s = "<UNKNOWN>"

        if   (funct5 == 0b_00010): op_s = "LR"
        elif (funct5 == 0b_00011): op_s = "SC"
        elif (funct5 == 0b_00001): op_s = "AMOSWAP"
        elif (funct5 == 0b_00000): op_s = "AMOADD"
        elif (funct5 == 0b_00100): op_s = "AMOXOR"
        elif (funct5 == 0b_01100): op_s = "AMOAND"
        elif (funct5 == 0b_01000): op_s = "AMOOR"
        elif (funct5 == 0b_10000): op_s = "AMOMIN"
        elif (funct5 == 0b_10100): op_s = "AMOMAX"
        elif (funct5 == 0b_11000): op_s = "AMOMINU"
        elif (funct5 == 0b_11100): op_s = "AMOMAXU"

        if   (funct3 == 0b_010): size_s = ".W"
        elif (funct3 == 0b_011): size_s = ".D"
        else: size_s = ".<UNKNOWN_size: funct3 {:d}>".format (funct3)

        
        if (op_s == "LR"):
            s += op_s + size_s + " " + r_s(rd) + " := MEM [" + r_s(rs1) + "]"
        elif (op_s == "SC"):
            s += op_s + size_s + " " + r_s(rd) + " += success/fail; MEM [" + r_s(rs1) + "] := " + r_s(rs2)
        else:
            s += op_s + size_s + " " + r_s(rd) + " := MEM [" + r_s(rs1) + "] op= " + r_s(rs2)

        s += "    (class_AMO)"

    # ---- CSSRx
    elif (opcode7 == 0b_111_0011) and ((funct3 == 1)
                                       or (funct3 == 2)
                                       or (funct3 == 3)):
        op_s = "<UNKNOWN>"
        if   (funct3 == 1): op_s = "CSRRW"
        elif (funct3 == 2): op_s = "CSRRS"
        elif (funct3 == 3): op_s = "CSRRC"

        s += op_s + " " + r_s(rd) + " := " + csr_s(imm12) + " := " + r_s(rs1)
        s += "    (class_CSRRx)"

    elif (opcode7 == 0b_111_0011) and ((funct3 == 5)
                                       or (funct3 == 6)
                                       or (funct3 == 7)):
        op_s = "<UNKNOWN>"
        if   (funct3 == 5): op = "CSRRWI"
        elif (funct3 == 6): op = "CSRRSI"
        elif (funct3 == 7): op = "CSRRCI"

        s += op_s + " " + r_s(rd) + " := " + csr_s(imm12) + " := " + x_s(rs1)
        s += "    (class_CSRRx)"

    # ---- SYSTEM
    elif (opcode7 == 0b_111_0011) and (funct3 == 0) and (rd == 0):
        op_s = "<UNKNOWN>"
        if   (imm12 == 0)                                  and (rs1 == 0): op_s = "ECALL"
        elif (imm12 == 1)                                  and (rs1 == 0): op_s = "EBREAK"
        elif (funct7 == 0b_000_0000) and (rs2 == 0b_00010) and (rs1 == 0): op_s = "URET"
        elif (funct7 == 0b_000_1000) and (rs2 == 0b_00010) and (rs1 == 0): op_s = "SRET"
        elif (funct7 == 0b_001_1000) and (rs2 == 0b_00010) and (rs1 == 0): op_s = "MRET"
        elif (funct7 == 0b_000_1000) and (rs2 == 0b_00101) and (rs1 == 0): op_s = "WFI"
        elif (funct7 == 0b_000_1001)                                     : op_s = "SFENCE.VMA"
        elif (funct7 == 0b_001_0001)                                     : op_s = "HFENCE.BVMA"
        elif (funct7 == 0b_101_0001)                                     : op_s = "HFENCE.GVMA"

        s += op_s
        if (op_s == "SFENCE.VMA") or (op_s == "HFENCE.BVMA") or (op_s == "HFENCE.GVMA"):
            s += " rs2 " + r_s(rs2) + "  rs1 " + r_s(rs1)
        s += "    (class_SYSTEM)"

    # ---- RV32F
    elif (opcode7 == 0b_000_0111) and (funct3 == 0b_010):
        op_s = "FLW " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)

    elif (opcode7 == 0b_010_0111) and (funct3 == 0b_010):
        op_s = "FSW " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(immS)

    elif (opcode7 == 0b_100_0011) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FMADD.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_0111) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FMSUB.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_1011) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FNMSUB.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_1111) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FNMADD.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_0000):
        op_s = "FADD.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_0100):
        op_s = "FSUB.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_1000):
        op_s = "FMUL.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_1100):
        op_s = "FDIV.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_010_1100) and (rs2 == 0):
        op_s = "FSQRT.S " + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0000) and (funct3 == 0b_000):
        op_s = "FSGNJ.S "  + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0000) and (funct3 == 0b_001):
        op_s = "FSGNJN.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0000) and (funct3 == 0b_010):
        op_s = "FSGNJX.S " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0100) and (funct3 == 0b_000):
        op_s = "FMIN.S "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0100) and (funct3 == 0b_001):
        op_s = "FMAX.S "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0000) and (rs2 == 0b_00000):
        op_s = "FCVT.W.S "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0000) and (rs2 == 0b_00001):
        op_s = "FCVT.WU.S "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_0000) and (rs2 == 0b_00000) and (funct3 == 0b_000):
        op_s = "FMV.X.W "   + r_s(rd) + " := " + r_s(rs1)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0000) and (funct3 == 0b_010):
        op_s = "FEQ.S "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0000) and (funct3 == 0b_001):
        op_s = "FLT.S "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0000) and (funct3 == 0b_000):
        op_s = "FLE.S "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_0000) and (rs2 == 0b_00000) and (funct3 == 0b_001):
        op_s = "FCLASS.S "   + r_s(rd) + " := " + r_s(rs1)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1000) and (rs2 == 0b_00000):
        op_s = "FCVT.S.W "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1000) and (rs2 == 0b_00001):
        op_s = "FCVT.S.WU "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_1000) and (rs2 == 0b_00000) and (funct3 == 0b_000):
        op_s = "FMV.W.X "   + r_s(rd) + " := " + r_s(rs1)

    # ---- RV64F
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0000) and (rs2 == 0b_00010):
        op_s = "FCVT.L.S "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0000) and (rs2 == 0b_00011):
        op_s = "FCVT.LU.S "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1000) and (rs2 == 0b_00010):
        op_s = "FCVT.S.L "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1000) and (rs2 == 0b_00011):
        op_s = "FCVT.S.LU "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    # ---- RV32D
    elif (opcode7 == 0b_000_0111) and (funct3 == 0b_011):
        op_s = "FLD " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(imm12)

    elif (opcode7 == 0b_010_0111) and (funct3 == 0b_011):
        op_s = "FSD " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s(immS)

    elif (opcode7 == 0b_100_0011) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FMADD.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_0111) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FMSUB.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_1011) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FNMSUB.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_100_1111) and (bitsel (instr, 26, 25) == 0b_01):
        op_s = "FNMADD.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + ", " + r_s(rs3) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_0001):
        op_s = "FADD.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_0101):
        op_s = "FSUB.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_1001):
        op_s = "FMUL.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_000_1101):
        op_s = "FDIV.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_010_1101) and (rs2 == 0):
        op_s = "FSQRT.D " + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0001) and (funct3 == 0b_000):
        op_s = "FSGNJ.D "  + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0001) and (funct3 == 0b_001):
        op_s = "FSGNJN.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0001) and (funct3 == 0b_010):
        op_s = "FSGNJX.D " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0101) and (funct3 == 0b_000):
        op_s = "FMIN.D "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_001_0101) and (funct3 == 0b_001):
        op_s = "FMAX.D "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_010_0000) and (rs2 == 0b_00001):
        op_s = "FCVT.S.D "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_010_0001) and (rs2 == 0b_00000):
        op_s = "FCVT.D.S "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0001) and (funct3 == 0b_010):
        op_s = "FEQ.D "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0001) and (funct3 == 0b_001):
        op_s = "FLT.D "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_101_0001) and (funct3 == 0b_000):
        op_s = "FLE.D "   + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_0001) and (rs2 == 0b_00000) and (funct3 == 0b_001):
        op_s = "FCLASS.D "   + r_s(rd) + " := " + r_s(rs1)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0001) and (rs2 == 0b_00000):
        op_s = "FCVT.W.D "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0001) and (rs2 == 0b_00001):
        op_s = "FCVT.WU.D "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1001) and (rs2 == 0b_00000):
        op_s = "FCVT.D.W "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1001) and (rs2 == 0b_00001):
        op_s = "FCVT.D.WU "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    # ---- RV64D
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0001) and (rs2 == 0b_00010):
        op_s = "FCVT.L.D "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_0001) and (rs2 == 0b_00011):
        op_s = "FCVT.LU.D "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_0001) and (rs2 == 0b_00000) and (funct3 == 0b_000):
        op_s = "FMV.X.D "   + r_s(rd) + " := " + r_s(rs1)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1001) and (rs2 == 0b_00010):
        op_s = "FCVT.D.L "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)
    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_110_1001) and (rs2 == 0b_00011):
        op_s = "FCVT.D.LU "   + r_s(rd) + " := " + r_s(rs1) + "; rm " + x_s(rm)

    elif (opcode7 == 0b_101_0011) and (funct7 == 0b_111_1001) and (rs2 == 0b_00000) and (funct3 == 0b_000):
        op_s = "FMV.D.X "   + r_s(rd) + " := " + r_s(rs1)

    # ---- UNKNOWN
    else:
        s += "<UNKNOWN>    (class_UNKNOWN)"

    return s

# ================================================================

def disasm_16b_instr (xlen, instr):
    if ((instr >> 16) != 0):
        return "[ERROR: 'instr' is > 16 bits: {:_x}]".format (instr)

    s = ""

    quadrant  = bitsel (instr,  1,  0)
    funct3    = bitsel (instr, 15, 13)

    # ----------------------------------------------------------------
    # QUADRANT 1

    if (quadrant == 0b_00):
        rd_prime  = bitsel (instr,  4,  2)
        rd        = rd_prime + 8
        rs2_prime = bitsel (instr,  4,  2)
        rs2       = rs2_prime + 8
        rs1_prime = bitsel (instr,  9,  7)
        rs1       = rs1_prime + 8

        if (bitsel (instr, 15, 2) == 0): op_s = "ILLEGAL_INSTR"

        elif (funct3 == 0b_000):
            nzuimm    = ((  bitsel (instr,  5,  5) << 3)
                         | (bitsel (instr,  6,  6) << 2)
                         | (bitsel (instr, 10,  7) << 6)
                         | (bitsel (instr, 12, 11) << 4))
            s += "C.ADDI4SPN " + r_s (rd) + " := " + x_s (nzuimm)

        elif (funct3 == 0b_001) and ((xlen == 32) or (xlen == 64)):
            uimm    = ((  bitsel (instr,  6,  5) << 6)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.FLD " + r_s (rd) + " := " + r_s (rs1) + ", " + x_s (uimm)

        elif (funct3 == 0b_001) and (xlen == 128):
            uimm    = ((  bitsel (instr,  6,  5) << 6)
                       | (bitsel (instr, 10, 10) << 8)
                       | (bitsel (instr, 12, 11) << 4))
            s += "C.LQ " + r_s (rd) + " := " + r_s (rs1) + ", " + x_s (uimm)

        elif (funct3 == 0b_010):
            uimm    = ((  bitsel (instr,  5,  5) << 6)
                       | (bitsel (instr,  6,  6) << 2)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.LW " + r_s (rd) + " := " + r_s (rs1) + ", " + x_s (uimm)

        elif (funct3 == 0b_011) and (xlen == 32):
            uimm    = ((  bitsel (instr,  5,  5) << 6)
                       | (bitsel (instr,  6,  6) << 2)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.FLW " + r_s (rd) + " := " + r_s (rs1) + ", " + x_s (uimm)

        elif (funct3 == 0b_011) and ((xlen == 64) or (xlen == 128)):
            uimm    = ((  bitsel (instr,  5,  5) << 6)
                       | (bitsel (instr,  6,  6) << 7)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.LD " + r_s (rd) + " := " + r_s (rs1) + ", " + x_s (uimm)

        elif (funct3 == 0b_101) and ((xlen == 32) or (xlen == 64)):
            uimm    = ((  bitsel (instr,  6,  5) << 6)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.FSD MEM [" + r_s (rs1) + " + " + x_s (uimm) + "] := " + r_s (rs2)

        elif (funct3 == 0b_101) and (xlen == 128):
            uimm    = ((  bitsel (instr,  6,  5) << 6)
                       | (bitsel (instr, 10, 10) << 8)
                       | (bitsel (instr, 12, 11) << 4))
            s += "C.SQ MEM [" + r_s (rs1) + " + " + x_s (uimm) + "] := " + r_s (rs2)

        elif (funct3 == 0b_110):
            uimm    = ((  bitsel (instr,  5,  5) << 6)
                       | (bitsel (instr,  6,  6) << 2)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.SW MEM [" + r_s (rs1) + " + " + x_s (uimm) + "] := " + r_s (rs2)

        elif (funct3 == 0b_111) and (xlen == 32):
            uimm    = ((  bitsel (instr,  5,  5) << 6)
                       | (bitsel (instr,  6,  6) << 2)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.FSW MEM [" + r_s (rs1) + " + " + x_s (uimm) + "] := " + r_s (rs2)

        elif (funct3 == 0b_111) and ((xlen == 64) or (xlen == 128)):
            uimm    = ((  bitsel (instr,  6,  5) << 6)
                       | (bitsel (instr, 12, 10) << 3))
            s += "C.SD MEM [" + r_s (rs1) + " + " + x_s (uimm) + "] := " + r_s (rs2)

        else:
            s += "<UNKNOWN>"

        s += "    (Quadrant_0)"

    # ----------------------------------------------------------------
    # QUADRANT 1

    elif (quadrant == 0b_01):
        rd        = bitsel (instr, 11, 7)
        rs1       = bitsel (instr, 11, 7)
        rd_prime  = bitsel (instr,  9, 7)
        rs1_prime = bitsel (instr,  9, 7)
        rs2_prime = bitsel (instr,  4, 2)

        if (funct3 == 0b_000):
            nzimm =  ((  bitsel (instr, 12, 12) << 5)
                      | (bitsel (instr,  6,  2) << 0))
            if (rd == 0):
                s += "C.NOP"
                if (nzimm != 0): s += "  (HINT)"
            else:
                s += "C.ADDI " + r_s(rd) + " := " + r_s(rs1) + " + " + x_s (nzimm)
                if (nzimm == 0): s += "  (HINT)"

        elif (funct3 == 0b_001) and (xlen == 32):
            imm = ((  bitsel (instr,  2,  2) <<  5)
                   | (bitsel (instr,  5,  3) <<  1)
                   | (bitsel (instr,  6,  6) <<  7)
                   | (bitsel (instr,  7,  7) <<  6)
                   | (bitsel (instr,  8,  8) << 10)
                   | (bitsel (instr, 10,  9) <<  8)
                   | (bitsel (instr, 11, 11) <<  4)
                   | (bitsel (instr, 12, 12) << 11))
            s += "C.JAL PC + " + x_s (imm)

        elif (funct3 == 0b_001) and ((xlen == 64) or (xlen == 128)) and (rd != 0):
            imm = ((  bitsel (instr,  6,  2) <<  0)
                   | (bitsel (instr, 12, 12) <<  5))
            s += "C.ADDIW " + r_s (rd) + " := " + r_s (rs1) + " + " + x_s (imm)

        elif (funct3 == 0b_010):
            imm = ((  bitsel (instr,  6,  2) <<  0)
                   | (bitsel (instr, 12, 12) <<  5))
            s += "C.LI " + r_s (rd) + " := " + x_s (imm)
            if (rd == 0): s += "  (HINT)"

        elif (funct3 == 0b_011):
            if (rd == 2):
                nzimm = ((  bitsel (instr,  2,  2) << 5)
                         | (bitsel (instr,  4,  3) << 7)
                         | (bitsel (instr,  5,  5) << 6)
                         | (bitsel (instr,  6,  6) << 4)
                         | (bitsel (instr, 12, 12) << 9))
                s += "C.ADDI16SP " + x_s (nzimm)
                if (nzimm != 0): s += " (RESERVED)"

            else:
                nzimm = ((  bitsel (instr,  6,  2) << 12)
                         | (bitsel (instr, 12, 12) << 17))
                s += "C.LUI " + r_s (rd) + " := " + x_s (nzimm)
                if (nzimm == 0): s += " (RESERVED)"
                if (rd == 0):    s += " (HINT)"

        elif (funct3 == 0b_100):
            nzuimm   = ((  bitsel (instr,  6,  2) << 0)
                        | (bitsel (instr, 12, 12) << 5))
            nzuimm5  = bitsel (instr, 12, 12)
            op_hi    = bitsel (instr, 11, 10)
            op_lo    = bitsel (instr,  6,  5)
            if (op_hi == 0b_00):
                if (nzuimm5 != 0):
                    s += "C.SRLI " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + " by " + x_s (nzuimm)
                    if (xlen == 32) and (nzuimm5 == 1): s += "  (RV32 Non_Std_Extn)"
                else:
                    s += "C.SRLI64 " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime)
                    if (xlen == 32) or (xlen == 64): s += "  (HINT)"
            elif (op_hi == 0b_01):
                if (nzuimm5 != 0):
                    s += "C.SRAI " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + " by " + x_s (nzuimm)
                    if (xlen == 32) and (nzuimm5 == 1): s += "  (RV32 Non_Std_Extn)"
                else:
                    s += "C.SRAI64 " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime)
                    if (xlen == 32) or (xlen == 64): s += "  (HINT)"
            elif (op_hi == 0b_10):
                s += "C.ANDI " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + x_s (nzuimm)

            elif (nzuimm5 == 0) and (op_hi == 0b_11) and (op_lo == 0b_00):
                s += "C.SUB " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
            elif (nzuimm5 == 0) and (op_hi == 0b_11) and (op_lo == 0b_01):
                s += "C.XOR " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
            elif (nzuimm5 == 0) and (op_hi == 0b_11) and (op_lo == 0b_10):
                s += "C.OR " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
            elif (nzuimm5 == 0) and (op_hi == 0b_11) and (op_lo == 0b_11):
                s += "C.AND " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
            elif (nzuimm5 == 1) and (op_hi == 0b_11) and (op_lo == 0b_00):
                s += "C.SUBW " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
                if (xlen == 32): s += "  (RESERVED)"
            elif (nzuimm5 == 1) and (op_hi == 0b_11) and (op_lo == 0b_01):
                s += "C.ADDW " + rprime_s (rd_prime) + " := " + rprime_s (rs1_prime) + ", " + rprime_s (rs2_prime)
                if (xlen == 32): s += "  (RESERVED)"
            elif (nzuimm5 == 1) and (op_hi == 0b_11) and (op_lo == 0b_10):
                s += "(RESERVED)"
            elif (nzuimm5 == 1) and (op_hi == 0b_11) and (op_lo == 0b_11):
                s += "(RESERVED)"
            else:
                s += "<UNKNOWN>"

        elif (funct3 == 0b_101):
            imm = ((  bitsel (instr,  2,  2) <<  5)
                   | (bitsel (instr,  5,  3) <<  1)
                   | (bitsel (instr,  6,  6) <<  7)
                   | (bitsel (instr,  7,  7) <<  6)
                   | (bitsel (instr,  8,  8) << 10)
                   | (bitsel (instr, 10,  9) <<  8)
                   | (bitsel (instr, 11, 11) <<  4)
                   | (bitsel (instr, 12, 12) << 11))
            s += "C.J PC + " + x_s (imm)

        elif (funct3 == 0b_110):
            imm = ((  bitsel (instr,  2,  2) <<  5)
                   | (bitsel (instr,  4,  3) <<  1)
                   | (bitsel (instr,  6,  5) <<  6)
                   | (bitsel (instr, 11, 10) <<  3)
                   | (bitsel (instr, 12, 12) <<  8))
            s += "C.BEQZ PC + " + x_s (imm)

        elif (funct3 == 0b_111):
            imm = ((  bitsel (instr,  2,  2) <<  5)
                   | (bitsel (instr,  4,  3) <<  1)
                   | (bitsel (instr,  6,  5) <<  6)
                   | (bitsel (instr, 11, 10) <<  3)
                   | (bitsel (instr, 12, 12) <<  8))
            s += "C.BNEZ PC + " + x_s (imm)

        else:
            s += "<UNKNOWN>"

        s += "    (Quadrant_1)"

    # ----------------------------------------------------------------
    # QUADRANT 2

    elif (quadrant == 0b_10):
        rd      = bitsel (instr, 11, 7)
        rs1     = bitsel (instr, 11, 7)
        rs2     = bitsel (instr,  6, 2)
        nzuimm5 = bitsel (instr, 12, 12)

        if (funct3 == 0b_000):
            nzuimm = ((  bitsel (instr,  6,  2) <<  0)
                      | (bitsel (instr, 12, 12) <<  5))
            if (nzuimm != 0):
                s += "C.SLLI " + r_s(rd) + " := " + r_s(rs1) + ", " + x_s (nzuimm)
                if (rd == 0): s += "  (HINT)"
                if (xlen == 32) and (nzuimm5 == 1): s += "  (Non_Std_Extn)"

            else:
                s += "C.SLLI64 " + r_s(rd) + " := " + r_s(rs1)
                if (xlen == 32) or (xlen == 64) or (rd == 0): s += "  (HINT)"

        elif (funct3 == 0b_001):
            uimm = ((  bitsel (instr,  4,  2) <<  6)
                    | (bitsel (instr,  6,  5) <<  3)
                    | (bitsel (instr, 12, 12) <<  5))
            if (xlen == 32) or (xlen == 64):
                s += "C.FLDSP " + r_s(rd) + " := " + x_s(uimm)
            else:
                s += "C.FLQSP " + r_s(rd) + " := " + x_s(uimm)
                if (rd == 0): s += "  (RESERVED)"

        elif (funct3 == 0b_010):
            uimm = ((  bitsel (instr,  3,  2) <<  6)
                    | (bitsel (instr,  6,  4) <<  2)
                    | (bitsel (instr, 12, 12) <<  5))
            s += "C.LWSP " + r_s(rd) + " := " + x_s (uimm)
            if (rd == 0): s+= "  (RESERVED)"

        elif (funct3 == 0b_011):
            if (xlen == 32):
                uimm = ((  bitsel (instr,  3,  2) <<  6)
                        | (bitsel (instr,  6,  4) <<  2)
                        | (bitsel (instr, 12, 12) <<  5))
                s += "C.FLWSP " + r_s(rd) + " := " + x_s (uimm)

            elif (xlen == 64) or (xlen == 128):
                uimm = ((  bitsel (instr,  4,  2) <<  6)
                        | (bitsel (instr,  6,  5) <<  3)
                        | (bitsel (instr, 12, 12) <<  5))
                s += "C.LDSP " + r_s(rd) + " := " + x_s (uimm)
                if (rd == 0): s+= "  (RESERVED)"
            else:
                s += "<UNKNOWN>"

        elif (funct3 == 0b_100):
            if (nzuimm5 == 0) and (rs2 == 0):
                s += "C.JR " + r_s(rs1)
                if (rs1 == 0): s += "  (RESERVED)"

            elif (nzuimm5 == 0) and (rs2 != 0):
                s += "C.MV " + r_s(rd) + " := " + r_s(rs1)
                if (rd == 0): s += "  (HINT)"
            elif (nzuimm5 == 1) and (rd == 0) and (rs2 != 0):
                s += "C.EBREAK"
            elif (nzuimm5 == 1) and (rs1 != 0) and (rs2 == 0):
                s += "C.JALR"
            elif (nzuimm5 == 1) and (rs2 != 0):
                s += "C.ADD " + r_s(rd) + " := " + r_s(rs1) + ", " + r_s(rs2)
                if (rd == 0): s += "  (HINT)"
            else:
                s += "<UNKNOWN>"

        elif (funct3 == 0b_101):
            if (xlen == 32) or (xlen == 64):
                uimm = ((  bitsel (instr,  9,  7) << 6)
                        | (bitsel (instr, 12, 10) << 3))
                s += "C.FSDSP " + r_s(rs2) + ", " + x_s (uimm)
            elif (xlen == 128):
                uimm = ((  bitsel (instr, 10,  7) << 6)
                        | (bitsel (instr, 12, 11) << 4))
                s += "C.SQSP " + r_s(rs2) + ", " + x_s (uimm)
            else:
                s += "<UNKNOWN>"

        elif (funct3 == 0b_110):
            uimm = ((  bitsel (instr,  8,  7) << 6)
                    | (bitsel (instr, 12,  9) << 2))
            s += "C.SWSP " + r_s(rs2) + ", " + x_s(uimm)

        elif (funct3 == 0b_111):
            if (xlen == 32):
                uimm = ((  bitsel (instr,  8,  7) << 6)
                        | (bitsel (instr, 12,  9) << 2))
                s += "C.FSWSP " + r_s(rs2) + ", " + x_s(uimm)
            elif (xlen == 64) or (xlen == 128):
                uimm = ((  bitsel (instr,  9,  7) << 6)
                        | (bitsel (instr, 12, 10) << 3))
                s += "C.SDSP " + r_s(rs2) + ", " + x_s(uimm)
            else:
                s += "<UNKNOWN>"

        else:
            s += "<UNKNOWN>"
        
        s += "    (Quadrant_2)"
    return s

# ================================================================
# Utils

# Bit-selection (like verilog x [hi:lo])

def bitsel (x, hi, lo):
    mask = ((1 << (hi +1 - lo)) - 1)
    return (x >> lo) & mask

# Hex string

def x_s (x):
    return "{:_x}".format (x)

# Decimal string

def x_d (x):
    return "{:_d}".format (x)

# Hex and decimal string

def xd_s (x):
    return "{:_x} ({:d})".format (x, x)

# Register name

def r_s (r):
    if   (r == 0): s = "zero"
    elif (r == 1): s = "ra"
    elif (r == 2): s = "sp"
    elif (r == 3): s = "gp"
    elif (r == 4): s = "tp"

    elif (r == 5): s = "t0"
    elif (r == 6): s = "t1"
    elif (r <= 7): s = "t7"

    elif (r == 8): s = "s0/fp"
    elif (r == 9): s = "s1"

    elif (r == 10): s = "a0"
    elif (r == 11): s = "a1"
    elif (r == 12): s = "a2"
    elif (r == 13): s = "a3"
    elif (r == 14): s = "a4"
    elif (r == 15): s = "a5"
    elif (r == 16): s = "a6"
    elif (r == 17): s = "a7"

    elif (r == 18): s = "s2"
    elif (r == 19): s = "s3"
    elif (r == 20): s = "s4"
    elif (r == 21): s = "s5"
    elif (r == 22): s = "s6"
    elif (r == 23): s = "s7"
    elif (r == 24): s = "s8"
    elif (r == 25): s = "s9"
    elif (r == 26): s = "s10"
    elif (r == 27): s = "s11"

    elif (r == 28): s = "t3"
    elif (r == 29): s = "t4"
    elif (r == 30): s = "t5"
    elif (r == 31): s = "t6"
    else:           s = "<UNKNOWN>"

    s += "(x{:d})".format (r)

    return s

# Compressed register-prime name
def rprime_s (r_prime):
    return r_s (r_prime + 8)

# CSR name

def csr_s (csr):
    if   (csr == 0x_000): s = "ustatus "
    elif (csr == 0x_004): s = "uie "
    elif (csr == 0x_005): s = "utvec "

    elif (csr == 0x_040): s = "uscratch "
    elif (csr == 0x_041): s = "uepc "
    elif (csr == 0x_042): s = "ucause "
    elif (csr == 0x_043): s = "utval "
    elif (csr == 0x_044): s = "uip "

    elif (csr == 0x_001): s = "fflags "
    elif (csr == 0x_002): s = "frm "
    elif (csr == 0x_003): s = "fcsr "

    elif (csr == 0x_C00): s = "cycle "
    elif (csr == 0x_C01): s = "time "
    elif (csr == 0x_C02): s = "instret "
    elif (csr == 0x_C03): s = "hpmcounter3 "
    elif (csr == 0x_C04): s = "hpmcounter4 "
    elif (csr == 0x_C05): s = "hpmcounter5 "
    elif (csr == 0x_C06): s = "hpmcounter6 "
    elif (csr == 0x_C07): s = "hpmcounter7 "
    elif (csr == 0x_C08): s = "hpmcounter8 "
    elif (csr == 0x_C09): s = "hpmcounter9 "
    elif (csr == 0x_C0A): s = "hpmcounter10 "
    elif (csr == 0x_C0B): s = "hpmcounter11 "
    elif (csr == 0x_C0C): s = "hpmcounter12 "
    elif (csr == 0x_C0D): s = "hpmcounter13 "
    elif (csr == 0x_C0E): s = "hpmcounter14 "
    elif (csr == 0x_C0F): s = "hpmcounter15 "
    elif (csr == 0x_C10): s = "hpmcounter16 "
    elif (csr == 0x_C11): s = "hpmcounter17 "
    elif (csr == 0x_C12): s = "hpmcounter18 "
    elif (csr == 0x_C13): s = "hpmcounter19 "
    elif (csr == 0x_C14): s = "hpmcounter20 "
    elif (csr == 0x_C15): s = "hpmcounter21 "
    elif (csr == 0x_C16): s = "hpmcounter22 "
    elif (csr == 0x_C17): s = "hpmcounter23 "
    elif (csr == 0x_C18): s = "hpmcounter24 "
    elif (csr == 0x_C19): s = "hpmcounter25 "
    elif (csr == 0x_C1A): s = "hpmcounter26 "
    elif (csr == 0x_C1B): s = "hpmcounter27 "
    elif (csr == 0x_C1C): s = "hpmcounter28 "
    elif (csr == 0x_C1D): s = "hpmcounter29 "
    elif (csr == 0x_C1E): s = "hpmcounter30 "
    elif (csr == 0x_C1F): s = "hpmcounter31 "

    elif (csr == 0x_C80): s = "cycleh "
    elif (csr == 0x_C81): s = "timeh "
    elif (csr == 0x_C82): s = "instreth "
    elif (csr == 0x_C83): s = "hpmcounter3h "
    elif (csr == 0x_C84): s = "hpmcounter4h "
    elif (csr == 0x_C85): s = "hpmcounter5h "
    elif (csr == 0x_C86): s = "hpmcounter6h "
    elif (csr == 0x_C87): s = "hpmcounter7h "
    elif (csr == 0x_C88): s = "hpmcounter8h "
    elif (csr == 0x_C89): s = "hpmcounter9h "
    elif (csr == 0x_C8A): s = "hpmcounter10h "
    elif (csr == 0x_C8B): s = "hpmcounter11h "
    elif (csr == 0x_C8C): s = "hpmcounter12h "
    elif (csr == 0x_C8D): s = "hpmcounter13h "
    elif (csr == 0x_C8E): s = "hpmcounter14h "
    elif (csr == 0x_C8F): s = "hpmcounter15h "
    elif (csr == 0x_C90): s = "hpmcounter16h "
    elif (csr == 0x_C91): s = "hpmcounter17h "
    elif (csr == 0x_C92): s = "hpmcounter18h "
    elif (csr == 0x_C93): s = "hpmcounter19h "
    elif (csr == 0x_C94): s = "hpmcounter20h "
    elif (csr == 0x_C95): s = "hpmcounter21h "
    elif (csr == 0x_C96): s = "hpmcounter22h "
    elif (csr == 0x_C97): s = "hpmcounter23h "
    elif (csr == 0x_C98): s = "hpmcounter24h "
    elif (csr == 0x_C99): s = "hpmcounter25h "
    elif (csr == 0x_C9A): s = "hpmcounter26h "
    elif (csr == 0x_C9B): s = "hpmcounter27h "
    elif (csr == 0x_C9C): s = "hpmcounter28h "
    elif (csr == 0x_C9D): s = "hpmcounter29h "
    elif (csr == 0x_C9E): s = "hpmcounter30h "
    elif (csr == 0x_C9F): s = "hpmcounter31h "

    elif (csr == 0x_100): s = "sstatus "
    elif (csr == 0x_102): s = "sedeleg "
    elif (csr == 0x_103): s = "sideleg "
    elif (csr == 0x_104): s = "sie "
    elif (csr == 0x_105): s = "stvec "
    elif (csr == 0x_106): s = "scounteren "

    elif (csr == 0x_140): s = "sscratch "
    elif (csr == 0x_141): s = "sepc "
    elif (csr == 0x_142): s = "scause "
    elif (csr == 0x_143): s = "stval "
    elif (csr == 0x_144): s = "sip "

    elif (csr == 0x_180): s = "satp "

    elif (csr == 0x_A00): s = "hstatus "
    elif (csr == 0x_A02): s = "hedeleg "
    elif (csr == 0x_A03): s = "hideleg "

    elif (csr == 0x_A80): s = "hgatp "

    elif (csr == 0x_200): s = "bsstatus "
    elif (csr == 0x_204): s = "bsie "
    elif (csr == 0x_205): s = "bstvec "
    elif (csr == 0x_240): s = "bsscratch "
    elif (csr == 0x_241): s = "bsepc "
    elif (csr == 0x_242): s = "bscause "
    elif (csr == 0x_243): s = "bstval "
    elif (csr == 0x_244): s = "bsip "
    elif (csr == 0x_280): s = "bsatp "

    elif (csr == 0x_F11): s = "mvendorid "
    elif (csr == 0x_F12): s = "marchid "
    elif (csr == 0x_F13): s = "mimpid "
    elif (csr == 0x_F14): s = "mhartid "

    elif (csr == 0x_300): s = "mstatus "
    elif (csr == 0x_301): s = "misa "
    elif (csr == 0x_302): s = "medeleg "
    elif (csr == 0x_303): s = "mideleg "
    elif (csr == 0x_304): s = "mie "
    elif (csr == 0x_305): s = "mtvec "
    elif (csr == 0x_306): s = "mcounteren "

    elif (csr == 0x_340): s = "mscratch "
    elif (csr == 0x_341): s = "mepc "
    elif (csr == 0x_342): s = "mcause "
    elif (csr == 0x_343): s = "mtval "
    elif (csr == 0x_344): s = "mip "

    elif (csr == 0x_3A0): s = "pmpcfg0 "
    elif (csr == 0x_3A1): s = "pmpcfg1 "
    elif (csr == 0x_3A2): s = "pmpcfg2 "
    elif (csr == 0x_3A3): s = "pmpcfg3 "

    elif (csr == 0x_3B0): s = "pmpaddr0 "
    elif (csr == 0x_3B1): s = "pmpaddr1 "
    elif (csr == 0x_3B2): s = "pmpaddr2 "
    elif (csr == 0x_3B3): s = "pmpaddr3 "
    elif (csr == 0x_3B4): s = "pmpaddr4 "
    elif (csr == 0x_3B5): s = "pmpaddr5 "
    elif (csr == 0x_3B6): s = "pmpaddr6 "
    elif (csr == 0x_3B7): s = "pmpaddr7 "
    elif (csr == 0x_3B8): s = "pmpaddr8 "
    elif (csr == 0x_3B9): s = "pmpaddr9 "
    elif (csr == 0x_3BA): s = "pmpaddr10 "
    elif (csr == 0x_3BB): s = "pmpaddr11 "
    elif (csr == 0x_3BC): s = "pmpaddr12 "
    elif (csr == 0x_3BD): s = "pmpaddr13 "
    elif (csr == 0x_3BE): s = "pmpaddr14 "
    elif (csr == 0x_3BF): s = "pmpaddr15 "

    elif (csr == 0x_B00): s = "mcycle "
    elif (csr == 0x_B02): s = "minstret "
    elif (csr == 0x_B03): s = "mhpmcounter3 "
    elif (csr == 0x_B04): s = "mhpmcounter4 "
    elif (csr == 0x_B05): s = "mhpmcounter5 "
    elif (csr == 0x_B06): s = "mhpmcounter6 "
    elif (csr == 0x_B07): s = "mhpmcounter7 "
    elif (csr == 0x_B08): s = "mhpmcounter8 "
    elif (csr == 0x_B09): s = "mhpmcounter9 "
    elif (csr == 0x_B0A): s = "mhpmcounter10 "
    elif (csr == 0x_B0B): s = "mhpmcounter11 "
    elif (csr == 0x_B0C): s = "mhpmcounter12 "
    elif (csr == 0x_B0D): s = "mhpmcounter13 "
    elif (csr == 0x_B0E): s = "mhpmcounter14 "
    elif (csr == 0x_B0F): s = "mhpmcounter15 "
    elif (csr == 0x_B10): s = "mhpmcounter16 "
    elif (csr == 0x_B11): s = "mhpmcounter17 "
    elif (csr == 0x_B12): s = "mhpmcounter18 "
    elif (csr == 0x_B13): s = "mhpmcounter19 "
    elif (csr == 0x_B14): s = "mhpmcounter20 "
    elif (csr == 0x_B15): s = "mhpmcounter21 "
    elif (csr == 0x_B16): s = "mhpmcounter22 "
    elif (csr == 0x_B17): s = "mhpmcounter23 "
    elif (csr == 0x_B18): s = "mhpmcounter24 "
    elif (csr == 0x_B19): s = "mhpmcounter25 "
    elif (csr == 0x_B1A): s = "mhpmcounter26 "
    elif (csr == 0x_B1B): s = "mhpmcounter27 "
    elif (csr == 0x_B1C): s = "mhpmcounter28 "
    elif (csr == 0x_B1D): s = "mhpmcounter29 "
    elif (csr == 0x_B1E): s = "mhpmcounter30 "
    elif (csr == 0x_B1F): s = "mhpmcounter31 "

    elif (csr == 0x_B80): s = "mcycleh "
    elif (csr == 0x_B82): s = "minstreth "
    elif (csr == 0x_B83): s = "mhpmcounter3h "
    elif (csr == 0x_B84): s = "mhpmcounter4h "
    elif (csr == 0x_B85): s = "mhpmcounter5h "
    elif (csr == 0x_B86): s = "mhpmcounter6h "
    elif (csr == 0x_B87): s = "mhpmcounter7h "
    elif (csr == 0x_B88): s = "mhpmcounter8h "
    elif (csr == 0x_B89): s = "mhpmcounter9h "
    elif (csr == 0x_B8A): s = "mhpmcounter10h "
    elif (csr == 0x_B8B): s = "mhpmcounter11h "
    elif (csr == 0x_B8C): s = "mhpmcounter12h "
    elif (csr == 0x_B8D): s = "mhpmcounter13h "
    elif (csr == 0x_B8E): s = "mhpmcounter14h "
    elif (csr == 0x_B8F): s = "mhpmcounter15h "
    elif (csr == 0x_B90): s = "mhpmcounter16h "
    elif (csr == 0x_B91): s = "mhpmcounter17h "
    elif (csr == 0x_B92): s = "mhpmcounter18h "
    elif (csr == 0x_B93): s = "mhpmcounter19h "
    elif (csr == 0x_B94): s = "mhpmcounter20h "
    elif (csr == 0x_B95): s = "mhpmcounter21h "
    elif (csr == 0x_B96): s = "mhpmcounter22h "
    elif (csr == 0x_B97): s = "mhpmcounter23h "
    elif (csr == 0x_B98): s = "mhpmcounter24h "
    elif (csr == 0x_B99): s = "mhpmcounter25h "
    elif (csr == 0x_B9A): s = "mhpmcounter26h "
    elif (csr == 0x_B9B): s = "mhpmcounter27h "
    elif (csr == 0x_B9C): s = "mhpmcounter28h "
    elif (csr == 0x_B9D): s = "mhpmcounter29h "
    elif (csr == 0x_B9E): s = "mhpmcounter30h "
    elif (csr == 0x_B9F): s = "mhpmcounter31h "

    elif (csr == 0x_320): s = "mcountinhibit "
    elif (csr == 0x_323): s = "mhpmevent3 "
    elif (csr == 0x_324): s = "mhpmevent4 "
    elif (csr == 0x_325): s = "mhpmevent5 "
    elif (csr == 0x_326): s = "mhpmevent6 "
    elif (csr == 0x_327): s = "mhpmevent7 "
    elif (csr == 0x_328): s = "mhpmevent8 "
    elif (csr == 0x_329): s = "mhpmevent9 "
    elif (csr == 0x_32A): s = "mhpmevent10 "
    elif (csr == 0x_32B): s = "mhpmevent11 "
    elif (csr == 0x_32C): s = "mhpmevent12 "
    elif (csr == 0x_32D): s = "mhpmevent13 "
    elif (csr == 0x_32E): s = "mhpmevent14 "
    elif (csr == 0x_32F): s = "mhpmevent15 "
    elif (csr == 0x_330): s = "mhpmevent16 "
    elif (csr == 0x_331): s = "mhpmevent17 "
    elif (csr == 0x_332): s = "mhpmevent18 "
    elif (csr == 0x_333): s = "mhpmevent19 "
    elif (csr == 0x_334): s = "mhpmevent20 "
    elif (csr == 0x_335): s = "mhpmevent21 "
    elif (csr == 0x_336): s = "mhpmevent22 "
    elif (csr == 0x_337): s = "mhpmevent23 "
    elif (csr == 0x_338): s = "mhpmevent24 "
    elif (csr == 0x_339): s = "mhpmevent25 "
    elif (csr == 0x_33A): s = "mhpmevent26 "
    elif (csr == 0x_33B): s = "mhpmevent27 "
    elif (csr == 0x_33C): s = "mhpmevent28 "
    elif (csr == 0x_33D): s = "mhpmevent29 "
    elif (csr == 0x_33E): s = "mhpmevent30 "
    elif (csr == 0x_33F): s = "mhpmevent31 "

    elif (csr == 0x_7A0): s = "tselect "
    elif (csr == 0x_7A1): s = "tdata1 "
    elif (csr == 0x_7A2): s = "tdata2 "
    elif (csr == 0x_7A3): s = "tdata3 "

    elif (csr == 0x_7B0): s = "dcsr "
    elif (csr == 0x_7B1): s = "dpc "
    elif (csr == 0x_7B2): s = "dscratch0 "
    elif (csr == 0x_7B3): s = "dscratch1 "

    else:                 s = ""

    s += "(csr {:x})".format (csr)
    return s

# ================================================================
