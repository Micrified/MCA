import os
import sys

dirs = {}

# Find the rvex repository root directory.
d = '.'
for i in range(20):
    files = os.listdir(d)
    
    # Look for the platform directory.
    if 'archive-manifest' in files and 'platform' not in dirs:
        dirs['platform'] = d
        dirs['manifest'] = d + os.sep + 'archive-manifest'
    
    # Look for the rvex-rewrite directory.
    if 'versions' in files and 'tools' in files and 'platform' in files and 'lib' in files:
        dirs['root'] = d
        break
    
    if 'rvex-rewrite' in files:
        dirs['root'] = d + os.sep + 'rvex-rewrite'
        break
    
    if d == '.':
        d = '..'
    else:
        d += os.sep + '..'
if 'root' not in dirs:
    print("Error: couldn't find rvex repository root directory.")
    sys.exit(1)

dirs['versions'] = dirs['root'] + os.sep + 'versions'
dirs['vtools'] = dirs['versions'] + os.sep + 'tools'

if len(sys.argv) > 1:
    dirs['arg'] = sys.argv[1]
