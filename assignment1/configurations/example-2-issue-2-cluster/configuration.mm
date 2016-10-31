
#-----------------------------------------------------------------------------#
#                            Global configuration                             #
#-----------------------------------------------------------------------------#

# Overall issue width. This is the number of syllables that can be executed
# per cycle, regardless of clustering. This must be at least 2.
RES: IssueWidth     4

# The following parameters specify the number of 32-bit connections to the data
# cache, for memory loads, stores, and prefetches respectively.
RES: MemLoad        1
RES: MemStore       1
RES: MemPft         1

# The following parameter specifies the number of clusters to use. It can be
# 1, 2 or 4. NOTE: do NOT uncomment this line. It is commented because the
# number of clusters is confusingly not actually part of the machine model, but
# a compiler flag. The compile script will search for this line and use it to
# set the -width compiler flag accordingly.
# ***Clusters***    2

#-----------------------------------------------------------------------------#
#                           Cluster 0 configuration                           #
#-----------------------------------------------------------------------------#

# The following parameter specifies the maximum number of syllables that can be
# decoded by this cluster per cycle. This must be at least 2.
RES: IssueWidth.0   2

# The following parameter specifies the number of ALU syllables that can be
# executed by this cluster per cycle.
RES: Alu.0          2

# The following parameter specifies the number of multiply syllables that can
# be executed by this cluster per cycle.
RES: Mpy.0          2

# The following parameter specifies the number of memory syllables that can be
# executed by this cluster per cycle.
RES: Memory.0       1

# The following two parameters specify the number of inter-cluster
# communication syllables that can be executed by this cluster per cycle. A
# register move from one cluster to another consists of a SEND syllable in the
# source cluster and a RECV syllable in the destination cluster. The number of
# SEND instructions per cycle in this cluster are governed by CopySrc, while
# RECV is governed by CopyDst.
RES: CopySrc.0      2
RES: CopyDst.0      2

# The following parameter specifies the number of 32-bit general purpose
# registers available to this cluster.
REG: $r0            63

# The following parameter specifies the number of single bit condition
# registers available to this cluster.
REG: $b0            8

#-----------------------------------------------------------------------------#
#                          Cluster 1-3 configuration                          #
#-----------------------------------------------------------------------------#
# See cluster 0 for what the parameters do.

# Cluster 1.
RES: IssueWidth.1   2
RES: Alu.1          2
RES: Mpy.1          2
RES: Memory.1       1
RES: CopySrc.1      2
RES: CopyDst.1      2
REG: $r1            63
REG: $b1            8

# Cluster 2.
RES: IssueWidth.2   2
RES: Alu.2          2
RES: Mpy.2          2
RES: Memory.2       1
RES: CopySrc.2      2
RES: CopyDst.2      2
REG: $r2            63
REG: $b2            8

# Cluster 3.
RES: IssueWidth.3   2
RES: Alu.3          2
RES: Mpy.3          2
RES: Memory.3       1
RES: CopySrc.3      2
RES: CopyDst.3      2
REG: $r3            63
REG: $b3            8

#=============================================================================#
#            For the assignments, don't change anything below here            #
#=============================================================================#

# Functional unit latencies for cluster 0.
DEL: AluR.0         0
DEL: Alu.0          0
DEL: CmpBr.0        0
DEL: CmpGr.0        0
DEL: Select.0       0
DEL: Multiply.0     1
DEL: Load.0         1
DEL: LoadLr.0       1
DEL: Store.0        0
DEL: Pft.0          0
DEL: CpGrBr.0       0
DEL: CpBrGr.0       0
DEL: CpGrLr.0       0
DEL: CpLrGr.0       0
DEL: Spill.0        0
DEL: Restore.0      1
DEL: RestoreLr.0    1

# Functional unit latencies for cluster 1.
DEL: AluR.1         0
DEL: Alu.1          0
DEL: CmpBr.1        0
DEL: CmpGr.1        0
DEL: Select.1       0
DEL: Multiply.1     1
DEL: Load.1         1
DEL: LoadLr.1       1
DEL: Store.1        0
DEL: Pft.1          0
DEL: CpGrBr.1       0
DEL: CpBrGr.1       0
DEL: CpGrLr.1       0
DEL: CpLrGr.1       0
DEL: Spill.1        0
DEL: Restore.1      1
DEL: RestoreLr.1    1

# Functional unit latencies for cluster 2.
DEL: AluR.2         0
DEL: Alu.2          0
DEL: CmpBr.2        0
DEL: CmpGr.2        0
DEL: Select.2       0
DEL: Multiply.2     1
DEL: Load.2         1
DEL: LoadLr.2       1
DEL: Store.2        0
DEL: Pft.2          0
DEL: CpGrBr.2       0
DEL: CpBrGr.2       0
DEL: CpGrLr.2       0
DEL: CpLrGr.2       0
DEL: Spill.2        0
DEL: Restore.2      1
DEL: RestoreLr.2    1

# Functional unit latencies for cluster 3.
DEL: AluR.3         0
DEL: Alu.3          0
DEL: CmpBr.3        0
DEL: CmpGr.3        0
DEL: Select.3       0
DEL: Multiply.3     1
DEL: Load.3         1
DEL: LoadLr.3       1
DEL: Store.3        0
DEL: Pft.3          0
DEL: CpGrBr.3       0
DEL: CpBrGr.3       0
DEL: CpGrLr.3       0
DEL: CpLrGr.3       0
DEL: Spill.3        0
DEL: Restore.3      1
DEL: RestoreLr.3    1

CFG: Quit           0
CFG: Warn           0
CFG: Debug          0
