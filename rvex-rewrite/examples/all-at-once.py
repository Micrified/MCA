#!/usr/bin/python3
import sys

# Generates an assembly file with a main which calls <object>_main for all
# objects specified on the command line. Nonzero return values are interpreted
# as an error.
usage = 'all.py <object> [<object2> ...]'

if len(sys.argv) == 0:
	print(usage, file=sys.stderr)
	sys.exit(2)

print("""

.section .text
.proc
main::

c0 add $r0.63 = $r0.0, 0
;;
""")

for f in sys.argv[1:]:
	print("""
	
	c0 call $l0.0 = %s_main
	;;
	c0 or $r0.63 = $r0.63, $r0.3
	;;
	""" % f.rsplit(".", 1)[0])

print("""

c0 cmpne $b0.0 = $r0.63, 0
;;
c0 mov $r0.3 = success_str
;;
c0 br $b0.0, 1f
;;
c0 call $l0.0 = rvex_succeed
;;
1:
c0 add $r0.3 = $r0.0, $r0.63
;;
c0 return $r0.1 = $r0.1, 0, $l0.0
;;
.endp

.section .data
success_str:
.data1 'A'
.data1 'L'
.data1 'L'
.data1 ' '
.data1 'B'
.data1 'E'
.data1 'N'
.data1 'C'
.data1 'H'
.data1 'M'
.data1 'A'
.data1 'R'
.data1 'K'
.data1 'S'
.data1 ' '
.data1 'S'
.data1 'U'
.data1 'C'
.data1 'C'
.data1 'E'
.data1 'S'
.data1 'S'
.data1 'F'
.data1 'U'
.data1 'L'
.data1 '\\n'
.data1 0
.data1 0

""")
