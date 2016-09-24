class InstructionNode:

    def __init__(self, insn):
        self.insn = insn
        self.ref_count = 0
        self.child = set()
        self.parent = set()
        self.issued = False
        self.index = None
        self.first = 0
        self.last = 7

    def issue(self, index):
        self.index = index
        self.issued = True
        self.update_graph()

    def unissue(self):
        self.index = None
        self.issued = False
        self.update_graph()

    def update_graph(self):
        for node in self.child:
            node.update_index()
        for node in self.parent:
            node.update_index()

    def update_index(self):
        self.first = 0
        self.last = 7
        for node in self.child:
            if (not node.index is None) and node.index > self.first:
                self.first = node.index - (node.index % 2)
        for node in self.parent:
            if (not node.index is None) and node.index < self.last:
                self.last = node.index - (node.index % 2) + 1

    def __str__(self):
        return "{} {}".format(str(self.insn), self.child)

class FollowNode:

    def issue(self, index):
        self.index = index
        self.issued = True

    def unissue(self):
        self.index = None
        self.issued = False

    def __init__(self):
        self.insn = None
        self.ref_count = 0
        self.child = set()
        self.parent = set()
        self.follow_parent = None
        self.issued = False
        self.index = None
        self.first = 0
        self.last = 7

class Graph:

    def __init__(self, insns, config=None):
        self.nodes = []
        self.issued = set()
        for insn in insns:
            self.nodes.append(InstructionNode(insn))
            if insn.has_long_imm():
                self.nodes.append(FollowNode())
                self.nodes[-1].follow_parent = self.nodes[-2]
        self.build_graph()
        if config:
            self.layout = config['layout']
            self.fus = config['fus']
            self.borrow = config['borrow']

    def build_graph(self):
        for node in self.nodes:
            self.update_child(node)

    def update_child(self, node):
        if not node.insn:
            return
        src = node.insn.get_read_registers()
        for index, node2 in enumerate(self.nodes):
            if not node2.insn:
                continue
            if node == node2:
                continue
            if (src.intersection(node2.insn.get_written_registers()) or
                    node2.insn.is_branch()):
                node2.child.add(node)
                node.parent.add(node2)


    def issue(self, node, index):
        node.issue(index)
        self.issued.add(index)

    def unissue(self, node, index):
        node.unissue()
        self.issued.remove(index)

    def get_next(self):
        for node in self.nodes:
            if not node.issued:
                return node

    def can_issue(self, node, issue):
        insn = node.insn
        if issue in self.issued:
            return False
        if not insn:
            if not node.follow_parent.issued:
                return False
            if issue in self.borrow[node.follow_parent.index]:
                return True
            return False
        if not insn.get_fu() in self.layout[issue]:
            return False
        if not insn.has_long_imm():
            return True
        for index in self.borrow[issue]:
            if not index in self.issued:
                return True
        return False

    def scheduled(self):
        for node in self.nodes:
            if not node.issued:
                return False
        return True

    def schedule2(self):
        sched_stack = []
        retry = False
        while True:
            node = self.get_next()
            if not node:
                return True
            if retry:
                retry = False
                start = i+1
            else:
                start = node.first
            end = node.last + 1
            for i in range(start, end):
                if self.can_issue(node, i):
                    self.issue(node, i)
                    sched_stack.append((node, i))
                    break
            else:
                # sched failed. rewind stack
                if not sched_stack:
                    return False
                node, i = sched_stack.pop()
                self.unissue(node, i)
                retry = True

    def update_ref(self, node, update):
        if not node.insn:
            return
        src = node.insn.get_read_registers()
        for node2 in self.nodes:
            if not node2.insn:
                continue
            if node == node2:
                continue
            if not node2.insn:
                continue
            if (src.intersection(node2.insn.get_written_registers()) or
                    node2.insn.is_branch()):
                node2.ref_count = update(node2.ref_count)


    def schedule(self):
        """ return [] if there are no cycles """
        if not self.nodes:
            return []
        for node in self.nodes:
            self.update_ref(node, lambda x: x+1)

        while True:
            node1 = None
            for node in self.nodes:
                if node.ref_count == 0:
                    node1 = node
                    break
            if node1 is None:
                return [node.insn for node in self.nodes]
            self.nodes.remove(node1)
            if not self.nodes:
                return []
            self.update_ref(node, lambda x: x-1)

    def __str__(self):
        result = "\n".join(str(x) for x in self.nodes)
        return result + "\n"




