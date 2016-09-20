#!/usr/bin/python

from __future__ import print_function

import sys
import paths
import os

# Look for the file (rather, see if paths found it)
if 'manifest' not in paths.dirs:
    print('Error: could not find archive-manifest.')
    sys.exit(1)

# Load the file.
with open(paths.dirs['manifest'], 'r') as f:
    manifest = f.readlines()

# Preprocess: strip comments and whitespace.
manifest = [x.split('#')[0].strip() for x in manifest]

# Split the file contents up into the sections.
entry = None
data = {}
for line in manifest:
    if line.startswith('[') and line.endswith(']'):
        entry = line[1:-1].strip()
        data[entry] = []
    elif line != '':
        if entry is not None:
            data[entry].append(line)

# Find the platform name.
if 'name' not in data:
    print('Error: no [name] in archive.manifest.')
    sys.exit(1)
name = data['name'][0]

# Find the platform name.
if 'ptag' not in data:
    print('Error: no [ptag] in archive.manifest.')
    sys.exit(1)
ptagfile = paths.dirs['platform'] + os.sep + data['ptag'][0]

# Find the bitfile name.
if 'bitfile' not in data:
    print('Error: no [bitfile] in archive.manifest.')
    sys.exit(1)
bitfile = paths.dirs['platform'] + os.sep + data['bitfile'][0]

# Processes a list of filenames. Directories are expanded to their contents.
def process_filenames(ls):
    fs = []
    for l in ls:
        
        # Split input and output if both are specified.
        l = l.split('->', 1)
        l = [x.strip() for x in l]
        i = l[0]
        o = l[-1]
        
        # Handle variables for the input path.
        for path_name in paths.dirs:
            i = i.replace('$' + path_name.upper(), paths.dirs[path_name])
        if '$' in i:
            print('Error: failed to parse pathspec (unknown variable): ' + i)
            sys.exit(1)
        
        # Handle variables for the output path.
        o = o.replace('$ROOT', '.')
        o = o.replace('$PLATFORM', 'platform/%s' % name)
        if '$' in o:
            print('Error: failed to parse pathspec (unknown variable): ' + o)
            sys.exit(1)
        
        # Clean up the paths a little bit.
        while i.startswith('./'):
            i = i[2:]
        while o.startswith('./'):
            o = o[2:]
        
        if os.path.isdir(i):
            def expand(i, o, fs):
                for f in os.listdir(i):
                    if os.path.isdir(i + os.sep + f):
                        expand(i + os.sep + f, o + os.sep + f, fs)
                    else:
                        fs.append((i + os.sep + f, o + os.sep + f))
            expand(i, o, fs)
        elif os.path.isfile(i):
            fs.append((i, o))
    return fs

# Processes the sources file list.
def sources_f():
    global data
    if 'sources' in data:
        return process_filenames(data['sources'])
    else:
        return []

# Processes the logs file list.
def logs_f():
    global data
    if 'logs' in data:
        return process_filenames(data['logs'])
    else:
        return []

