#!/usr/bin/python3

import sys
import os
import time
from plumbum import local, FG

# Check command line
if len(sys.argv) != 5:
    print('Usage: [python3] boardserver_run.py <server-dir> <fpga.bit> <code.srec> <results-dir>')
    sys.exit(2)

# Check boardserver directory.
boardserver = sys.argv[1]
if not os.path.isdir(boardserver):
    print('\033[31;1mError: boardserver directory does not exist. Did you run the set group script?\033[0m')
    print('Was looking for %s' % boardserver)
    sys.exit(1)

# Check srec.
srec = sys.argv[3]
if not os.path.exists(srec):
    print('\033[31;1mError: srec not found. Please run compilation first.\033[0m')
    print('Was looking for %s' % srec)
    sys.exit(1)

# Check result directory.
resultdir = sys.argv[4]
if not os.path.isdir(resultdir):
    local['mkdir']('-p', resultdir)
    if not os.path.isdir(resultdir):
        print('\033[31;1mError: result directory does not exist.\033[0m')
        print('Was looking for %s' % resultdir)
        sys.exit(1)

# Check bitfile.
bitfile = sys.argv[2]
if not os.path.exists(bitfile):
    print('\033[1mError: bitfile not found.\033[0m')
    print('Was looking for %s' % bitfile)
    print('Would you like to run synthesis now? This will break any synthesis commands')
    print('running in this configuration directory and will delete data from previous')
    print('runs (if any) in this directory. Are you sure? [y/n]')
    if input() != 'y':
        sys.exit(0)
    local['make']['synth'] & FG

# Create a tar archive with the bitfile and srec inside.
token    = ('%.5f' % time.time()).replace('.', '')
tempdir  = '/tmp/boardserver-' + token
tempfile = tempdir + os.sep + token + '.tgz'
tempbit  = tempdir + os.sep + 'fpga.bit'
tempsrec = tempdir + os.sep + 'code.srec'

requestfile = boardserver + os.sep + token + '.tgz'
statusfile  = boardserver + os.sep + token + '.stat'
resultfile  = boardserver + os.sep + token + '.result.tgz'

local['mkdir']('-p', tempdir)
local['cp'](bitfile, tempbit)
local['cp'](srec, tempsrec)
local['tar']('czf', tempfile, '-C', tempdir, 'fpga.bit', 'code.srec')

# Move the tar archive to the dropbox folder and remove the temp folder.
local['mv'](tempfile, boardserver)
local['rm']('-rf', tempdir)

# Scan for status messages.
t = 0
try:
    print('\033[1mWaiting for boardserver, ctrl+C to cancel...\033[0m')
    complete = False
    status = 'waiting for response'
    while not complete:
        
        # Wait for one second.
        time.sleep(1)
        t += 1
        
        # Figure out what the current status is.
        if os.path.exists(resultfile):
            status = 'done.'
            complete = True
        elif os.path.exists(statusfile):
            try:
                with open(statusfile, 'r') as f:
                    status = f.read().split('\n')[0].strip()
            except IOError:
                pass
        
        # Print the current status.
        print('\033[A\033[1mWaiting for boardserver, ctrl+C to cancel... %d sec%s\033[0m\033[K' % (
            t, (', ' + status) if status else ''))

except KeyboardInterrupt:
    local['rm']('-f', requestfile, statusfile, resultfile)
    print('\033[31;1mCancelled.\033[0m')
    sys.exit(1)

# Complete the request by removing all related files from the dropbox folder ASAP.
# The boardserver will also do this after some time in case something goes wrong
# in the VM.
local['mv'](resultfile, resultdir + os.sep + 'results.tgz')
local['rm']('-f', requestfile, statusfile, resultfile)

# Extract the result data.
with local.cwd(resultdir):
    local['tar']('xzf', 'results.tgz')
    local['rm']('-f', 'results.tgz')

# Dump the status log to the console.
logfile = resultdir + os.sep + 'boardserver.log'
try:
    with open(logfile, 'r') as f:
        print(f.read())
    local['rm']('-f', logfile)
except IOError:
    print('Did not receive status log file from board server...')
