import math
from instructions import FU, EndBBInstruction
from collections import defaultdict
from bundle import BundleScheduler, InstructionBundle, EntryBundle, CallBundle, ExitBundle
from debugprint import warn


class Node:
    """Node used for representing dependencies between instructions."""

    def cost(self, node):
        '''Determine the delay required from this node to the node 'node'.'''
        cost = self.insn.cost()
        if isinstance(node, EndBBNode):
            return cost - node.delay
        return cost

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
        self.prio = 0
        self.start = 0

    def __repr__(self):
        return "Node({})".format(repr(self.insn))

    def __str__(self):
        return "{}: {} {}".format(str(self.insn), self.index,
                self.insn.has_long_imm())


class EndBBNode(Node):
    """Node used for representing dependencies to the next BasicBlock."""

    def __init__(self, index, delay, succ_regs):
        self.index = index
        self.delay = delay
        self.read = set()
        if succ_regs:
            self.read = set(succ_regs.keys())
            self.succ_regs = succ_regs
        self.written = set()
        self.insn = EndBBInstruction()
        self.raw = set()
        self.war = set()
        self.waw = set()
        self.rbw = set()
        self.wbr = set()
        self.wbw = set()

    def __str__(self):
        return 'EndBBNode {}'.format(self.delay)


def calc_prio(nodes):
    '''Calculate the priority for selecting instructions for schedulign.
    The priority is based on the delay from that instruction to reach the
    final instruction in the basic block.'''
    roots = set()
    visited = set()
    for n in nodes:
        n.prio = 0
    while True:
        for n in nodes:
            if n in visited:
                continue
            if (all(x in visited for x in n.wbr) and
                    all(x in visited for x in n.rbw) and
                    all(x in visited for x in n.wbw)):
                roots.add(n)
        if not roots:
            break
        #Select the instructions on alphabetical order, just to ensure
        #consistent results to make debugging easier.
        node = min(roots, key=lambda x: str(x))
        prios = [node.prio]
        if node.wbr:
            prios.append(max(x.prio + node.cost(x) for x in node.wbr))
        if node.rbw:
            prios.append(max(x.prio for x in node.rbw))
        if node.wbw:
            prios.append(max(x.prio + 1 for x in node.wbw))
        node.prio = max(prios)
        visited.add(node)
        roots.remove(node)
    if not all([x in visited for x in nodes]):
        import pprint
        pprint.pprint(nodes)
        warn('not all prios calculated', nodes[0].insn.line_no)
        exit(1)

def build_raw_graph(nodes):
    """Build the read after write dependency graph.
    If node1 has node2 in its raw set, it means that node1 must be executed
    after node2 has executed, and enough cycles have passed for the data to be
    available."""
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

def build_war_graph(nodes):
    """Build the write after read dependency graph.
    If node1 has node2 in its war set, it means that node1 must be executed
    after, or in the same cycle as node2, and not before."""
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

def build_mem_graph(nodes):
    """Build the memory dependency graph. (write after write)
    If node1 has node2 in its waw set, it means that node1 must be executed at
    least 1 cycle after node2. This ensures that memory operations keep the
    original execution order during rescheduling."""
    for node in nodes:
        if node.insn.get_fu() != FU.MEM:
            continue
        for node2 in nodes:
            if node == node2:
                continue
            if node.index >= node2.index:
                continue
            if node2.insn.get_fu() != FU.MEM:
                continue
            node.wbw.add(node2)
            node2.waw.add(node)
            break

def build_control_graph(nodes):
    """Build the control dependency graph.
    Each instruction whose results are not read by any other instruction
    gets an additional war dependency with any branch instruction in the basic
    block. This ensures that the branch instruction is always the last one in
    the basic block."""
    for node in nodes:
        if node.wbr or node.wbw:
            continue
        for node2 in nodes:
            if node == node2:
                continue
            if node2.insn.is_branch():
                node2.war.add(node)
                node.rbw.add(node2)

def update_ready_list(nodes):
    """Scan the set of nodes for any instruction that has all its dependencies
    satisfied and return them.
    Also sets the nodes minimum start position based on the final index that its
    predecessors were scheduled in."""
    ready = set()
    for n in nodes:
        if (all(not x.index is None for x in n.raw) and
                all(not x.index is None for x in n.war) and
                all(not x.index is None for x in n.waw)):
            ready.add(n)
        s = [0]
        if n.raw:
            s.extend(x.index + x.cost(n) for x in n.raw if not
                    x.index is None)
        if n.war:
            s.extend(x.index for x in n.war if not x.index is None)
        if n.waw:
            s.extend(x.index + 1 for x in n.waw if not x.index is None)
        n.start = max(s)
    return ready

class BasicBlock:

    def build_instruction_graph(self, succ_regs):
        nodes = []
        for index, bundle in enumerate(self.bundles):
            for insn in bundle.insns:
                nodes.append(Node(insn, index, len(self.bundles)))
        if succ_regs:
            #add fake instruction with delay of 1
            #this makes the fake instruction end up at the latest in the last
            #bundle that should be in the basic block, instead of one bundle
            #later.
            nodes.append(EndBBNode(len(self.bundles), 1, succ_regs))
        build_raw_graph(nodes)
        build_war_graph(nodes)
        build_mem_graph(nodes)
        build_control_graph(nodes)
        return nodes

    def get_read_registers(self):
        '''Get the registers read in the first couple of instruction bundles of
        this basic block.'''
        # currently the maximum number of cycles an instruction takes is 2.
        max_delay = 2
        # we only have to look at the first max_delay - 1 bundles
        # since anything read after that should be fine.
        # if max delay is ever changed, this should be changed to take into
        # account dependencies across multiple bundles.
        read = {}
        written = set()
        for i, b in enumerate(self.bundles[:max_delay-1]):
            new_read = b.get_read()
            for r in new_read - written:
                read[r] = i
            written |= b.get_written()
        return read


    def reschedule(self, config):
        """Reschedule instructions to reduce variation of ILP in a basic block
        as much as possible.
        Input:
            config - the configuration of the processor to schedule for.
        Algorithm:
            Build instruction dependency graph
            Calculate scheduling priority of each instruction
            Add instructions with satisfied dependencies to ready queue.
            Select instruction from ready list with lowest scheduling freedom.
            If the ready list is empty, exit the loop.
            Find bundle that increases total cost the least if the instruction
            is scheduled there.
            If no valid bundle is found, increase the maximum number of bundles
            in the basic block and try again.
            If a valid schedule is found, remove the node from the ready set, and
            go back to step 3."""
        if self.successor and not self.successor.scheduled:
            warn('Error: successor not scheduled')
            exit(1)
        succ_regs = None
        if self.successor:
            succ_regs = self.successor.get_read_registers()
        nodes = self.build_instruction_graph(succ_regs)
        to_schedule = set(nodes)
        ready = set()
        scheduled = defaultdict(list)
        calc_prio(nodes)
        if len(nodes) == 0:
            self.scheduled = True
            return
        total_length = max(nodes, key=lambda x: x.prio).prio
        total_length = max(math.ceil(len(nodes)/8) - 1, total_length)
        for n in nodes:
            n.index = None
        repeat = 0
        while True:
            ready |= update_ready_list(to_schedule)
            if not ready:
                break
            node = min(ready,
                       key=lambda x: (total_length - x.prio - x.start,
                                      total_length - x.prio, x.insn.line_no))
            if isinstance(node, EndBBNode):
                if node.start > total_length:
                    total_length = node.start
                node.index = node.start
                ready.remove(node)
                to_schedule.remove(node)
                nodes.remove(node)
                continue
            end = total_length - node.prio
            start = node.start
            selected = []
            for index in range(start, end+1):
                new_nodes = set(scheduled[index])
                b = BundleScheduler(config)
                before = b.cost(b.size(new_nodes))
                if b.size(new_nodes) == 8:
                    # this bundle is full, skip to the next
                    continue
                # if a more than 8 instructions want to be placed in a bundle,
                # give that bundle a penalty for selection
                c = 0
                penalty = 0
                for x in to_schedule:
                    if index == total_length - x.prio:
                        c += 1
                if b.size(new_nodes) + c > 8:
                    # lots of nodes for this bundle give a penalty
                    penalty = 2
                new_nodes.add(node)
                if not b.schedule2([a.insn for a in new_nodes]):
                    continue
                after = b.cost(b.size(new_nodes))
                size = b.size(new_nodes)
                selected.append((after - before + penalty, index, size))
            if not selected:
                # keep track of the number of times we increased the schedule
                # length. If greater than the actual number of instructions we
                # are probably in some kind of infinite loop, so just give up.
                if repeat > len(nodes):
                    warn('cannot schedule basic block', self.bundles[0].line_no)
                    exit(1)
                repeat += 1
                # increase total length to give more scheduling freedom
                total_length += 1
                warn('expanding basic block {} times'.format(repeat),
                     node.insn.line_no)
                continue
            node.index = min(selected)[1]
            scheduled[node.index].append(node)
            to_schedule.remove(node)
            ready.remove(node)
        # The last node is the end node. The total number of bundles is equal to
        # its index + 1
        bundles = []
        for i in range(0, total_length+1):
            # find all instructions scheduled for this index and add them to a
            # new instruction bundle
            bundles.append(InstructionBundle([n.insn for n in scheduled[i]],
                0, raw=True))
            # copy over labels from first bundle in basic block
            if i == 0 and self.bundles[0].labels:
                bundles[0].labels = self.bundles[0].labels
        if len(bundles) > len(self.bundles):
            if len(self.bundles[0].insns) > 0:
                warn('new length: {} vs {}'.format(len(bundles),
                     len(self.bundles)), self.bundles[0].insns[0].line_no)
            else:
                warn('new length: {} vs {}'.format(len(bundles),
                     len(self.bundles)))
        self.scheduled = True
        self.bundles = bundles

    def __init__(self, bundles):
        self.bundles = bundles
        self.scheduled = False
        self.successor = None

    def __str__(self):
        return "\n".join(str(bundle) for bundle in self.bundles)

def split_into_basic_blocks(insn_bundles):
    """Split the list of instruction bundles into a list of BasicBlocks."""
    bbs = []
    bundles = []
    for bundle in insn_bundles:
        if bundle.is_fake():
            continue
        if bundle.begins_bb() and bundles:
            new_bb = BasicBlock(bundles)
            if bbs:
                if ('next' in bbs[-1].bundles[-1].get_destination() and
                        not bbs[-1].bundles[-1].has_call()):
                    bbs[-1].successor = new_bb
            bbs.append(new_bb)
            bundles = []
        bundles.append(bundle)
        if bundle.ends_bb():
            new_bb = BasicBlock(bundles)
            if bbs:
                if ('next' in bbs[-1].bundles[-1].get_destination() and
                        not bbs[-1].bundles[-1].has_call()):
                    bbs[-1].successor = new_bb
            bbs.append(new_bb)
            bundles = []
    if bundles:
        new_bb = BasicBlock(bundles)
        if bbs:
            if ('next' in bbs[-1].bundles[-1].get_destination() and
                    not bbs[-1].bundles[-1].has_call()):
                bbs[-1].successor = new_bb
        bbs.append(new_bb)
    return bbs

def reschedule(bundles, config):
    """Reschedule the instructions in bundles.

    First reschedule each basic block in reverse order. We use reverse order so
    that each basic block can see if its results are read in the next basic
    block. This is so we know if the result of a multi cycle operation (load or
    multiply) will be used in the next bundle.
    Return the list of rescheduled instruction bundles."""
    bbs = split_into_basic_blocks(bundles)
    for bb in reversed(bbs):
        bb.reschedule(config)
    bundles = []
    bundles.append(EntryBundle())
    for bb in bbs:
        bundles.extend(bb.bundles)
        if bundles[-1].has_call():
            bundles.append(CallBundle())
    bundles.append(ExitBundle())
    return bundles

