#!/usr/bin/python3

import sys

# Print usage.
if len(sys.argv) < 3:
    print('usage: [python3] parse_compile_config.py <config.compile> <core> [target]')
    print('')
    print('If target not specified:')
    print('  Returns the list of targets specified for core <core> in configuration file')
    print('  <config.compile>')
    print('')
    print('If target specified:')
    print('  Returns the additional compile flags for the given target as specified in')
    print('  <config.compile> for core <core>.')
    print('')
    sys.exit(2)

# Read the file.
with open(sys.argv[1], 'r') as f:
    lines = f.readlines()

# Strip comments.
lines = [line.split('#', 1)[0].strip() for line in lines]
lines = [line for line in lines if line]

# Look for the specified [core] line.
new_lines = []
found = False
for line in lines:
    if not found:
        if line == '[%s]' % sys.argv[2]:
            found = True
            continue
    else:
        if line.startswith('[') and line.endswith(']'):
            break
        else:
            new_lines.append(line)
if not found:
    print('Error: could not find [%s] in config.compile.' % sys.argv[1], file=sys.stderr)
    sys.exit(1)
lines = new_lines

# Output list of targets if no target specified.
if len(sys.argv) == 3:
    targets = [line.split()[0] for line in lines]
    targets = [target for target in targets if target != 'OTHERS']
    for line in lines:
        target = line.split()[0]
        if target and target != 'OTHERS':
            print(target)
    sys.exit(0)

# Output compile flags for the given target.
others_args = ''
for line in lines:
    target, args = line.split(maxsplit=1)
    if target == sys.argv[3] or target == sys.argv[3] + '-sub':
        print(args)
        sys.exit(0)
    elif target == 'OTHERS':
        other_args = args
print(other_args)
sys.exit(0)
