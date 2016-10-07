import re
import parse
import vex

class FU:
    ALU = 1
    MUL = 2
    MEM = 4
    BR = 8

def parse_instruction(line, comment="", line_no=0):
    cluster, line2 = parse.get_cluster(line)
    mnemonic, line2 = parse.get_mnemonic(line2)
    if not mnemonic:
        print("Error parsing line {}\n".format(line_no))
        print(line)
        exit(1)
    if re.search(r"br[f]?", mnemonic):
        return BranchInstruction(line, comment, line_no)
    elif re.search(r"return", mnemonic):
        return ReturnInstruction(line, comment, line_no)
    elif re.search(r"rfi", mnemonic):
        return ReturnInstruction(line, comment, line_no)
    elif re.search(r"goto", mnemonic):
        return GotoInstruction(line, comment, line_no)
    elif re.search(r"call", mnemonic):
        return CallInstruction(line, comment, line_no)
    elif re.search(r"mpy", mnemonic):
        return MulInstruction(line, comment, line_no)
    elif parse.is_store(mnemonic):
        return StoreInstruction(line, comment, line_no)
    elif parse.is_load(mnemonic):
        return LoadInstruction(line, comment, line_no)
    elif parse.is_stop(mnemonic):
        return StopInstruction(line, comment, line_no)
    else:
        return Instruction(line, comment, line_no)

class Instruction:
    """Object for holding and parsing VEX instructions.
    """

    def __eq__(self, other):
        if not isinstance(other, Instruction):
            return False
        return str(self) == str(other)

    def get_fu(self):
        return FU.ALU

    def change_source_reg(self, orig, new):
        self.srcs = [new if arg == orig else arg for arg in self.srcs]

    def change_dest_reg(self, orig, new):
        self.dests = [new if arg == orig else arg for arg in self.dests]

    def is_branch(self):
        return False

    def is_call(self):
        return False

    def is_return(self):
        return False

    def get_branch_destination(self):
        """Return the branch destination of this instruction"""
        return ["next"]

    def get_written_registers(self):
        return {x for x in self.dests
                if isinstance(x, vex.Register)}

    def get_read_registers(self):
        return {x for x in self.srcs if isinstance(x, vex.Register)}

    def parse_args(self, args):
        dest = True
        for arg in [x.strip() for x in args]:
            if arg == "," or arg == '[' or arg == ']' or arg == '':
                continue
            if arg == '=':
                dest = False
                continue
            if parse.is_register(arg):
                arg = vex.parse_register(arg)
            if dest:
                self.dests.append(arg)
            else:
                self.srcs.append(arg)
    def cost(self):
        return 1

    def arg_is_long_imm(self, arg):
        if isinstance(arg, vex.Register):
            return False
        try:
            a = eval(arg, {"__builtins__":None}, None)
            if a > 255 or a < -256:
                return True
            else:
                return False
        except:
            return True

    def has_long_imm(self):
        return self.has_long

    def __init__(self, line, comment, line_no):
        self.dests = []
        self.srcs = []
        tokens = re.split(r'(?:,\s*)|\s+', line.strip())
        if not parse.get_cluster(line):
            print(line, file=sys.stderr)
        self.cluster, line = parse.get_cluster(line)
        self.mnemonic, line = parse.get_mnemonic(line)
        self.parse_args(re.split(r"([,=\[\]])", line))
        self.has_long = any(self.arg_is_long_imm(arg) for arg in self.srcs)
        self.comment = comment
        self.line_no = line_no
        self.pseudo_op = None

    def __str__(self):
        string = ''
        if self.pseudo_op:
            string = self.pseudo_op + '\n'
        string += "c{0} {1} ".format(self.cluster, self.mnemonic)
        string += ', '.join(str(x) for x in self.dests)
        if len(self.dests) > 0:
            string += ' = '
        if len(self.srcs) > 0:
            string += ', '.join(str(x) for x in self.srcs)
        if self.comment:
            string += ' #' + self.comment
        return string

    def __repr__(self):
        return "{0}('{1}')".format(self.__class__.__name__, str(self))

class MulInstruction(Instruction):

    def get_fu(self):
        return FU.MUL

    def cost(self):
        return 2

class ControlInstruction(Instruction):

    def has_long_imm(self):
        return False

    def is_branch(self):
        return True

    def get_fu(self):
        return FU.BR

class CallInstruction(ControlInstruction):

    def is_call(self):
        return True

class BranchInstruction(ControlInstruction):

    def get_branch_destination(self):
        """Return the branch destination of this instruction"""
        return ["next", self.srcs[-1]]

    def parse_args(self, args):
        for arg in [x.strip() for x in args]:
            if (arg == "," or arg == '[' or arg == ']' or
                arg == '' or arg == '='):
                continue
            if parse.is_register(arg):
                arg = vex.parse_register(arg)
            self.srcs.append(arg)

    def __str__(self):
        string = "c{0} {1} ".format(self.cluster, self.mnemonic)
        string += ", ".join(str(x) for x in self.srcs)
        return string

class ReturnInstruction(ControlInstruction):

    def get_written_registers(self):
        if len(self.dests) == 0:
            return {vex.GeneralRegister(0, 1)}
        else:
            return super().get_written_registers()

    def get_read_registers(self):
        regs = super().get_read_registers()
        if len(self.srcs) == 1:
            regs.add(vex.GeneralRegister(0,1))
        return regs

    def is_return(self):
        return True

    def get_branch_destination(self):
        """Return the branch destination of this instruction"""
        return ["return"]

    def parse_args(self, args):
        super().parse_args(args)
        if len(args) == 1:
            temp = self.srcs
            self.srcs = self.dests
            self.dests = temp


class GotoInstruction(BranchInstruction):

    def get_branch_destination(self):
        """Return the branch destination of this instruction"""
        if self.srcs[-1] == '1-1':
            return ['next']
        return [self.srcs[-1]]

class StoreInstruction(Instruction):

    def get_fu(self):
        return FU.MEM

    def parse_args(self, args):
        for arg in [x.strip() for x in args]:
            if (arg == "," or arg == '[' or arg == ']' or
                arg == '' or arg == '='):
                continue
            if parse.is_register(arg):
                arg = vex.parse_register(arg)
            self.srcs.append(arg)

    def __str__(self):
        string = "c{0} {1} ".format(self.cluster, self.mnemonic)
        string += "{0}[{1}] = {2}".format(self.srcs[0], self.srcs[1],
                                          self.srcs[2])
        return string

class LoadInstruction(Instruction):

    def get_fu(self):
        return FU.MEM

    def cost(self):
        return 2

    def __str__(self):
        string = "c{0} {1} ".format(self.cluster, self.mnemonic)
        string += "{0} = {1}[{2}]".format(self.dests[0], self.srcs[0],
                                          self.srcs[1])
        return string

class StopInstruction(Instruction):

    def get_fu(self):
        return FU.BR

    def __str__(self):
        return 'c{0} {1}'.format(self.cluster, self.mnemonic)

class EndBBInstruction(Instruction):

    def __init__(self):
        self.line_no = -1
        pass

    def __str__(self):
        return ''

