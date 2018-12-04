#include <stdio.h>
#include <stdlib.h>

const char format[] =
"RES: IssueWidth     %s\n\
RES: MemLoad        %s\n\
RES: MemStore       %s\n\
RES: MemPft         %s\n\
# ***Clusters***    1\n\
RES: IssueWidth.0   %s\n\
RES: Alu.0          %s\n\
RES: Mpy.0          %s\n\
RES: Memory.0       %s\n\
RES: CopySrc.0      0\n\
RES: CopyDst.0      0\n\
REG: $r0            %s\n\
REG: $b0            %s\n\
DEL: AluR.0         0\n\
DEL: Alu.0          0\n\
DEL: CmpBr.0        0\n\
DEL: CmpGr.0        0\n\
DEL: Select.0       0\n\
DEL: Multiply.0     1\n\
DEL: Load.0         1\n\
DEL: LoadLr.0       1\n\
DEL: Store.0        0\n\
DEL: Pft.0          0\n\
DEL: CpGrBr.0       0\n\
DEL: CpBrGr.0       0\n\
DEL: CpGrLr.0       0\n\
DEL: CpLrGr.0       0\n\
DEL: Spill.0        0\n\
DEL: Restore.0      1\n\
DEL: RestoreLr.0    1\n\
CFG: Quit           0\n\
CFG: Warn           0\n\
CFG: Debug          0\n ";

int main (int argc, const char *argv[]) {
	if (argc != 10) {
		fprintf(stderr, "<IssueWidth> <MemLoad> <MemStore> <MemPft> <Alu> <Mpy> <Memory> <R0> <B0>\n");
		exit(EXIT_FAILURE);
	}
	fprintf(stdout, format, argv[1],argv[2],argv[3],argv[4],argv[1],argv[5],argv[6],argv[7],argv[8],argv[9]);
	return EXIT_SUCCESS;
}
