#!/usr/bin/python3
import sys, getopt

# This searches for *.dep files in the specified paths and adds interprets
# their contents as dependencies. For each new dependency found, additional
# dependencies are checked for recursively. The extensions of <object*>
# are ignored.
usage = 'deps.py -p <search path> [-p <search path 2> ...] <object> [<object2> ...]'

curObjs = set()
curDeps = []
paths = []

def scanDeps(obj):
  global curDeps, curObjs, paths
  
  # Figure out if the given object has dependencies of its own which are not
  # already in the set.
  deps = []
  for path in paths:
    try:
      with open(path + "/" + obj + ".dep", "r") as myfile:
        deps += myfile.read().split()
    except (OSError, IOError):
      pass
  for obj in deps:
    if obj not in curObjs:
      curObjs.add(obj)
      curDeps += [obj]
      scanDeps(obj)

try:
  opts, args = getopt.getopt(sys.argv[1:], "p:")
except getopt.GetoptError:
  print(usage, file=sys.stderr)
  sys.exit(2)

for opt, arg in opts:
  if opt == '-p':
    if not arg:
      print(usage, file=sys.stderr)
      sys.exit(2)
    paths += [arg]

objs = []
for f in args:
  obj = f.rsplit(".", 1)[0]
  objs += [obj]
  curObjs.add(obj)

for obj in objs:
  scanDeps(obj)

for dep in curDeps:
  print(dep + '.o')

print('deps.py: dependencies for objects ' + ', '.join([x + '.o' for x in objs]) + ': ' + ', '.join([x + '.o' for x in curDeps]), file=sys.stderr)
