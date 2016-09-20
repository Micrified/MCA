
from __future__ import print_function

import subprocess
import sys

def run_command(command, silent=False, default=None):
    """Runs the given command, formatted as a list of argv parameters, the first
    of which is the executable including path. If silent is not specified, all
    output is piped to stdout, whereas if silent is set to true, output is not
    forwarded unless the process returns nonzero. If anything is outputted to
    stdout, the command line is first printed. If the process returns nonzero
    and default is None, sys.exit() is called with the same error code, and thus
    this call will not return. If default is not None, sys.exit() is not called
    and the contents of default are returned. If the process returns zero, its
    stdout/stderr is returned as a string."""
    
    cmdline = ' '.join([('"%s"' % x.replace('\\', '\\\\').replace('"', '\\"')) if ' ' in x else x for x in command])
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        result = []
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output != '':
                result.append(output)
                if not silent:
                    if cmdline:
                        print(cmdline)
                        cmdline = None
                    print(output, end='')
        rc = process.poll()
        if rc == 0:
            return ''.join(result)
    except OSError as e:
        result = ['OSError: ', str(e), '\n']
        rc = -1
    
    if cmdline:
        print(cmdline)
        cmdline = None
    if silent:
        print(''.join(result), end='')
    if default is None:
        sys.exit(rc)
    return default

