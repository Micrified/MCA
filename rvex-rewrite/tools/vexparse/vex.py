import re
import itertools


class Argument:

    def __init__(self, line):
        self.line = line

    def __str__(self):
        return self.line


class Register:

    def get_free_reg(self, used):
        return

    def __eq__(self, other):
        try:
            if (self.n == other.n and self.c == other.c and self.t == other.t
                    and isinstance(other, self.__class__)):
                return True
            else:
                return False
        except:
            return False

    def __lt__(self, other):
        if not isinstance(other, Register):
            raise TypeError()
        if self.c != other.c:
            raise ValueError("Cannot compare different register clusters")
        if self.t != other.t:
            return self.t < other.t
        if self.n >= other.n:
            return False
        return True

    def __init__(self, c, n):
        self.c = int(c)
        self.n = int(n)

    def __str__(self):
        return "${0}{1}.{2}".format(self.t, self.c, self.n)

    def __repr__(self):
        return "{0}({1}, {2})".format(self.__class__.__name__, self.c, self.n)

    def __hash__(self):
        return hash(self.n)

class GeneralRegister(Register):

    def __init__(self, c, n):
        self.t = 'r'
        super().__init__(c, n)

    def get_free_reg(self, used):
        for i in range(11, 56):
            new_reg = GeneralRegister(0, i)
            if not new_reg in used:
                return new_reg
        return

class BranchRegister(Register):

    def __init__(self, c, n):
        self.t = 'b'
        super().__init__(c, n)

    def get_free_reg(self, used):
        for i in range(8):
            new_reg = BranchRegister(0, i)
            if not new_reg in used:
                return new_reg
        return

class LinkRegister(Register):

    def __init__(self, c, n):
        self.t = 'l'
        super().__init__(c, n)

fixed_regs = {GeneralRegister(0, x) for x in itertools.chain(range(0, 11),
    range(56,64))}

reg_re = re.compile(r"\$([rbl])(\d+)\.(\d+)")

def parse_register(reg):
    match = reg_re.search(reg)
    if match:
        if match.group(1) == 'b':
            return BranchRegister(match.group(2), match.group(3))
        if match.group(1) == 'r':
            return GeneralRegister(match.group(2), match.group(3))
        if match.group(1) == 'l':
            return LinkRegister(match.group(2), match.group(3))
    else:
        raise ValueError("'{0}' is not a register".format(reg))
