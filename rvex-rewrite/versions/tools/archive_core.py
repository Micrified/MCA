#!/usr/bin/python
import vhdtag
import os
import sys
import tarfile

import vhdl_package
import paths

def run(silent=True, very_silent=False, actually_archive=True):
    
    # Find the :/versions and :/lib/rvex/core/ paths regardless of current
    # directory.
    rvex_rewrite_dir = os.path.realpath(paths.dirs['root'])
    archive_dir = os.path.realpath(rvex_rewrite_dir + '/versions/cores')
    source_dir = os.path.realpath(rvex_rewrite_dir + '/lib/rvex/core')
    version_file = 'core_version_pkg.vhd'

    # Load the source file lists.
    source_files = []
    with open(source_dir + '/deps.txt', 'r') as f:
        source_files += list(filter(None, (source_dir + os.sep + line.strip() for line in f)))
    with open(source_dir + '/vhdlsyn.txt', 'r') as f:
        source_files += list(filter(None, (source_dir + os.sep + line.strip() for line in f)))
    for i in range(len(source_files)):
        source_files[i] = os.path.realpath(source_files[i])

    # Generate the tag for everything but the version file.
    fs = []
    for f in source_files:
        if not f.endswith(version_file):
            fs += [f]
    tag = vhdtag.tag(fs, None if silent else sys.stdout)
    if not (silent and very_silent):
        print('################################################################################')
        print('##     The core version tag is:  \033[1;4m' + tag['tag'] + '\033[0m-' + tag['md5'] + '     ##')
        print('################################################################################')

    # (Re)generate the version file.
    with open(source_dir + os.sep + version_file, 'w') as f:
        f.write(vhdl_package.gen(tag, 'core'))

    # Generate the archive and put it in the right place!
    if actually_archive:
        archive_file = 'core-' + tag['tag'] + '-' + tag['md5'] + '.tar.gz'
        print('Creating "' + archive_dir + os.sep + archive_file + '"...')
        with tarfile.open(archive_dir + os.sep + archive_file, 'w:gz') as arch:
            for fname in source_files:
                arcname = os.path.relpath(fname, rvex_rewrite_dir)
                arch.add(fname, arcname)
    
    return tag

if __name__ == "__main__":
    run(False)
