import re
import sys
from docopt import docopt
from collections import defaultdict
import parse
import vex
import graph
import copy

opt = """vexparse.
Usage:
    vex_parse.py <file> [--resched (--O0 | --O1 | --O2)] [--borrow=<borrow>] [--config=<cfg>] [--nalu=<num>] [--nmul=<num>] [--nmem=<num>] [--nbr=<num>] [-o <file>]
    vex_parse.py (-h | --help)
    vex_parse.py --version

Options:
    -h --help          Show this help message.
    --version          Show version.
    -o <file>          Give the output filename.
    --resched          Allow rescheduling in addition to register renaming
                       to fix dependencies.
    --O0               Only allow NOP-insertion when rescheduling.
    --O1               Try to optimize code size (and thus speed).
    --O2               --O1 + reorder instruction to smoothen bundle sizes.
    --borrow=<borrow>  Supply borrow configuration. Use . as lane separator
                       and , as slot separator, for example
                       1.0.3,0.2,1.5,2.4,3.7,4.6,5
    --config=<cfg>     Lane resource configuration, specified as hex number,
                       with a nibble for each lane. Bit 0 is used for ALU,
                       bit 1 for MUL, bit 2 for MEM and bit 3 for BR.
    --nalu=<num>       Number of ALU resources. If not specified, the value is
                       deduced from --config.
    --nmul=<num>       Same as --nalu, but for MUL resources.
    --nmem=<num>       Same as --nalu, but for MEM resources.
    --nbr=<num>        Same as --nalu, but for BR resources.

"""

ALU = 1
MUL = 2
MEM = 4
BR = 8

class Label:

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
        return ALU

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
        return MUL

    def cost(self):
        return 2

class ControlInstruction(Instruction):

    def has_long_imm(self):
        return False

    def is_branch(self):
        return True

    def get_fu(self):
        return BR

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
        return MEM

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
        return MEM

    def cost(self):
        return 2

    def __str__(self):
        string = "c{0} {1} ".format(self.cluster, self.mnemonic)
        string += "{0} = {1}[{2}]".format(self.dests[0], self.srcs[0],
                                          self.srcs[1])
        return string

class StopInstruction(Instruction):

    def get_fu(self):
        return BR

    def __str__(self):
        return 'c{0} {1}'.format(self.cluster, self.mnemonic)

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

    def __init__(self, lines, line_no, name=set(), raw=False):
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
        self.labels = {Label(x) for x in name}
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

    def is_fake(self):
        return True

    def has_call(self):
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

    def can_issue(self, insn, issue):
        if issue in self.issued:
            return False
        if not insn.get_fu() in self.layout[issue]:
            return False
        if not insn.has_long_imm():
            return True
        for index in self.borrow[issue]:
            if not index in self.issued:
                return True
        return False

    def issue(self, issue):
        self.issued.add(issue)

    def un_issue(self, issue):
        self.issued.remove(issue)

    def schedule2(self, insns):
        a = graph.Graph(insns, self.config)
        a.build_graph()
        return a.schedule2()


    def schedule(self, insns):
        size = 0
        for insn in insns:
            if insn.has_long_imm():
                size += 2
            else:
                size += 1
        if size > 8:
            return False
        a = defaultdict(lambda:0)
        for insn in insns:
            a[insn.get_fu()] += 1
        for key in a.keys():
            if a[key] > self.fus[key]:
                return False
        return True

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


class Node:
    """node for scheduling instructions"""

    def cost(self, node):
        cost = self.insn.cost()
        if node.insn.is_branch():
            return cost + 1
        return cost

    def slack(self):
        return len(self.possible)

    def ready(self, unsched):
        for node in self.raw:
            if node in unsched:
                return False
        for node in self.war:
            if node in unsched:
                return False
        for node in self.waw:
            if node in unsched:
                return False
        return True

    def remove(self, index):
        if index in self.possible:
            self.possible.remove(index)
        if not self.possible:
            print(self)
            print("This instruction cannot be scheduled.")
            return True
        if index < min(self.possible) or index > max(self.possible):
            return True
        else:
            return False

    def schedule(self, index):
        self.possible = {index}

    def __init__(self, insn, index, max_lat):
        self.insn = insn
        self.written = insn.get_written_registers()
        self.read = insn.get_read_registers()
        self.raw = set()
        self.war = set()
        self.waw = set()
        self.rbw = set()
        self.wbr = set()
        self.wbw = set()
        self.max = index
        self.index = index
        self.possible = [index]

    def __repr__(self):
        return "Node({})".format(repr(self.insn))

    def __str__(self):
        return "{}: {} {} {}".format(str(self.insn), self.index, self.possible,
                self.insn.has_long_imm())

class BasicBlock:

    def build_raw_graph(self, nodes):
        for node in nodes:
            written = node.written
            written_temp = written
            temp_index = node.index
            for node2 in nodes:
                if node == node2:
                    continue
                if node.index >= node2.index:
                    continue
                if temp_index < node2.index:
                    temp_index = node2.index
                    written = written_temp
                if not written:
                    break
                read = node2.read
                if written & read:
                    node2.raw.add(node)
                    node.wbr.add(node2)
                written2 = node2.written
                written_temp = {x for x in written_temp if x not in written2}

    def build_war_graph(self, nodes):
        for node in nodes:
            read = node.read
            read_temp = read
            temp_index = node.index
            for node2 in nodes:
                if node.index > node2.index:
                    continue
                if node == node2:
                    continue
                if temp_index < node2.index:
                    temp_index = node2.index
                    read = read_temp
                if not read:
                    break
                written2 = node2.written
                read_temp = {x for x in read_temp if x not in written2}
                if (read & written2):
                    node2.war.add(node)
                    node.rbw.add(node2)

    def build_waw_graph(self, nodes):
        for node in nodes:
            written = node.written
            written_temp = written
            temp_index = node.index
            for node2 in nodes:
                if node == node2:
                    continue
                if node.index >= node2.index:
                    continue
                if temp_index < node2.index:
                    temp_index = node2.index
                    written = written_temp
                if not written:
                    break
                written2 = node2.written
                written_temp = {x for x in written_temp if x not in written2}
                if (written & written2):
                    node2.waw.add(node)
                    node.wbw.add(node2)

    def build_mem_graph(self, nodes):
        for node in nodes:
            if node.insn.get_fu() != MEM:
                continue
            for node2 in nodes:
                if node == node2:
                    continue
                if node.index >= node2.index:
                    continue
                if node2.insn.get_fu() != MEM:
                    continue
                node.wbw.add(node2)
                node2.waw.add(node)
                break

    def build_control_graph(self, nodes):
        for node in nodes:
            if node.wbr or node.wbw:
                continue
            for node2 in nodes:
                if node == node2:
                    continue
                if node.index > node2.index:
                    continue
                if node2.insn.is_branch():
                    node2.war.add(node)
                    node.rbw.add(node2)

    def build_instruction_graph(self):
        nodes = []
        for index, bundle in enumerate(self.bundles):
            for insn in bundle.insns:
                nodes.append(Node(insn, index, len(self.bundles)))
        self.build_raw_graph(nodes)
        self.build_war_graph(nodes)
        self.build_waw_graph(nodes)
        self.build_mem_graph(nodes)
        self.build_control_graph(nodes)
        return nodes

    def __init__(self, bundles):
        self.bundles = bundles

    def __str__(self):
        return "\n".join(str(bundle) for bundle in self.bundles)

class Function:

    def __eq__(self, other):
        if not isinstance(other, Function):
            return False
        return str(self) == str(other)

    def get_free_reg(self, reg, indices):
        table = self.build_register_live_table()
        result = set(indices)
        #the provided register is always considered used
        used_regs = set([reg])
        for index in indices:
            visited = defaultdict(lambda: False)
            if not reg in self.bundles[index].get_written():
                return []
            to_visit = set(self.succ_cfg[index])
            while to_visit:
                index = to_visit.pop()
                if visited[index]:
                    continue
                visited[index] = True
                if reg in table[index]:
                    result.add(index)
                    if reg in self.bundles[index].get_written():
                        continue
                    used_regs |= self.bundles[index].get_written()
                    to_visit |= set(self.succ_cfg[index])

        for i in result:
            used_regs |= table[i]
        return reg.get_free_reg(used_regs)

    def rewrite(self, reg, index):
        """Rewrite reg to a free register in bundles starting from index.
        reg has to be written in the bundle identified by index.
        If no free register is found the function does nothing.

        """
        sources = self.get_read(reg, index)
        dests = set()
        if reg in self.bundles[index].get_written():
            dests.add(index)
        changed = True
        while changed:
            new_dests = set(dests)
            new_sources = set(sources)
            for source in sources:
                new_dests.update(self.get_written(reg, source))
            for dest in dests:
                new_sources.update(self.get_read(reg, dest))
            if new_dests != dests or new_sources != sources:
                changed = True
            else:
                changed = False
            sources = new_sources
            dests = new_dests
        for x in sources:
            if (isinstance(self.bundles[x], CallBundle) or
                    isinstance(self.bundles[x], ExitBundle)):
                return
        for x in dests:
            if (isinstance(self.bundles[x], CallBundle) or
                    isinstance(self.bundles[x], EntryBundle)):
                return
        new_reg = self.get_free_reg(reg, dests)
        if not new_reg:
            return
        for index in sources:
            self.bundles[index].rename_read(reg, new_reg)
        for index in dests:
            self.bundles[index].rename_written(reg, new_reg)
        return True

    def get_read(self, reg, index):
        '''Return the indexes of all the bundles where register reg is read
        which is written in bundle with index index.'''
        result = set()
        visited = {key: False for key in self.succ_cfg}
        table = self.build_register_live_table()

        if not reg in self.bundles[index].get_written():
            return result
        to_visit = list(self.succ_cfg[index])
        while to_visit:
            i = to_visit.pop()
            if visited[i]:
                continue
            visited[i] = True
            if not reg in table[i]:
                continue
            if reg in self.bundles[i].get_read():
                result.add(i)
            if reg in self.bundles[i].get_written():
                continue
            else:
                to_visit.extend(self.succ_cfg[i])

        return result

    def get_written(self, reg, index):
        '''Return the indexes of all bundles where register reg, which is read
        in bundle with index index, was written.'''
        result = set()
        visited = {key: False for key in self.succ_cfg}
        if not reg in self.bundles[index].get_read():
            return result
        to_visit = list(self.pred_cfg[index])
        while to_visit:
            i = to_visit.pop()
            if visited[i]:
                continue
            visited[i] = True
            if reg in self.bundles[i].get_written():
                result.add(i)
                continue
            else:
                to_visit.extend(self.pred_cfg[i])

        return result

    def build_label_table(self):
        result = {}
        for i, bundle in enumerate(self.bundles):
            for label in bundle.labels:
                result[label.label] = i
        return result

    def build_successor_graph(self):
        table = defaultdict(list)
        labels = self.build_label_table()
        for i, bundle in enumerate(self.bundles):
            table[i]
            for dest in bundle.get_destination():
                if dest == "next":
                    if i + 1 >= len(self.bundles):
                        continue
                    table[i].append(i + 1)
                elif dest == "return":
                    table[i].append(len(self.bundles)-1)
                else:
                    if dest == vex.LinkRegister(0,0):
                        # This means a goto that can jump to any address
                        # Just hope it only jumps to any of the local labels
                        for value in labels.values():
                            table[i].append(value)
                        continue
                    elif dest in labels:
                        table[i].append(labels[dest])
                    else:
                        # if the label is not known, treat the instruction
                        # like a return
                        table[i].append(len(self.bundles)-1)
        return table

    def build_predecessor_graph(self, table):
        reverse_table = defaultdict(list)
        for key, value in table.items():
            reverse_table[key]
            for j in value:
                reverse_table[j].append(key)
        return reverse_table

    def build_register_live_table(self):
        """Return a dictionary which contains the set of live registers at the
        start of each instruction bundle.
        A register is considered to be live in a bundle if it is read by any of
        that bundle's successors.

        """
        live_graph = defaultdict(set)
        changed = {key: True for key in self.succ_cfg}

        while any(changed.values()):
            # The list is traversed in reverse to reduce the number of
            # iterations needed to build the table.
            new_changed = dict(changed)
            for i, bundle in reversed(list(enumerate(self.bundles))):
                succs = self.succ_cfg[i]
                # If this bundle has successors and none of their register
                # liveness information has been updated, this one will not be
                # updated either.
                if succs and (not any((changed[x] for x in succs))):
                    new_changed[i] = False
                    continue

                written = bundle.get_written()
                read = bundle.get_read()
                live = set()
                for succ in succs:
                    live |= live_graph[succ]
                live -= written
                live |= read
                if live != live_graph[i]:
                    new_changed[i] = True
                else:
                    new_changed[i] = False
                live_graph[i] = live
            changed = new_changed
        return live_graph

    def split_into_basic_blocks(self):
        """Split the list of instruction bundles into a list of BasicBlocks."""
        bbs = []
        bundles = []
        for bundle in self.bundles:
            if bundle.is_fake():
                continue
            if bundle.begins_bb() and bundles:
                bbs.append(BasicBlock(bundles))
                bundles = []
            bundles.append(bundle)
            if bundle.ends_bb():
                bbs.append(BasicBlock(bundles))
                bundles = []
        if bundles:
            bbs.append(BasicBlock(bundles))
        return bbs

    def split_into_bundles(self, lines):
        name = set()
        bundle_lines = []
        bundle_line_no = -1
        self.bundles.append(EntryBundle())
        exit = ExitBundle()
        pseudo_call = False
        pseudo_op = None
        for i in lines:
            line = i[0]
            comment = i[1]
            if len(bundle_lines) == 0:
                bundle_line_no = i[2]
            if parse.is_label(line):
                if pseudo_op and parse.is_global(pseudo_op):
                    pseudo_op = None
                    line = line.strip()+':'
                name.add(line)
                continue
            elif parse.is_end_bundle(line):
                insns = [parse_instruction(x[0], x[1], x[2]) for x in bundle_lines]
                for insn in insns:
                    if insn.is_call() or insn.is_return():
                        insn.pseudo_op = pseudo_op
                        break
                self.bundles.append(InstructionBundle(insns, bundle_line_no, name, raw=True))
                bundle_lines, name = ([], set())
                if self.bundles[-1].has_call():
                    # insert a fake basic block representing the function call
                    call_b = CallBundle()
                    if pseudo_call:
                        call_b.read = arg_regs
                        call_b.written = ret_regs
                    self.bundles.append(call_b)
                pseudo_call = False
                pseudo_op = None
                continue
            elif parse.is_entry(line):
                regs = parse.get_regs(line)
                self.bundles[0].written = {vex.parse_register(x) for x in regs}
                continue
            elif parse.is_exit(line):
                pseudo_op = line
                regs = parse.get_regs(line)
                exit.read = {vex.parse_register(x) for x in regs}
                continue
            elif parse.is_call(line):
                pseudo_op = line
                arg_regs = {vex.parse_register(x) for x in
                        parse.get_arg_regs(line)}
                ret_regs = {vex.parse_register(x) for x in
                        parse.get_ret_regs(line)}
                pseudo_call = True
                continue
            elif parse.is_global(line):
                pseudo_op = line
                continue
            elif parse.is_type(line):
                continue
            elif parse.is_nopinsertion(line):
                # skip this pseudo op
                continue
            elif parse.is_balignl(line):
                # skip this pseudo op
                continue
            bundle_lines.append(i)
        if bundle_lines != []:
            self.bundles.append(InstructionBundle(bundle_lines, bundle_line_no, name))
        self.bundles.append(exit)
        return

    def fix_cycles(self):
        for i, bundle in enumerate(self.bundles):
            if bundle.has_cycle():
                regs = bundle.get_cycle_regs()
                for reg in regs:
                    self.rewrite(reg, i)
                    if not bundle.has_cycle():
                        break
        return

    def fix_load_dependency(self):
        for i, bundle in enumerate(self.bundles):
            regs = bundle.has_load_dependency()
            for reg in regs:
                if not self.rewrite(reg, i):
                    indices = self.get_written(reg, i)
                    if indices:
                        self.rewrite(reg, indices.pop())
                if not bundle.has_load_dependency():
                    break

    def calc_alap(self, nodes):
        changed = set(nodes)
        while changed:
            unchanged = set()
            for node in reversed(nodes):
                new = set()
                if node.wbr:
                    new.add(min(x.index - node.cost(x) for x in node.wbr))
                if node.rbw:
                    new.add(min(x.index for x in node.rbw))
                if node.wbw:
                    new.add(min(x.index - 1 for x in node.wbw))
                if not new:
                    unchanged.add(node)
                    continue
                new = min(new)
                new_possible = list(range(node.index, new + 1))
                if node.possible == new_possible:
                    unchanged.add(node)
                    continue
                node.possible = new_possible
                changed.add(node)
            changed -= unchanged

    def resched(self, bb, config):
        nodes = bb.build_instruction_graph()
        self.calc_alap(nodes)
        changed = True
        while changed:
            changed = set()
            for node in reversed(nodes):
                if not len(node.possible) > 1:
                    continue
                selected = []
                for index in node.possible:
                    b = BundleScheduler(config)
                    if index == node.index:
                        new_nodes = {x for x in nodes if x.index == index and
                                not x == node}
                    else:
                        new_nodes = {x for x in nodes if x.index == index}
                    before = b.cost(b.size(new_nodes))
                    size = b.size(new_nodes)
                    new_nodes.add(node)
                    if b.schedule2([a.insn for a in new_nodes]):
                        after = b.cost(b.size(new_nodes))
                        cost = after - before
                        selected.append((cost, size, index))
                if not selected:
                    continue
                index = min(selected)[2]
                if index == node.index:
                    continue
                node.index = index
                self.calc_alap(nodes)
                changed.add(node)
        sched = defaultdict(list)
        for node in nodes:
            sched[node.index].append(node)
        for index, bundle in enumerate(bb.bundles):
            bundle.insns = [x.insn for x in sched[index]]

    def do_asap(self, config):
        bbs = self.split_into_basic_blocks()
        for bb in bbs:
            self.resched(bb, config)

    def fully_resched_bb(self, bb, config, opt):
        debug = False
        if debug:
            print("************************", file=sys.stderr)
        nodes = bb.build_instruction_graph()
        for index, node in enumerate(nodes):
            node.list_index = index

        # Minimum syllables per cycle/number of lanes.
        min_issue = 2

        # Maximum syllables per cycle/number of lanes.
        max_issue = 8

        # Maximum latency.
        max_latency = 2

        # Determine scheduling constraints due to dependencies. Note that
        # dependencies on branch instructions are ignored, because the code
        # generating those dependencies is a bit dodgy for branches. It doesn't
        # matter here because the branch should always be at the end of a basic
        # block, so there aren't any instructions anything dependent on it
        # within the basic block by definition.
        for node in nodes:
            node.must_schedule_in_cycle = None
            node.cycles_after = {}
            node.cycles_before = {}
        def register_dep(node, dep, dly):
            ni = node.list_index
            di = dep.list_index
            if di not in node.cycles_after or node.cycles_after[di] < dly:
                node.cycles_after[di] = dly
            if ni not in dep.cycles_before or dep.cycles_before[ni] < dly:
                dep.cycles_before[ni] = dly
        prev_node = None
        prev_bun = []
        cur_bun = []
        for node in nodes:
            for dep_node in node.war:
                if not dep_node.insn.is_branch():
                    register_dep(node, dep_node, 0)
            for dep_node in node.waw:
                if not dep_node.insn.is_branch():
                    register_dep(node, dep_node, 1)
            for dep_node in node.raw:
                if not dep_node.insn.is_branch():
                    register_dep(node, dep_node, dep_node.insn.cost())
            if not node.insn.is_branch():
                for dep_node in node.rbw:
                    register_dep(dep_node, node, 0)
                for dep_node in node.wbw:
                    register_dep(dep_node, node, 1)
                for dep_node in node.wbr:
                    register_dep(dep_node, node, node.insn.cost())

            # If optimizations are off, we should only insert NOPs when we need
            # to, or reorder instructions within a bundle. To accomplish this,
            # add a dependency between every subsequent bundle, using the
            # original number of bundle borders between them as latency.
            if not opt:
                if prev_node is not None:
                    dly = node.index != prev_node.index
                    if dly > 0: # Bundle border between prev and current node.
                        for node_a in prev_bun:
                            for node_b in cur_bun:
                                register_dep(node_b, node_a, dly)
                        prev_bun = cur_bun
                        cur_bun = []
                prev_node = node
                cur_bun += [node]

            if debug:
                print("Node " + str(node.list_index) + ": " + str(node.insn), file=sys.stderr)
                for dep in node.cycles_after.items():
                    print("  At least " + str(dep[1]) + " cycles after node " + str(dep[0]), file=sys.stderr)
                for dep in node.cycles_before.items():
                    print("  At least " + str(dep[1]) + " cycles before node " + str(dep[0]), file=sys.stderr)
                for dep in node.war:
                    print("  WAR: " + str(dep.list_index), file=sys.stderr)
                for dep in node.raw:
                    print("  RAW: " + str(dep.list_index), file=sys.stderr)
                for dep in node.waw:
                    print("  WAW: " + str(dep.list_index), file=sys.stderr)
                for dep in node.wbr:
                    print("  WBR: " + str(dep.list_index), file=sys.stderr)
                for dep in node.rbw:
                    print("  RBW: " + str(dep.list_index), file=sys.stderr)
                for dep in node.wbw:
                    print("  WBW: " + str(dep.list_index), file=sys.stderr)

        # Schedule the nodes.
        sched_syll = {} # Map from syllable index (PC/4) to node or "LIMMH <lane>, *".
        sched_res = {ALU: {}, MUL: {}, MEM: {}, BR: {}} # Map from generic bundle index (PC/32) to resource usage.
        syll_count = 0
        nodes_scheduled = 0
        nodes_scheduled_prev = 0
        test_circular = False
        for node in nodes:
            node.scheduled_at = None
        while nodes_scheduled < len(nodes):
            for node in nodes:
                if node.scheduled_at is None:

                    same_cycle_nodes = []

                    # We can only schedule this node when all nodes which it
                    # depends on have also been scheduled.
                    can_schedule = True
                    is_circular = False
                    min_syll_idx = 0
                    for dep in node.cycles_after.items():
                        dep_at = nodes[dep[0]].scheduled_at
                        if dep_at is None:

                            # One of the dependencies has not been scheduled
                            # yet, so we can't schedule this instruction
                            # normally.
                            can_schedule = False

                            # If the dependency is only dependent on us,
                            # though, we should schedule anyway to handle
                            # circular dependencies.
                            if test_circular:
                                can_schedule = True
                                for dep_dep in nodes[dep[0]].cycles_after.items():
                                    dep_dep_at = nodes[dep_dep[0]].scheduled_at
                                    if dep_dep[0] == node.list_index:
                                        # Circular dependancy detected.
                                        # Ignore it if the loop latency is
                                        # zero, in which case it might be
                                        # schedulable.
                                        if dep[1] + dep_dep[1] > 0:
                                            # Impossible circular dependency.
                                            sys.exit("Impossible circular dependency in basic block starting at input line " + str(nodes[0].insn.line_no) + ".")
                                        is_circular = True
                                        continue
                                    if dep_dep_at is None:
                                        can_schedule = False
                                        break
                                if is_circular and can_schedule:
                                    same_cycle_nodes += [nodes[dep[0]]]

                            break
                        else:
                            # Determine the first index where we can schedule
                            # this instruction.
                            if dep[1] == 0:
                                i = (dep_at//min_issue) * min_issue
                            else:
                                i = (dep_at//max_issue + dep[1]) * max_issue
                            if min_syll_idx < i:
                                min_syll_idx = i
                    if not can_schedule:
                        continue

                    # Determine the last index where we can schedule this
                    # instruction.
                    if node.must_schedule_in_cycle is not None:
                        # The to-be-scheduled syllable must be scheduled in
                        # exactly the cycle specified due to a circular
                        # dependency.
                        if min_syll_idx//min_issue > node.must_schedule_in_cycle:
                            if debug:
                                print(node.list_index, file=sys.stderr)
                            sys.exit("Impossible circular dependency in basic block "
                                     + "starting at input line "
                                     + str(nodes[0].insn.line_no))

                        min_syll_idx = node.must_schedule_in_cycle * min_issue
                        max_syll_idx = min_syll_idx + min_issue - 1
                    else:
                        # Choose something which is high enough for any
                        # instruction to be scheduled.
                        max_syll_idx = max(min_syll_idx, syll_count) + max_issue * 3

                    # Determine the functional unit necessary to execute the
                    # instruction.
                    fu = node.insn.get_fu()

                    # Schedule this node as soon as possible taking all
                    # constraints into account.
                    for syll_idx in range(min_syll_idx, max_syll_idx+1):
                        bun_idx = syll_idx // max_issue
                        lane_idx = syll_idx % max_issue

                        # Can't schedule here if this position already contains
                        # an instruction.
                        if syll_idx in sched_syll:
                            continue

                        # If this is the first syllable in a pair of circularly
                        # dependent instructions, we'll want to schedule it in
                        # a lane group which is still completely free.
                        if is_circular:
                            grp_free = True
                            grp_idx = syll_idx // min_issue
                            for i in range(grp_idx, grp_idx + min_issue):
                                if i in sched_syll:
                                    grp_free = False
                                    break
                            if not grp_free:
                                continue


                        # Check if the current lane has the functional unit we
                        # need.
                        if fu not in config['layout'][lane_idx]:
                            continue

                        # Make sure we haven't run out of resources in this
                        # bundle yet.
                        if bun_idx not in sched_res[fu]:
                            sched_res[fu][bun_idx] = 0
                        if sched_res[fu][bun_idx] >= config['fus'][fu]:
                            continue

                        # If this instruction needs a LIMMH instruction, make
                        # sure there's room for it, and heuristically choose
                        # the best option to schedule it in if there's more
                        # than one.
                        limmh_syll_idx = None
                        if node.insn.has_long_imm():
                            opts = config['borrow'][lane_idx]
                            cur_cost = None
                            for opt in opts:

                                # Check if this slot is free.
                                if (bun_idx*max_issue + opt) in sched_syll:
                                    continue

                                # Check for cost. Cost is based on the number
                                # of functional units in the lane which we'd
                                # be scheduling a LIMMH in.
                                cost = len(config['layout'][opt])
                                if limmh_syll_idx is None or cost < cur_cost:
                                    limmh_syll_idx = bun_idx*max_issue + opt
                                    cur_cost = cost

                            if limmh_syll_idx is None:
                                continue

                        # Brag about handling circular data dependencies if
                        # debug is enabled...
                        if debug and node.must_schedule_in_cycle is not None:
                            print("Circular data dependency handled!", file=sys.stderr)

                        # Can schedule here!

                        # Schedule the instruction itself.
                        sched_syll[syll_idx] = node
                        node.scheduled_at = syll_idx
                        sched_res[fu][bun_idx] += 1
                        nodes_scheduled += 1

                        # Schedule its LIMMH borrow slot.
                        if limmh_syll_idx is not None:
                            sched_syll[limmh_syll_idx] = "limmh " + str(lane_idx) + ", *"

                        # Extend syll_count such that the basic block won't end
                        # until the instruction(s) have been issued and their
                        # results can be used.
                        extra_nops = 0
                        if node.insn.cost() > 1:
                            extra_nops = node.insn.cost() - 1
                        if syll_count < syll_idx + extra_nops*max_issue + 1:
                            syll_count = syll_idx + extra_nops*max_issue + 1
                        if limmh_syll_idx is not None:
                            if syll_count < limmh_syll_idx + 1:
                                syll_count = limmh_syll_idx + 1

                        # If there were circularly dependent nodes with 0 loop
                        # latency, these need to be scheduled in the same
                        # cycle.
                        for node2 in same_cycle_nodes:
                            node2.must_schedule_in_cycle = syll_idx // min_issue

                        break


            # If we didn't manage to schedule anything this round, enable
            # circular dependency handling (which is a bit slower). If that
            # fails as well, the code cannot be scheduled.
            if nodes_scheduled_prev == nodes_scheduled:
                if not test_circular:
                    test_circular = True
                else:
                    if debug or True:
                        print("", file=sys.stderr)
                        print("*** Scheduling error incoming ***", file=sys.stderr)
                        print("--- Scheduled " + str(nodes_scheduled) + " out of " + str(len(nodes)) + " nodes so far: ---", file=sys.stderr)
                        for syll_idx in range(((syll_count + max_issue - 1) // max_issue) * max_issue):
                            if syll_idx in sched_syll:
                                if isinstance(sched_syll[syll_idx], Node):
                                    print("  ln" + str(syll_idx % max_issue)
                                          + " n" + str(sched_syll[syll_idx].list_index)
                                          + ": " + str(sched_syll[syll_idx].insn), file=sys.stderr)
                                else:
                                    print("  ln" + str(syll_idx % max_issue)
                                          + ": " + sched_syll[syll_idx], file=sys.stderr)
                            if (syll_idx % max_issue) == 7:
                                print(";;", file=sys.stderr)

                        print("", file=sys.stderr)
                        print("--- Remaining nodes: ---", file=sys.stderr)
                        for node in nodes:
                            if node.scheduled_at == None:
                                print("  n" + str(node.list_index) + ": " + str(node.insn), file=sys.stderr)
                                for dep in node.cycles_after.items():
                                    print("    At least " + str(dep[1]) + " cycles after node " + str(dep[0]), file=sys.stderr)
                                for dep in node.cycles_before.items():
                                    print("    At least " + str(dep[1]) + " cycles before node " + str(dep[0]), file=sys.stderr)
                                for dep in node.war:
                                    print("    WAR: " + str(dep.list_index), file=sys.stderr)
                                for dep in node.raw:
                                    print("    RAW: " + str(dep.list_index), file=sys.stderr)
                                for dep in node.waw:
                                    print("    WAW: " + str(dep.list_index), file=sys.stderr)
                                for dep in node.wbr:
                                    print("    WBR: " + str(dep.list_index), file=sys.stderr)
                                for dep in node.rbw:
                                    print("    RBW: " + str(dep.list_index), file=sys.stderr)
                                for dep in node.wbw:
                                    print("    WBW: " + str(dep.list_index), file=sys.stderr)

                        print("", file=sys.stderr)
                        print("--- Error code: ---", file=sys.stderr)
                    sys.exit("Failed to schedule basic block starting at input line " + str(nodes[0].insn.line_no) + ".")
            else:
                test_circular = False
            nodes_scheduled_prev = nodes_scheduled

        # Print scheduled block if debug is enabled.
        if debug:
            print("Can be scheduled as:", file=sys.stderr)
            for syll_idx in range(((syll_count + max_issue - 1) // max_issue) * max_issue):
                if syll_idx in sched_syll:
                    if isinstance(sched_syll[syll_idx], Node):
                        print("  " + str(sched_syll[syll_idx].insn), file=sys.stderr)
                    else:
                        print("  " + sched_syll[syll_idx], file=sys.stderr)
                else:
                    print("  nop", file=sys.stderr)
                if (syll_idx % max_issue) == 7:
                    print(";;", file=sys.stderr)

        # Convert to InstructionBundles.
        bundles = []
        insns = []
        line_no = bb.bundles[0].line_no
        for syll_idx in range(((syll_count + max_issue - 1) // max_issue) * max_issue):
            if syll_idx in sched_syll:
                if isinstance(sched_syll[syll_idx], Node):
                    insns += [sched_syll[syll_idx].insn]
                    line_no = sched_syll[syll_idx].insn.line_no
            if (syll_idx % max_issue) == 7:
                bundle = InstructionBundle(insns, line_no, raw=True)
                insns = []
                if syll_idx < 8:
                    bundle.labels = bb.bundles[0].labels
                bundles += [bundle]

        # If there are no syllables here, this was a basic block with just one
        # or more empty bundles. We still need to output at least one bundle in
        # this case, otherwise labels will be lost.
        if len(bundles) == 0:
            bundle = InstructionBundle([], line_no, raw=True)
            bundle.labels = bb.bundles[0].labels
            bundles = [bundle]

        return bundles

    def fully_resched(self, config, opt):
        bbs = self.split_into_basic_blocks()
        bundles = []
        bundles.append(EntryBundle())
        for bb in bbs:
            bundles += self.fully_resched_bb(bb, config, opt)
            if bundles[-1].has_call():
                bundles.append(CallBundle())
        bundles.append(ExitBundle())

        self.bundles = bundles
        self.succ_cfg = self.build_successor_graph()
        self.pred_cfg = self.build_predecessor_graph(self.succ_cfg)

    def __init__(self, lines):
        self.name = lines[0][0]
        self.bundles = []
        self.split_into_bundles(lines)
        self.succ_cfg = self.build_successor_graph()
        self.pred_cfg = self.build_predecessor_graph(self.succ_cfg)

    def __str__(self):
        return "\n".join(map(str, self.bundles))

    def __repr__(self):
        return "\n".join(map(str, self.bundles))

def read_file(file):
    statements = []
    function = []
    in_func = False
    in_block_comment = False
    line_no = 0
    for line in file:
        line_no = line_no + 1
        line, hash_comment, in_block_comment = parse.strip_comments(line, in_block_comment)
        if line or hash_comment:
            if parse.is_end_function(line):
                statements.append(Function(function))
                function = []
                in_func = False
            if in_func:
                if line:
                    if not re.search(r"\.trace", line):
                        function.append((line.rstrip(), hash_comment, line_no))
            else:
                if hash_comment:
                    statements.append(line + " #" + hash_comment)
                else:
                    statements.append(line)
            if parse.is_start_function(line):
                in_func = True
                continue
    return statements



def main(in_file, out_file, resched, config):

    # Parse the input file into a list of Functions and unknown/unused compiler
    # directives as strings.
    fs = read_file(in_file)

    # Print the output file while we're fixing and optimizing functions.
    for f in fs:

        # Fix and optimize.
        if isinstance(f, Function):

            # Perform register renaming to remove dependencies as much as
            # possible.
            f.fix_load_dependency()
            f.fix_cycles()

            if resched:

                # Reschedule the assembly to make it work for dynamic binaries.
                f.fully_resched(config, config['opt'] >= 1)

                if config['opt'] >= 2:

                    # Try to move syllables arount to increase performance for
                    # low issue widths when stop bits are implemented.
                    f.do_asap(config)
        # Print.
        print(str(f), file=out_file)

def parse_borrow_opt(borrow):
    lanes = borrow.split(".")
    borrow = []
    if len(lanes) != 8:
        sys.exit("Borrow configuration needs to contain 8 lanes.")
    for lane in lanes:
        slots = lane.split(",")
        parsed_slots = []
        for slot in slots:
            if slot:
                try:
                    parsed_slots += [int(slot)]
                except ValueError:
                    sys.exit("Invalid borrow configuration.")
        borrow += [parsed_slots]
    return borrow

def parse_config_opt(config):
    try:
        config_int = int(str(config), 16)
    except ValueError:
        sys.exit("Configuration should be a hex integer.")
    config = [set(), set(), set(), set(), set(), set(), set(), set()]
    for lane_index in range(0, 8):
        lane_config_int = config_int >> ((7-lane_index)*4)
        if lane_config_int & ALU:
            config[lane_index] |= {ALU}
        if lane_config_int & MUL:
            config[lane_index] |= {MUL}
        if lane_config_int & MEM:
            config[lane_index] |= {MEM}
        if lane_config_int & BR:
            config[lane_index] |= {BR}
    return config

default_config = {
    'borrow': [[1],[0],[3],[2],[5],[4],[7],[6]],
    'layout': [{ALU, BR, MUL}, {ALU, MUL, MEM}, {ALU, MUL, BR}, {ALU, MUL},
            {ALU, MUL, BR}, {ALU, MUL}, {ALU, MUL, BR}, {ALU, MUL}],
    'fus':    {ALU: 8, MUL: 4, MEM: 1, BR: 1},
    'opt':    0
    }

if __name__ == '__main__':
    arguments = docopt(opt)
    resched = arguments['--resched']
    config = copy.deepcopy(default_config)
    if arguments['--O1']:
        config['opt'] = 1
    if arguments['--O2']:
        config['opt'] = 2
    if arguments['--borrow']:
        config['borrow'] = parse_borrow_opt(arguments['--borrow'])
    if arguments['--config']:
        config['layout'] = parse_config_opt(arguments['--config'])
        config['fus'] = {ALU: 0, MUL: 0, MEM: 0, BR: 0}
        for lane in config['layout']:
            for unit in lane:
                config['fus'][unit] = config['fus'][unit] + 1
    for res in [(ALU, 'alu'), (MUL, 'mul'), (MEM, 'mem'), (BR, 'br')]:
        if arguments['--n' + res[1]]:
            try:
                nres = int(arguments['--n' + res[1]])
                if nres < 0 or nres > 8:
                    raise ValueError
                config['fus'][res[0]] = nres
            except ValueError:
                sys.exit('Number of ' + res[1] + ' resources must be a number from 0 to 8.')

    with open(arguments['<file>']) as in_file:
        if arguments['-o']:
            out_file = open(arguments['-o'], 'w')
            with open(arguments['-o'], 'w') as out_file:
                main(in_file, out_file, resched, config)
        else:
             main(in_file, sys.stdout, resched, config)

