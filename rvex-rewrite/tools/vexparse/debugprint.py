import sys
print_warnings = False

def warn(msg, line=None):
    if not print_warnings:
        return
    if line:
        print('{} on line {}'.format(msg, line), file=sys.stderr)
    else:
        print(msg, file=sys.stderr)

