import re

def strip_comments(input_line, in_block_comment):

    # Remove trailing whitespace and newline.
    input_line = input_line.rstrip()

    # Remove block comments entirely.
    output_line = ""
    pc = ""
    for c in input_line:

        # If we encounter a hash comment, and we are not yet in a block
        # comment, we stop checking for multi-line comments.
        if c == '#' and in_block_comment == False:
            output_line = input_line
            break

        # Detect block comment start (the slash has already been appended at
        # this point so we need to remove it)
        if pc == "/" and c == "*":
            in_block_comment = True
            output_line = output_line[:-1]

        # Detect block comment end.
        if pc == "*" and c == "/":
            in_block_comment = False
            continue

        # Append characters to the output of we're not in a block comment.
        if not in_block_comment:
            output_line += c

        # Remember the previous character.
        pc = c

    # Split the assembly code and hash comments; the latter may contain debug
    # information from the C compiler.
    output_line, dummy, hash_comment = output_line.partition("#")

    return output_line.strip(), hash_comment, in_block_comment

label_re = re.compile(r"^\s*[a-zA-Z0-9?_\.]+:+")

def is_label(line):
    if label_re.search(line):
        return True
    return False

pseudo_re = re.compile(r"^\s*\.([a-zA-Z0-9_])+(?=[\s]|$)")
proc_re = re.compile(r"\.proc")
endp_re = re.compile(r"\.endp")
dcol_re = re.compile(r";;")

def is_psuedo(line):
    if pseudo_re.search(line):
        return True
    return False

def is_end_bundle(line):
    if dcol_re.search(line):
        return True
    return False

def is_start_function(line):
    if proc_re.search(line):
        return True
    return False

def is_end_function(line):
    if endp_re.search(line):
        return True
    return False

reg_str = r'\$[rbl]\d\.\d+'
reg_re = re.compile(reg_str)

def is_register(line):
    if reg_re.search(line):
        return True
    return False

st_re = re.compile(r"st[bhw]")

def is_store(line):
    if st_re.search(line):
        return True
    return False

ld_re = re.compile(r"ld[bhw]")

def is_load(line):
    return ld_re.search(line)

control_re = re.compile(r"br[f]?|return|goto|call")
def is_control(line):
    return control_re.search(line)

cluster_re = re.compile(r"^\s*c(\d+)(.*)$")

stop_re = re.compile(r"stop|nop")

def is_stop(line):
    return stop_re.search(line)

def get_cluster(line):
    match = cluster_re.search(line.strip())
    if match:
        return (int(match.group(1)), match.group(2))
    else:
        return (0, line)

mnem_re = re.compile(r"^\s*(\w+)(.*)$")

def get_mnemonic(line):
    match = mnem_re.search(line)
    if match:
        return (match.group(1).strip(), match.group(2))
    else:
        return (None, None)

entry_re = re.compile(r'^\s*\.entry')
def is_entry(line):
    match = entry_re.search(line)
    if match:
        return True
    return False

exit_re = re.compile(r'^\s*\.return')
def is_exit(line):
    match = exit_re.search(line)
    if match:
        return True
    return False

call_re = re.compile(r'^\s*\.call')
def is_call(line):
    if call_re.search(line):
        return True
    return False

global_re = re.compile(r'^\s*\.global')
def is_global(line):
    if global_re.search(line):
        return True
    return False

nopinsertion_re = re.compile(r'^\s*\.(no)?nopinsertion')
def is_nopinsertion(line):
    if nopinsertion_re.search(line):
        return True
    return False

balignl_re = re.compile(r'^\s*\.balignl')
def is_balignl(line):
    if balignl_re.search(line):
        return True
    return False

type_re = re.compile(r'^\s*\.type')
def is_type(line):
    if type_re.search(line):
        return True
    return False

arg_re = re.compile(r'arg\([^\)]*\)')
def get_arg_regs(line):
    match = arg_re.search(line)
    if match:
        return get_regs(match.group())
    return set()

ret_re = re.compile(r'ret\(.*\)')
def get_ret_regs(line):
    match = ret_re.search(line)
    if match:
        return get_regs(match.group())
    return set()


def get_regs(line):
    return reg_re.findall(line)



