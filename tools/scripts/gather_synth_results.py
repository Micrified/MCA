#!/usr/bin/python3

import sys
import os

if len(sys.argv) < 4:
    print('Usage: [python3] gather_synth_results.py <xilinx.log> <timing.twr> <results dir>')
    sys.exit(2)

# Read xilinx.log to look for area utilization data and timing score.
area = []
area_region = False
timing_score = None
timing_score_line = ''
with open(sys.argv[1], 'r') as f:
    for line in f:
        if line.startswith('Slice Logic Utilization:'):
            if not area:
                area_region = True
        if area_region:
            area.append(line)
            if line.startswith('Average Fanout of Non-Clock Nets'):
                area_region = False
        if line.startswith('Timing Score:'):
            timing_score_line = line
            try:
                timing_score = int(line[14:].split()[0])
            except ValueError:
                pass
area = ''.join(area)

# Print the area utilization report.
print('\033[1mArea utilization dump:\033[0m')
print('')
print(area)

# Output a message depending on the timing score.
print('')
print('')
print('#'*100)
if timing_score is None:
    print('# \033[31;1mError parsing logs; could not determine if constraints were met.\033[0m')
elif timing_score != 0:
    print('# \033[31;1mYour design did not meet the timing constraints. That means that it probably won\'t work right.\033[0m')
    print('# \033[31;1mYour design may be too complex. Timing score (lower is better, should be 0): %d\033[0m' % timing_score)
else:
    print('# \033[32;1mSynthesis completed successfully.\033[0m')
print('#'*100)
print('')
print('')

# Dump the area utilization to a file.
with open(sys.argv[3] + os.sep + 'area.txt', 'w') as f:
    f.write(area)

# Dump the timing report.
with open(sys.argv[3] + os.sep + 'timing.txt', 'w') as f:
    if timing_score == 0:
        f.write('All timing constraints were met.\n')
    else:
        f.write('ERROR: there are some timing problems with your design.\n')
        f.write('Your design is probably too complex. The timing report is included below.\n\n')
        f.write(timing_score_line + '\n')
        with open(sys.argv[2], 'r') as f2:
            f.write(f2.read())

