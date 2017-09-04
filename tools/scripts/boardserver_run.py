#!/usr/bin/python3

import sys
import os
import time
from plumbum import local, FG

# Check command line
if len(sys.argv) != 5:
    print('Usage: [python3] boardserver_run.py <server> <fpga.bit> <code.srec> <results-dir>')
    print('<server> can be a dropbox directory or a websocket server address of the form <host>:<port>:<group number>')
    sys.exit(2)

# Figure out if we should use the dropbox or websocket transfer protocol.
boardserver = sys.argv[1]
try:
    if os.path.isdir(boardserver):
        protocol = 'dropbox'
    elif len(boardserver.split(':')) == 3:
        protocol = 'websocket'
        boardserver = boardserver.split(':')
        port = int(boardserver[1])
        try:
            group = int(boardserver[2])
        except ValueError:
            with open(boardserver[2], 'r') as f:
                group = int(f.read())
        boardserver = boardserver[0]
        if port < 1 or port > 65535 or group < 1 or group > 99:
            raise ValueError
    else:
        raise ValueError
except ValueError:
    print('\033[31;1mError: invalid server configuration.\033[0m')
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

local['mkdir']('-p', tempdir)
local['cp'](bitfile, tempbit)
local['cp'](srec, tempsrec)
local['tar']('czf', tempfile, '-C', tempdir, 'fpga.bit', 'code.srec')

# Handle dropbox protocol.
if protocol == 'dropbox':
    
    # Figure out dropbox protocol filenames.
    requestfile = boardserver + os.sep + token + '.tgz'
    statusfile  = boardserver + os.sep + token + '.stat'
    resultfile  = boardserver + os.sep + token + '.result.tgz'

    # Move the tar archive to the dropbox folder and remove the temp folder.
    local['mv'](tempfile, boardserver)
    local['rm']('-rf', tempdir)

    # Scan for status messages.
    t = 0
    try:
        print('\033[1mWaiting for boardserver, ctrl+C to cancel...\n\033[0m')
        complete = False
        status = 'waiting for response from server...'
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
            
            # Handle epic boardserver errors.
            if status.startswith('ERROR'):
                print(status)
                local['rm']('-f', requestfile, statusfile, resultfile)
                sys.exit(1)
            
            # Print the current status.
            print('\033[2A\033[1mWaiting for boardserver, ctrl+C to cancel... %d sec\n%s\033[0m\033[K' % (
                t, ('Status: ' + status) if status else ''))
            

    except KeyboardInterrupt:
        local['rm']('-f', requestfile, statusfile, resultfile)
        print('\033[31;1mCancelled.\033[0m')
        sys.exit(1)

    # Complete the request by removing all related files from the dropbox folder ASAP.
    # The boardserver will also do this after some time in case something goes wrong
    # in the VM.
    local['mv'](resultfile, resultdir + os.sep + 'results.tgz')
    local['rm']('-f', requestfile, statusfile, resultfile)

# Handle websocket protocol.
elif protocol == 'websocket':
    
    def run_on_bs(group, infname, outfname):
        import asyncio
        import websockets
        import base64
        import traceback
        
        last_status = ['']
        
        def print_status(fmt, *args):
            msg = fmt % args
            last_status[0] = msg
            print('\r\033[J\033[1m%s\033[0m' % msg, end='', file=sys.stderr)
        
        def print_note(fmt, *args):
            msg = fmt % args
            print('\r\033[J%s\n\033[s' % msg, end='', file=sys.stderr)
        
        def print_end(fmt=None, *args):
            if fmt is not None:
                msg = '\033[1m%s\033[0m\n' % (fmt % args)
            else:
                msg = ''
            print('\r\033[J%s' % msg, end='', file=sys.stderr)
        
        def print_warning(fmt, *args):
            msg = fmt % args
            print_note('%s%s', '\033[33m\033[1mWarning:\033[0m ', msg)
        
        def print_error(fmt, *args):
            msg = fmt % args
            print_note('%s%s', '\033[31m\033[1mError:\033[0m ', msg)
        
        def communicate():
            
            start = time.time()
            
            def print_status_2(fmt, *args):
                msg = fmt % args
                print_status('%s (attempt %d, %ds elapsed)', msg, attempt, int(time.time() - start))
            
            @asyncio.coroutine
            def coroutine():
                try:
                    
                    # Connect to the boardserver.
                    print_status_2('%s', 'Connecting to boardserver')
                    websocket = yield from websockets.connect('ws://%s:%d/' % (boardserver, port), max_size=1024*1024*10)
                    yield from websocket.send('et4074 group %d' % group)
                    status = 'Connected to boardserver'
                    print_status_2('%s', status)
                    
                    recv_pend = set()
                    
                    try:
                        
                        # Remember when we last received a message so we can do timeouts.
                        last_recv = time.time()
                        
                        # Wait for messages.
                        recv_pend = {websocket.recv()}
                        while True:
                            recv_done, recv_pend = yield from asyncio.wait(recv_pend, timeout=1)
                            
                            for recv in recv_done:
                                
                                # Received a message from the server.
                                msg = recv.result()
                                last_recv = time.time()
                                
                                # Split the message into command and payload.
                                msg = msg.split(' ', 1)
                                if len(msg) > 1:
                                    payload = msg[1]
                                command = msg[0]
                                
                                # Handle the message.
                                try:
                                    
                                    # Transfer command: send the job file to the server.
                                    if command == 'transfer':
                                        with open(infname, 'rb') as f:
                                            s = base64.b85encode(f.read()).decode('ascii')
                                        yield from websocket.send(s)
                                    
                                    # Complete command: contains result file as payload.
                                    elif command == 'complete':
                                        s = base64.b85decode(payload)
                                        with open(outfname, 'wb') as f:
                                            f.write(s)
                                        return 'success'
                                    
                                    # Retry command: retry after the given amount of seconds.
                                    elif command == 'retry':
                                        try:
                                            return int(payload)
                                        except ValueError:
                                            return 'retry'
                                    
                                    # Status update commands.
                                    elif command == 'error':
                                        print_error('%s', payload)
                                        return 'serverfail'
                                    elif command == 'warning':
                                        print_warning('%s', payload)
                                    elif command == 'note':
                                        print_note('%s', payload)
                                    elif command == 'message':
                                        status = str(payload)
                                    
                                    # Unknown commands.
                                    else:
                                        print_error('unknown command from server: %s. Try running the update toolchain script.', command)
                                        return 'fail'
                                except asyncio.CancelledError:
                                    raise
                                except Exception as e:
                                    print_error('while handling %s command: %s\nThis is a bug, try running the update toolchain script.', command, traceback.format_exc())
                                    return 'fail'
                                
                                # Start waiting for the next message.
                                recv_pend.add(websocket.recv())
                            
                            # Handle update message timeouts.
                            if time.time() - last_recv > 30:
                                print_error('timeout waiting for message from boardserver')
                                return 'retry'
                            
                            # Update the status text at the bottom of the terminal.
                            print_status_2('%s', status)
                            
                    finally:
                        for recv in recv_pend:
                            if hasattr(recv, 'cancel'):
                                recv.cancel()
                        yield from websocket.close()
                
                except websockets.exceptions.ConnectionClosed:
                    print_error('lost connection to boardserver')
                    return 'retry'
                except websockets.exceptions.InvalidHandshake as e:
                    print_error('%s', e)
                    return 'retry'
                except OSError as e:
                    if e.args and isinstance(e.args[0], str) and 'Connect call failed' in e.args[0]:
                        print_error('Failed to connect to the boardserver. Check if your internet connection\nis working. If this message persists, contact the lab assistents.')
                    elif e.args and e.errno == 104:
                        print_error('Connection reset by server.')
                    else:
                        print_error('%s', e)
                    return 'retry'
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    print_error('%s', traceback.format_exc())
                    return 'fail'
            
            loop = asyncio.get_event_loop()
            try:
                return loop.run_until_complete(coroutine())
            except KeyboardInterrupt as e:
                for task in asyncio.Task.all_tasks():
                    task.cancel()
                loop.run_forever()
                for task in asyncio.Task.all_tasks():
                    try:
                        task.exception()
                    except asyncio.CancelledError:
                        pass
                loop.close()
                raise
        
        try:
            retry_timeout = 5
            attempt = 1
            serverfail_retried = False
            while True:
                
                # Try to send the file to the boardserver.
                result = communicate()
                attempt += 1
                
                # An integer result means that we were instructed to wait for that
                # many seconds.
                status_fmt = 'Retrying (attempt %d) in %d second(s)... %s'
                if isinstance(result, int):
                    retry_timeout = result
                    result = 'retry'
                    status_fmt = 'Your group already has at least one job queued up on the server.\n' + status_fmt + '\033[A\r'
                
                # If we get a retry result, retry after some time. Increase the
                # time exponentially after each retry, but allow the user to retry
                # immediately and reset the holdback time after 3 seconds.
                if result == 'retry':
                    serverfail_retried = False
                    for i in range(3):
                        print_status(status_fmt, attempt, retry_timeout - i,
                                    '(press Ctrl+C to \033[31mcancel\033[0;1m)')
                        time.sleep(1)
                    try:
                        for i in range(3, retry_timeout):
                            print_status(status_fmt, attempt, retry_timeout - i,
                                        '(press Ctrl+C to \033[32mretry\033[0;1m now)')
                            time.sleep(1)
                    except KeyboardInterrupt:
                        retry_timeout = 5
                    else:
                        retry_timeout = int(retry_timeout * 1.5)
                
                # If we get a fail result, stop trying and return false.
                elif result == 'fail':
                    print_end('Aborted due to fatal error.')
                    return False
                
                # If we get a serverfail result, try once more, because the fixing
                # script on the server might fix things.
                elif result == 'serverfail':
                    if serverfail_retried:
                        print_end('Aborted due to fatal error.')
                        return False
                    print_note('Server problem! Retrying once more, it might fix itself...')
                    serverfail_retried = True
                    continue
                
                # If we get a success result, return true.
                elif result == 'success':
                    print_end('Completed successfully.')
                    return True
                
                else:
                    print_end('Unknown error.')
                    return False
            
        except KeyboardInterrupt:
            print_end('Cancelled.')
            return False
    
    try:
        if not run_on_bs(group, tempfile, resultdir + os.sep + 'results.tgz'):
            sys.exit(1)
    finally:
        local['rm']('-rf', tempdir)

# Extract the result data.
with local.cwd(resultdir):
    local['tar']('xzf', 'results.tgz')
    local['rm']('-f', 'results.tgz')

if protocol == 'dropbox':
    
    # Dump the status log to the console. Only do this for the dropbox
    # protocol, because the websocket protocol will dump the log live.
    logfile = resultdir + os.sep + 'boardserver.log'
    try:
        with open(logfile, 'r') as f:
            print(f.read())
        local['rm']('-f', logfile)
    except IOError:
        print('Did not receive status log file from board server...')
