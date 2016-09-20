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
-- This package configures the pipeline used by the rvex.
-------------------------------------------------------------------------------
package core_pipeline_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Pipeline diagram
  -----------------------------------------------------------------------------
  -- The figure below shows the pipeline diagram and forwarding logic of the
  -- rvex processor. Pipeline flushing due to exceptions and limmh forwarding
  -- is not shown. Timing within the stages is approximate.
  --
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  --
  --              clk        clk        clk        clk        clk
  --    :----S1----:----S2----:----S3----:----S4----:----S5----:----S6----:
  --    :    .---------..----.:      .-------..---------.   .-----.       :
  --    :    |  IMEM   ||Btgt|:      |  ALU  ||  DMEM   |   |Reg. |       :
  --    :    '---------''----':      '-------''---------'   |write|       :
  --    :    .----.:       .-----.   .------------------.   '-----'       :
  --    :    |PC+1|:       |Reg. |   |   :   MUL    :   |      :          :
  --    :    '----':       |read |   '------------------'      :          :
  --    :          :       '-----'       :    .---. :          :          :
  --    :          :    .-..-.:          :    |BRK| :          :          :
  --    :          :    |s||l|:          :    '---' :          :          :
  --    :          :    |t||i|:          :          :          :          :
  --    :          :    |o||m|:          :          :          :          :
  --    :          :    |p||m|:          :          :          :          :
  --    :          :    '-''-':          :          :          :          :
  --    '----S1----'----S2----'----S3----'----S4----'----S5----'----S6----'
  --         ^           |      |   ^        |          |          |*
  --         |           v      v   |        v          v          v
  --        .--------------------. .--------------------------------.
  --        |    Branch unit     | |General purpose reg. forwarding |
  --        '--------------------' '--------------------------------'
  --     ----S1---- ----S2---- ----S3---- ----S4---- ----S5---- ----S6----
  --                         ^    ^         |          |      |
  --                         |    |         v          v      |
  --                         |   .----------------------.     |
  --                         |   |Branch & link forward.|     |
  --                         |   '----------------------'     |
  --                         |                                |
  --                         '--------------------------------'
  --                                  Trap forwarding
  --
  -- * The register file is implemented using dual port RAM blocks. These
  --   blocks do not have consistent read-while-write behavior between the two
  --   ports. By extending the forwarding logic by one stage, such accesses are
  --   prevented (at least, their result is ignored).
  --
  
  -- TODO: generate something like the diagram above.
  
  -----------------------------------------------------------------------------
  -- Pipeline definitions
  -----------------------------------------------------------------------------
  -- The S_<block> definitions map to the first stage of a block. The L_<block>
  -- definitions determine the latency of a block, i.e., how many stages later
  -- the results of a block are expected to be valid.

  @CONSTANTS
  
end core_pipeline_pkg;

package body core_pipeline_pkg is
end core_pipeline_pkg;
