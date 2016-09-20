#!/usr/bin/python

import os
import manifest
import vhdl_package
import vhdtag

# Compute the platform tag.
ptag = vhdtag.tag([x[0] for x in manifest.sources_f() if os.path.isfile(x[0])], mode='md5')
print('################################################################################')
print('##   The platform version tag is:  \033[1;4m' + ptag['tag'] + '\033[0m-' + ptag['md5'] + '   ##')
print('################################################################################')
with open(manifest.ptagfile, 'w') as f:
    f.write(vhdl_package.gen(ptag, 'platform'))

