-- r-VEX processor
-- Copyright (C) 2008-2016 by TU Delft.
-- All Rights Reserved.

-- THIS IS A LEGAL DOCUMENT, BY USING r-VEX,
-- YOU ARE AGREEING TO THESE TERMS AND CONDITIONS.

-- No portion of this work may be used by any commercial entity, or for any
-- commercial purpose, without the prior, written permission of TU Delft.
-- Nonprofit and noncommercial use is permitted as described below.

-- 1. r-VEX is provided AS IS, with no warranty of any kind, express
-- or implied. The user of the code accepts full responsibility for the
-- application of the code and the use of any results.

-- 2. Nonprofit and noncommercial use is encouraged. r-VEX may be
-- downloaded, compiled, synthesized, copied, and modified solely for nonprofit,
-- educational, noncommercial research, and noncommercial scholarship
-- purposes provided that this notice in its entirety accompanies all copies.
-- Copies of the modified software can be delivered to persons who use it
-- solely for nonprofit, educational, noncommercial research, and
-- noncommercial scholarship purposes provided that this notice in its
-- entirety accompanies all copies.

-- 3. ALL COMMERCIAL USE, AND ALL USE BY FOR PROFIT ENTITIES, IS EXPRESSLY
-- PROHIBITED WITHOUT A LICENSE FROM TU Delft (J.S.S.M.Wong@tudelft.nl).

-- 4. No nonprofit user may place any restrictions on the use of this software,
-- including as modified by the user, by any other authorized user.

-- 5. Noncommercial and nonprofit users may distribute copies of r-VEX
-- in compiled or binary form as set forth in Section 2, provided that
-- either: (A) it is accompanied by the corresponding machine-readable source
-- code, or (B) it is accompanied by a written offer, with no time limit, to
-- give anyone a machine-readable copy of the corresponding source code in
-- return for reimbursement of the cost of distribution. This written offer
-- must permit verbatim duplication by anyone, or (C) it is distributed by
-- someone who received only the executable form, and is accompanied by a
-- copy of the written offer of source code.

-- 6. r-VEX was developed by Stephan Wong, Thijs van As, Fakhar Anjam,
-- Roel Seedorf, Anthony Brandon, Jeroen van Straten. r-VEX is currently
-- maintained by TU Delft (J.S.S.M.Wong@tudelft.nl).

-- Copyright (C) 2008-2016 by TU Delft.

library IEEE;
use IEEE.std_logic_1164.all;

--=============================================================================
-- This package specifies the control signal encoding for routing data through
-- the pipelane.
-------------------------------------------------------------------------------
package core_opcodeDatapath_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Integer operand and result datapath
  -----------------------------------------------------------------------------
  -- The integer datapath is controlled by various control signals to support
  -- the various instruction encodings. These signals are:
  -- 
  --  - Syllable bit 23: selects between (long) immediate and general purpose
  --    register file for operand 2.
  -- 
  --  - stackOp: selects between the designated fields in the syllable for
  --    general purpose register file source 1 and destination addresses or
  --    register r0.1 for both. It also selects between the regular datapath
  --    for operand 2 and the branch offset field in the syllable. The latter
  --    is used to perform an addition with immediate on r0.1, designated to be
  --    the stack pointer, while an RFI or RETURN instruction is processed.
  -- 
  --  - op1LinkReg selects between the current value of the link register and
  --    the value read from the general purpose registers for operand 1.
  -- 
  --  - op3LinkReg selects between the current value of the link register and
  --    the value read from the general purpose registers for operand 3.
  -- 
  --  - funcSel controls which functional unit output is sent to the general
  --    purpose register file or the link register.
  -- 
  --  - linkWE controls whether the link register should be written to or not.
  -- 
  --  - gpRegWE controls whether the general purpose register file should be
  --    written to or not.
  -- 
  -- The datapath is also depicted schematically below.
  -- 
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  -- 
  -- 22..17 ---o------->|0\
  --           |        |  |--------------------------------------------> dest
  --           |  R1 -->|1/
  --           |         ^
  --           |         |                   <op1LinkReg>
  --           |     <stackOp>  .----------.      |  <op3LinkReg>
  --           |         |      | Link rd. |--.   v     | <op3BranchRegs>
  --           |         v      '----------'  o->|1\    |       |
  -- 16..11 ---+------->|0\ src1.----------.  |  |  |---+-------+-------> op1
  --           |        |  |--->| GP. read |--+->|0/    v       |
  --           |  R1 -->|1/     '----------'  o------->|1\      v
  --           |                              |        |  |--->|0\
  --           '------->|1\ src2.----------.  |   .--->|0/     |  |-----> op3
  --                    |  |--->| GP. read |--+---o  <brRegs>->|1/
  --  10..5 ----------->|0/     '----------'  |   |  
  --                     ^                    |   '--->|0\
  --                     |      imm           |        |  |--->|0\
  --  10..2 ---x---------+--------------------+------->|1/     |  |-----> op2
  --  limmh ---'         |     useImm         |         ^   .->|1/
  --     23 -------------o--------------------+---------'   |   ^
  --  23..5 -------------------------------o--+-------------'   |
  --                   br.branchOffset     |  |              <linkOp>
  --                                       |  |br.linkTarget.----------.
  --                                       v  '------------>|  Branch  |
  --  PC_plusOne ------------------------>(+)-------------->|   unit   |
  --                                       br.relativeTarget'----------'
  -- 
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  -- 
  --                    .-----.                             .----------.
  --    op1 -------o--->|     |    resMul        <linkWE>-->|WE        |
  --               |    | MUL |--------------. <funcSel>    | Link wr. |
  --           .---+--->|     |              |    |      .->|Data      |
  --           |   |    '-----'  PC_plusOne  |    v      |  '----------'
  --           |   |    .-----.       |      '-->| \     |
  --           |   '--->|     |       '--------->|  \    |
  --           |        | ALU |----------------->|  |----o
  --    op2 ---o------->|     |    resALU        |  /    |res
  --                    '-----'              .-->| /     |
  --                         |    .------.   |           |  .----------.
  --                   resAdd'--->|Addr  |   |resMem     '->|Data      |
  --                              | MEM  |   |              | GP write |
  --    op3 --------------------->|DI  DO|---o  <gpRegWE>-->|WE        |
  --                              '------'   |              |          |
  --   dest ---------------------------------+------------->|Addr      |
  --                                         v              '----------'
  --                                   .-----------.
  --                                   |   Data    |
  --                                   |Br bulk wr.|
  --                   <allBrRegsWE>-->|WE         |
  --                                   '-----------'
  -- 
  -----------------------------------------------------------------------------
  -- Branch/carry operand and result datapath
  -----------------------------------------------------------------------------
  -- The branch/carry datapath is displayed below. It is controlled by two
  -- control signals, brFmt and brWrite. brFmt chooses between two locations
  -- for the branch source and destination registers in the syllable, brWrite
  -- controls whether the branch register file will be written to or not. The
  -- datapath is also depicted schematically below.
  --
  -- The entire branch register file can also be written at once for context
  -- save/restore purposes. The signals for that are indicated in the integer
  -- datapath.
  -- 
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  -- 
  -- 19..17 ------>|0\             destBr                .-----------.
  --               |  |--------------------------------->|Addr       |
  --          .--->|1/                                   |           |
  --          |     ^                      <brRegWE>---->|WE         |
  --          |     |                                    |           |
  --   4..2 --o  <brFmt>                    .----------. | Br. write |
  --          |     |                opBr.->| Br. unit | |           |
  --          |     v                    |  '----------' |           |
  --          '--->|0\ srcBr.----------. |  .-----.      |           |
  --               |  |---->| Br. read |-o->| ALU |----->|Data       |
  -- 26..24 ------>|1/      '----------'    '-----'resBr '-----------'
  -- 
  -----------------------------------------------------------------------------
  -- Branch unit control signals
  -----------------------------------------------------------------------------
  -- Enumeration type for the funcSel control signal.
  type datapathFuncSel_type is (ALU, MEM, MUL, PCP1);
  
  -- Data path control signals. Refer to the schematics and documentation above
  -- for more information.
  type datapathCtrlSignals_type is record
    funcSel                     : datapathFuncSel_type;
    gpRegWE                     : std_logic;
    linkWE                      : std_logic;
    brRegWE                     : std_logic;
    allBrRegsWE                 : std_logic;
    stackOp                     : std_logic;
    op1LinkReg                  : std_logic;
    op3LinkReg                  : std_logic;
    op3BranchRegs               : std_logic;
    brFmt                       : std_logic;
    
    -- Special instruction flags. These are set only when the respective
    -- instruction is executed.
    isLIMMH                     : std_logic;
    isTrap                      : std_logic;
    isNOP                       : std_logic;
    
  end record;
  
  -- Array type.
  type datapathCtrlSignals_array is array (natural range <>) of datapathCtrlSignals_type;
  
  -- No operation.
  constant DP_CTRL_NOP          : datapathCtrlSignals_type := (
    funcSel                     => ALU,
    isNOP                       => '1',
    others                      => '0'
  );
  
end core_opcodeDatapath_pkg;

package body core_opcodeDatapath_pkg is
end core_opcodeDatapath_pkg;
