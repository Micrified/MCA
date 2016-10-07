import vex
import re
import graph
from debugprint import warn
from instructions import parse_instruction
from instructions import LoadInstruction

class Label:

    def __eq__(self, other):
        if isinstance(other, self.__class__):
            return other.label == self.label and other.local == self.local
        return False

    def __hash__(self):
        return hash(str(self))

    def __init__(self, line):
        match = re.search(r'([\.\w\?]+):+', line)
        if match:
            self.label = match.group(1)
        else:
            raise ValueError("'{0}' is not a label".format(line))
        if re.search(r'::', line):
            self.local = False
        else:
            self.local = True

    def __str__(self):
        string = "{0}:".format(self.label)
        if not self.local:
            string += ':'
        return string

    def __repr__(self):
        return "{0}('{1}')".format(self.__class__.__name__, str(self))


class InstructionBundle:
    """An InstructionBundle holds multiple instructions that are scheduled for
    simultaneous execution.

    """

    def __eq__(self, other):
        if not isinstance(other, InstructionBundle):
            return False
        return str(self) == str(other)

    def get_destination(self):
        for insn in self.insns:
            if insn.is_branch():
                return insn.get_branch_destination()
        return ["next"]

    def get_written(self):
        written = set()
        for insn in self.insns:
            written |= insn.get_written_registers()
        return written

    def get_read(self):
        read = set()
        for insn in self.insns:
            read |= insn.get_read_registers()
        return read

    def ends_bb(self):
        for insn in self.insns:
            if insn.is_branch():
                return True
        return False

    def begins_bb(self):
        if self.labels:
            return True
        return False

    def fix_same_reg_writes(self):
        '''Check if there are multiple instructions that write to the same
        register in this bundle. If there are, and the targer is a general
        register, rename the first one to r0 so it will be ignored. Also issue
        warning.'''
        written = set()
        err = False
        for insn in reversed(self.insns):
            regs = insn.get_written_registers()
            for r in regs:
                if r == vex.GeneralRegister(0,0) or not r in written:
                    continue
                warn('Multiple writes to same register in bundle',
                        self.insns[0].line_no)
                #print(self, file=sys.stderr)
                if isinstance(r, vex.GeneralRegister):
                    insn.change_dest_reg(r, vex.GeneralRegister(0,0))
                else:
                    err = True
            written |= regs
        return err


    def fix_stack_pop(self):
        '''Check if an instruction bundle contains both a return instruction
        and an add to $r0.1. If they do, try to combine them into a single
        return and stack pop instruction. The instructions can only be combined
        if the add instruction reads the first source from register 1, and the
        second is a short immediate value that fits in a branch immediate.

        Return value:
        True if successful, meaning the instructions were combined successfuly,
        or the combination of instructions was not found.
        False if the instructions were found, but could not be combined.'''
        for insn in self.insns:
            if insn.is_return():
                ret_insn = insn
                break
        else:
            return True
        for insn in self.insns:
            if (insn.mnemonic == 'add' and
                    vex.GeneralRegister(0,1) in insn.get_written_registers()):
                add_insn = insn
                break
        else:
            return True
        if (add_insn.srcs[0] != vex.GeneralRegister(0,1) or
                isinstance(add_insn.srcs[1], vex.GeneralRegister)):
            print('Could not combine return and stack pop on line {}:'.format(
                add_insn.line_no), file=sys.stderr)
            print(self, file=sys.stderr)
            return False
        if len(ret_insn.srcs) == 1:
            ret_insn.srcs.insert(0, vex.GeneralRegister(0,1))
            ret_insn.srcs.insert(1, add_insn.srcs[1])
        else:
            ret_insn.srcs[1] = '{} + {}'.format(ret_insn.srcs[1],
                    add_insn.srcs[1])
        if len(ret_insn.dests) == 0:
            ret_insn.dests.append(vex.GeneralRegister(0,1))
        self.insns.remove(add_insn)
        return True

    def has_call(self):
        for insn in self.insns:
            if insn.is_call():
                return True
        return False

    def has_cycle(self):
        """Check if this instruction bundle has a dependency cycle
        between the instructions

        """
        if graph.Graph(self.insns).schedule():
            return True
        else:
            return False

    def has_load_dependency(self):
        regs = set()
        ins2 = None
        for ins in self.insns:
            if isinstance(ins, LoadInstruction):
                regs = ins.get_written_registers()
                ins2 = ins
        if not regs:
            return set()
        for ins in self.insns:
            if ins is ins2:
                continue
            if regs & ins.get_read_registers():
                return regs & ins.get_read_registers()
        return set()


    def get_cycle_regs(self):
        """Get all registers written by instructions in a dependency cycle."""
        regs = set()
        for insn in graph.Graph(self.insns).schedule():
            regs |= insn.get_written_registers()
        return regs

    def rename_written(self, reg1, reg2):
        """Rename all registers named reg1 written in this bundle by reg2.

        Keyword arguments:
        reg1 -- original register name
        reg2 -- new register name

        """
        for ins in self.insns:
            ins.change_dest_reg(reg1, reg2)

    def rename_read(self, reg1, reg2):
        """Rename all registers named reg1 read in this bundle by reg2.

        Keyword arguments:
        reg1 -- original register name
        reg2 -- new register name

        """
        for ins in self.insns:
            ins.change_source_reg(reg1, reg2)

    def is_fake(self):
        return False

    def __init__(self, lines, line_no, name=[], raw=False):
        """Create a new InstructionBundle with the instructions in lines and
        the name name.

        Keyword arguments:
            lines -- when raw is False:
                       an array of two-tuples; the first part being the string
                       representing the instruction and the second being the
                       hash-separated comment
                     when raw is True:
                       an array of Instructions
            line_no -- line number in input file
            name -- the optional label of the bundle (default "")
            raw

        """
        self.labels = [Label(x) for x in name]
        self.line_no = line_no
        if raw:
            self.insns = lines
        else:
            self.insns = [parse_instruction(line[0], line[1], line_no) for line in lines]

    def __str__(self):
        string = ""
        if self.labels:
            string = '\n'.join(str(x) for x in self.labels) + '\n'
        if self.insns != []:
            string += "\n".join(map(str, self.insns)) + "\n"
        return string + ";;"

    def __repr__(self):
        return "{0}({1})".format(self.__class__.__name__, self.insns)

class Bundle:

    def __eq__(self, other):
        if not isinstance(other, self.__class__):
            return False
        return str(self) == str(other)

    def fix_stack_pop(self):
        return

    def is_fake(self):
        return True

    def has_call(self):
        return False

    def fix_same_reg_writes(self):
        return False

    def rename_read(self, reg1, reg2):
        pass

    def get_destination(self):
        return ["next"]

    def get_written(self):
        return set()

    def get_read(self):
        return set()

    def has_cycle(self):
        return False

    def has_load_dependency(self):
        return set()

    def __init__(self):
        self.labels = set()

    def __str__(self):
        return ""

    def __repr__(self):
        return "{}()".format(self.__class__.__name__)

class EntryBundle(Bundle):

    def get_written(self):
        return self.written

    def __init__(self):
        super().__init__()
        self.written = set(vex.fixed_regs)

class ExitBundle(Bundle):

    def get_destination(self):
        return []

    def get_read(self):
        return self.read

    def __init__(self):
        super().__init__()
        self.read = set(vex.fixed_regs)


class CallBundle(Bundle):

    def get_written(self):
        return self.written

    def get_read(self):
        return self.read

    def __init__(self):
        super().__init__()
        self.read = set(vex.fixed_regs)
        self.written = set(vex.fixed_regs)


class BundleScheduler:

    def schedule2(self, insns):
        a = graph.Graph(insns, self.config)
        a.build_graph()
        return a.schedule2()

    def size(self, nodes):
        sum = 0
        for node in nodes:
            if node.insn.has_long_imm():
                sum += 2
            else:
                sum += 1
        return sum

    def cost2(self, issue, size):
        result = 0
        if size == 0 or size % issue != 0:
            result = 1
        return size//issue + result

    def cost(self, size):
        return self.cost2(2, size) + self.cost2(4, size) + self.cost2(8, size)

    def __init__(self, config):
        self.layout = config['layout']
        self.fus = config['fus']
        self.borrow = config['borrow']
        self.config = config
        self.issued = set()


