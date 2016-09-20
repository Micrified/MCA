#!/usr/bin/python
from __future__ import print_function
import re
import hashlib
import sys

def _load_file(vhdfile, log=None):
    """Loads the VHDL file specified by vhdfile into a string and strips it
    for hashing.
    
    The file is stripped as follows:
     - All -- comments are removed.
     - Optional whitespace/newlines are removed as much as possible.
     - Required whitespace is turned into a single space as much as possible.
    """
    
    if log is not None:
        print('Hashing "' + vhdfile + '"...', file=log)
    
    # Read the file.
    with open(vhdfile, 'r') as f:
        text = f.read()
    
    # Strip the file.
    req_ws = False
    idx = 0
    output = []
    while idx < len(text):
        
        # Ignore whitespace.
        while text[idx:idx+1] in [' ', '\t', '\n', '\r']:
            idx += 1
        
        # Tokenize numbers and identifiers.
        if re.match('[0-9a-zA-Z_]', text[idx:idx+1]) is not None:
            if req_ws:
                output.append(' ')
            output.append(text[idx:idx+1])
            idx += 1
            while re.match('[0-9a-zA-Z_]', text[idx:idx+1]) is not None:
                output.append(text[idx:idx+1])
                idx += 1
            req_ws = True
            continue
        
        # Handle comments.
        if text[idx:idx+2] == '--':
            idx += 2
            while text[idx:idx+1] not in ['\n', '\r']:
                idx += 1
            idx += 1
            continue
        
        # Handle strings.
        if text[idx:idx+1] == '"':
            output.append(text[idx:idx+1])
            idx += 1
            while text[idx:idx+1] != '"' is not None:
                output.append(text[idx:idx+1])
                idx += 1
            output.append(text[idx:idx+1])
            idx += 1
            req_ws = False
            continue
            
        # Handle characters.
        if re.match("'.'", text[idx:idx+3]):
            output.append(text[idx:idx+3])
            idx += 3
            req_ws = False
            continue
        
        # Handle any other characters.
        output.append(text[idx:idx+1])
        idx += 1
        req_ws = False
    
    return ''.join(output)

def _b64(tag):
    """Turns three hex digits into two base-64 characters."""
    table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    tag = int(tag, 16)
    return table[tag // 64] + table[tag % 64]

def tag(files, log=None, mode='vhdl'):
    """Generates the tag for a given list of filenames. If mode is 'vhdl', the
    tag is generated in a way which attempts to preserve the same tag if the
    functionality remains the same, i.e. ignoring comments etc. This only works
    for VHDL files. If the input contains other kinds of files, set mode to
    'md5'; then the tag source is just the MD5 sum of all input files."""
    
    if mode == 'vhdl':
        
        # Load and strip the contents of all the files.
        contents = [_load_file(fname, log) for fname in files]
        
        if log is not None:
            print('Computing tag...', file=log)
        
        # Sort the files by their content, so the order in which the files are
        # passed to this function doesn't affect the tag.
        contents.sort()
        
        # Append all the files to a single string for hashing.
        contents = '\n'.join(contents)
        
        # Generate an MD5 of the contents.
        h = hashlib.md5(contents).hexdigest()
    
    else:
        
        # Simply compute the MD5 hash of all files in any order.
        h = hashlib.md5()
        for fname in files:
            with open(fname, "rb") as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    h.update(chunk)
        h = h.hexdigest()
    
    result = {'md5': h}
    
    # Generate 7 base64 characters from it.
    tag = _b64(h[0:3]) + _b64(h[3:6]) + _b64(h[6:9]) + _b64(h[9:12])
    tag = tag[:7]
    result['tag'] = tag
    
    # Convert the ASCII tag to hex.
    hexa = ''
    for i in range(7):
        hexa += '%02X' % ord(tag[i])
    result['hexhi'] = hexa[0:6]
    result['hexlo'] = hexa[6:14]
    result['hex'] = '0x--' + hexa[0:6] + ', 0x' + hexa[6:14]
    
    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Usage: [python] vhdtag.py [-q] <file1> [file2] ...', file=sys.stderr)
        sys.exit(2)
    if sys.argv[1] == '-q':
        print(tag(sys.argv[2:])['tag'])
    else:
        tagdata = tag(sys.argv[1:], sys.stdout)
        print('MD5 hash        = ' + tagdata['md5'])
        print('ASCII tag       = ' + tagdata['tag'])
        print('Hexadecimal tag = ' + tagdata['hex'])
