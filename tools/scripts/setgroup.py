
from plumbum import local
import sys
import os
import random

if len(sys.argv) != 2:
    print('Error: no group number specified...')
    sys.exit(1)
try:
    group = int(sys.argv[1])
    if group > 99 or group < 0:
        raise ValueError()
except ValueError:
    print('Error: invalid group number specified...')
    sys.exit(1)

# Store the group number as a file in the workspace.
with open('/home/user/workspace/.mcagroup', 'w') as f:
    f.write(str(group))

# Configure dropbox. Update: no need to do this now; we're now using the
# websocket server.
#dropbox_folder = '/home/user/.dropbox-folder/Dropbox'
#dropbox_group = 'group%02d' % group
#boardserver = '/home/user/boardserver'
#os.chdir(dropbox_folder)
#files = local['ls']().split()
#local['dropbox']['exclude']['add'](*files)
#local['dropbox']['exclude']['remove'](dropbox_group)
#local['rm']['-f'](boardserver)
#local['ln']['-s'](dropbox_folder + '/' + dropbox_group, boardserver)

# Pick four benchmarks for the group. The first two of which will be used for
# assignment 1, all four will be used for assignment 2.
random.seed(group * 314159265)
benchmarks = [
    'adpcm',
    'bcnt',
    'blit',
    'compress',
    'convolution_3x3',
    'convolution_5x5',
    'convolution_7x7',
    'crc',
    'des',
    'engine',
    'fir',
    'g3fax',
    'greyscale',
    'jpeg',
    'matrix',
    'median',
    'pocsag',
    'pocsag',
    'qurt',
    'ucbqsort',
    'v42',
    'x264'
]
random.shuffle(benchmarks)
unique_benchmarks = set()
picked_benchmarks = []
for benchmark in benchmarks:
    if benchmark.split('_')[0] not in unique_benchmarks:
        unique_benchmarks.add(benchmark.split('_')[0])
        picked_benchmarks.append(benchmark)
        if len(picked_benchmarks) == 4:
            break

print('')
def bm(i):
    return '\033[1;33m%s\033[0m' % picked_benchmarks[i]
print('For assignment 1 your group should use:')
print('  %s and %s' % (bm(0), bm(1)))
print('')
print('For assignment 2 your group should use:')
print('  %s, %s, %s and %s' % (bm(0), bm(1), bm(2), bm(3)))
print('')
print('These names are stored in the \'benchmarks\' file in the')
print('assignment directories.')

with open('/home/user/workspace/assignment1/benchmarks', 'w') as f:
    f.write('Group %d assignment 1 benchmarks:\n\n' % group)
    f.write('%s\n' % picked_benchmarks[0])
    f.write('%s\n' % picked_benchmarks[1])

with open('/home/user/workspace/assignment2/benchmarks', 'w') as f:
    f.write('Group %d assignment 2 benchmarks:\n\n' % group)
    f.write('%s\n' % picked_benchmarks[0])
    f.write('%s\n' % picked_benchmarks[1])
    f.write('%s\n' % picked_benchmarks[2])
    f.write('%s\n' % picked_benchmarks[3])

sys.exit(0)
