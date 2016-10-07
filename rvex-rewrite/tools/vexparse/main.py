import re
import sys
import copy
import argparse
from collections import defaultdict
from instructions import FU, parse_instruction
from bundle import CallBundle, EntryBundle, ExitBundle, InstructionBundle
from debugprint import warn
import debugprint
import parse
import vex
import scheduler
import graph

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

    def split_into_bundles(self, lines):
        name = []
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
                name.append(line)
                continue
            elif parse.is_end_bundle(line):
                insns = [parse_instruction(x[0], x[1], x[2]) for x in bundle_lines]
                for insn in insns:
                    if insn.is_call() or insn.is_return():
                        insn.pseudo_op = pseudo_op
                        break
                self.bundles.append(InstructionBundle(insns, bundle_line_no, name, raw=True))
                bundle_lines, name = ([], [])
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

    def fix_same_reg_writes(self):
        return any(bundle.fix_same_reg_writes() for bundle in self.bundles)

    def fix_return_and_stack_pop(self):
        for i, bundle in enumerate(self.bundles):
            bundle.fix_stack_pop()

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

    def new_resched(self, config):
        self.bundles = scheduler.reschedule(self.bundles, config)

    def __init__(self, lines):
        self.name = lines[0][0]
        self.bundles = []
        self.split_into_bundles(lines)
        self.succ_cfg = self.build_successor_graph()
        self.pred_cfg = self.build_predecessor_graph(self.succ_cfg)

    def __str__(self):
        return "\n".join(map(str, (b for b in self.bundles if not b.is_fake())))


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
    debugprint.print_warnings = True

    # Parse the input file into a list of Functions and unknown/unused compiler
    # directives as strings.
    fs = read_file(in_file)

    # Print the output file while we're fixing and optimizing functions.
    for f in fs:

        # Fix and optimize.
        if isinstance(f, Function):

            # Perform register renaming to remove dependencies as much as
            # possible.
            f.fix_return_and_stack_pop()
            if f.fix_same_reg_writes():
                exit(1)
            f.fix_load_dependency()
            f.fix_cycles()

            if resched and config['opt'] > 0:
                f.new_resched(config)

        # Print.
        print(str(f), file=out_file)

def parse_borrow_opt(borrow):
    lanes = borrow.split(".")
    if len(lanes) != 8:
        raise argparse.ArgumentTypeError(
                "Borrow configuration needs to contain 8 lanes.")
    try:
        return [[int(slot) for slot in lane.split(',')] for lane in lanes]
    except ValueError:
        raise argparse.ArgumentTypeError(
                "Invalid borrow configuration.")

def parse_config_opt(config):
    if len(config) != 8:
        raise argparse.ArgumentTypeError(
                "Configuration needs to contain 8 lanes.")
    try:
        return [set(t for t in [FU.ALU, FU.MUL, FU.MEM, FU.BR] if int(x, 16) & t) for x in config]
    except ValueError:
        raise argparse.ArgumentTypeError(
                "Configuration should be a hex integer.")

default_config = {
    'borrow': [[1],[0],[3],[2],[5],[4],[7],[6]],
    'layout': [{FU.ALU, FU.BR, FU.MUL}, {FU.ALU, FU.MUL, FU.MEM}, {FU.ALU, FU.MUL, FU.BR}, {FU.ALU, FU.MUL},
            {FU.ALU, FU.MUL, FU.BR}, {FU.ALU, FU.MUL}, {FU.ALU, FU.MUL, FU.BR}, {FU.ALU, FU.MUL}],
    'fus':    {FU.ALU: 8, FU.MUL: 4, FU.MEM: 1, FU.BR: 1},
    'opt':    0
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="""Reschedule rvex instructions to improve performance of
        generic binaries.""")
    parser.add_argument('file',
            help='''Input file name.''')
    parser.add_argument('-o', metavar='outfile', dest='outfile',
            help='Output file name.')
    parser.add_argument('--borrow', type=parse_borrow_opt,
            help='''Supply borrow configuration. Use . as lane separator
            and , as slot separator, for example 1.0.3,0.2,1.5,2.4,3.7,4.6,5''')
    parser.add_argument('--config', type=parse_config_opt,
            help='''Lane resource configuration, specified as hex number,
            with a nibble for each lane. Bit 0 is used for ALU,
            bit 1 for MUL, bit 2 for MEM and bit 3 for BR.''')
    parser.add_argument('--nalu', type=int, choices=range(0,9),
            help='''Number of ALU resources. If not specified, the value is
            taken from --config.''')
    parser.add_argument('--nmul', type=int, choices=range(0,9),
            help='''Number of MUL resources. If not specified, the value is
            taken from --config.''')
    parser.add_argument('--nmem', type=int, choices=range(0,9),
            help='''Number of MEM resources. If not specified, the value is
            taken from --config.''')
    parser.add_argument('--nbr', type=int, choices=range(0,9),
            help='''Number of BR resources. If not specified, the value is
            taken from --config.''')
    parser.add_argument('--resched', action='store_true',
            help='''Allow rescheduling in addition to register renaming to fix
            dependencies.''')
    parser.add_argument('-O', choices=range(0,3), default=0, type=int,
            help='''Select the optimizations that will be performed.
            0 only allows NOP-insertion when rescheduling. 1 Tries to optimize
            code size (and thus speed). 2 is the same as 1, but additionally it
            reorders instructions to smoothen bundle sizes. This argument is
            ignored if --resched is not given.''')
    args = parser.parse_args()
    resched = args.resched
    config = copy.deepcopy(default_config)
    config['opt'] = args.O
    if args.borrow:
        config['borrow'] = args.borrow
    if args.config:
        config['layout'] = args.config
        config['fus'] = {FU.ALU: 0, FU.MUL: 0, FU.MEM: 0, FU.BR: 0}
        for lane in config['layout']:
            for unit in lane:
                config['fus'][unit] = config['fus'][unit] + 1
    if args.nalu:
        config['fus'][FU.ALU] = args.nalu
    if args.nmul:
        config['fus'][FU.MUL] = args.nmul
    if args.nmem:
        config['fus'][FU.MEM] = args.nmem
    if args.nbr:
        config['fus'][FU.BR] = args.nbr

    with open(args.file) as in_file:
        if args.outfile:
            with open(args.outfile, 'w') as out_file:
                main(in_file, out_file, resched, config)
        else:
             main(in_file, sys.stdout, resched, config)

