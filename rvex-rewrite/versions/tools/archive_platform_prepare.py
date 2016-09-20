#!/usr/bin/python

import sys
import os
import time
import pickle

import paths
import manifest
import archive_core
import vhdl_package
import vhdtag
from run_cmd import run_command

if 'arg' not in paths.dirs:
    print('Error: please pass a temporary directory for the archive as an argument.')
    sys.exit(1)

# Archive the core and get the core version tag.
ctag = archive_core.run()

# Compute the platform tag.
ptag = vhdtag.tag([x[0] for x in manifest.sources_f()], mode='md5')
print('################################################################################')
print('##   The platform version tag is:  \033[1;4m' + ptag['tag'] + '\033[0m-' + ptag['md5'] + '   ##')
print('################################################################################')
with open(manifest.ptagfile, 'w') as f:
    f.write(vhdl_package.gen(ptag, 'platform'))

# Put the sources in the archive.
print('Populating archive with sources...')
odirs = set()
for i, o in manifest.sources_f():
    o = paths.dirs['arg'] + os.sep + 'sources' + os.sep + o
    if o.endswith('/'):
        o = o[:-1]
    odir = os.path.split(o)[0]
    if odir not in odirs:
        odirs.add(odir)    
        run_command(['mkdir', '-p', odir])
    run_command(['cp', i, o])
print('Complete.')

# Generate metadata file.
print('Generating metadata...')
meta = """
Platform:     {platform}
Core tag:     {ctag} ({cmd5})
Platform tag: {ptag} ({pmd5})
Time:         {date}
User:         {user}

{rule}
 Current git commit
{rule}
{gitlog}

{rule}
 Git status
{rule}
{gitstat}

{rule}
 Git remote
{rule}
{gitrepo}

""".format(
    platform = manifest.name,
    ctag     = ctag['tag'],
    cmd5     = ctag['md5'],
    ptag     = ptag['tag'],
    pmd5     = ptag['md5'],
    date     = time.strftime("%Y-%m-%d %H:%M:%S"),
    user     = run_command(['git', 'config', '--get', 'user.name'], True, "unknown").strip(),
    gitlog   = run_command(['git', 'log', '-n', '1'], True, "unknown").strip(),
    gitstat  = run_command(['git', 'status'], True, "unknown").strip(),
    gitrepo  = run_command(['git', 'remote', '-v'], True, "unknown").strip(),
    rule     = '-' * 80
)
with open(paths.dirs['arg'] + os.sep + 'meta', 'w') as f:
    f.write(meta)
print('Complete.')

# Pickle data needed to complete the archive later.
pdata = {
    'ctag': ctag,
    'ptag': ptag
}
with open(paths.dirs['arg'] + os.sep + 'build-in-progress', 'wb') as f:
    pickle.dump(pdata, f)
