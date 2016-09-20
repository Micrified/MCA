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

library rvex;
use rvex.core_intIface_pkg.all;
use rvex.core_opcodeDatapath_pkg.all;
use rvex.core_opcodeAlu_pkg.all;
use rvex.core_opcodeBranch_pkg.all;
use rvex.core_opcodeMemory_pkg.all;
use rvex.core_opcodeMultiplier_pkg.all;

--=============================================================================
-- This package specifies basic decoding signals for all opcodes. In theory,
-- when you want to implement a new instruction which makes use of existing
-- logic in the pipelanes, you only need to change things here and in the
-- rvex_opcode<unit>_pkg associated with the unit you want to change. If you
-- also need new control signals, you'll obviously have to change the code of
-- the functional unit as well.
-------------------------------------------------------------------------------
package core_opcode_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Misc. instruction set constants
  -----------------------------------------------------------------------------
  -- Special "general purpose" register which is always tied to 0.
  constant GPREG_ZERO           : rvex_gpRegAddr_type := "000000";
  
  -- Special "general purpose" register which is used as stack pointer by
  -- return instructions.
  constant GPREG_STACK          : rvex_gpRegAddr_type := "000001";
  
  -- Special "general purpose" register which optionally maps to the link
  -- register, based on configuration.
  constant GPREG_LINK           : rvex_gpRegAddr_type := "111111";
  
  -- Determines which encoding is used for the relative branch offset. May be
  -- set to 2 or 3. When set to 3, the old encoding is used, where the LSB of
  -- the branch offset is equal to 64 bits. When set to 2, the branch offset
  -- is shifted right by one bit, to allow branching to 32 bit boundaries.
  @BRANCH_OFFS_SHIFT
  
  -----------------------------------------------------------------------------
  -- Opcode table entry type
  -----------------------------------------------------------------------------
  -- Constrained string type for syntax specifications.
  subtype syllable_syntax_type is string(1 to 50);
  
  -- Each opcode has a table entry like this which defines the behavior of the
  -- instruction.
  type opcodeTableEntry_type is record
    
    -- Instruction name/syntax for disassembly in VHDL simulation. Syntax_reg
    -- is for syllables with bit 23 cleared, syntax_imm is for syllables with
    -- bit 23 set. See also the documentation just below the =Opcode decoding
    -- table= header.
    syntax_reg                  : syllable_syntax_type;
    syntax_imm                  : syllable_syntax_type;
    
    -- Instruction valid. When this is low, attempting to execute this
    -- instruction raises an invalid instruction exception. This is indexed
    -- by bit 23 of the syllable, which determines whether operand 2 is a
    -- register or an immediate.
    valid                       : std_logic_vector(1 downto 0);
    
    -- Control signals for datapath.
    datapathCtrl                : datapathCtrlSignals_type;
    
    -- Control signals for the ALU.
    aluCtrl                     : aluCtrlSignals_type;
    
    -- Control signals for the branch unit.
    branchCtrl                  : branchCtrlSignals_type;
    
    -- Control signals for the memory unit.
    memoryCtrl                  : memoryCtrlSignals_type;
    
    -- Control signals for the multiplier unit.
    multiplierCtrl              : multiplierCtrlSignals_type;
    
  end record;
  
  -- Array type of the above to get a table. The index of this table is the
  -- opcode (the MSB of the syllable).
  type opcodeTable_type is array (0 to 2**rvex_opcode_type'LENGTH-1) of opcodeTableEntry_type;
  
  --===========================================================================
  -- Opcode decoding table
  --===========================================================================
  -- This table specifies how all instructions are decoded. It is generated by
  -- the scripts in the config directory.
  --
  -- Indexes in this table correspond to syllable bit 31 downto 24. The syntax
  -- formatter makes the following replacements when decoding the instruction.
  --   "%r1" --> Bit 22..17 in unsigned decimal.
  --   "%r2" --> Bit 16..11 in unsigned decimal.
  --   "%r3" --> Bit 10..5 in unsigned decimal.
  --   "%id" --> immediate, respecting long immediates. Displays the immediate
  --             in signed decimal form.
  --   "%iu" --> Same as above, but in unsigned decimal form.
  --   "%ih" --> Same as above, but in hex form.
  --   "%i1" --> Bit 27..25 in unsigned decimal for LIMMH target lane.
  --   "%i2" --> Bit 24..02 in hex for LIMMH.
  --   "%b1" --> Bit 26..24 in unsigned decimal.
  --   "%b2" --> Bit 19..17 in unsigned decimal.
  --   "%b3" --> Bit 4..2 in unsigned decimal.
  --   "%bi" --> Bit 23..5 in signed decimal (rfi/return stack offset).
  --   "%bt" --> Next PC + bit 23..5 in hex (branch target).
  --   "#"   --> Cluster identifier (maps to 0).
  
  @OPCODE_TABLE

end core_opcode_pkg;

package body core_opcode_pkg is
end core_opcode_pkg;
