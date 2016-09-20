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

--=============================================================================
-- This package specifies the control signal encoding for the branch unit.
-------------------------------------------------------------------------------
package core_opcodeBranch_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Branch unit control signals
  -----------------------------------------------------------------------------
  type branchCtrlSignals_type is record
    
    -- When this instruction is executed on a lane without a branch unit, an
    -- invalid instruction exception will be raised.
    isBranchInstruction         : std_logic;
    
    -- When high, a branch will occur if the currently addressed branch
    -- register (by brRegAddr) is high/true.
    branchIfTrue                : std_logic;
    
    -- When high, a branch will occur if the currently addressed branch
    -- register (by brRegAddr) is low/false.
    branchIfFalse               : std_logic;
    
    -- Branch target selection. When low, the target is set to PC+1 +
    -- branch immediate. When high, the target is the current contents of the
    -- link register. Return from interrupt overrides the target to the proper
    -- control register when enabled.
    branchToLink                : std_logic;
    
    -- Determines whether or not the link register should be assigned to
    -- PC_plusOne or not, for call and icall. Active high.
    link                        : std_logic;
    
    -- Stop instruction detected signal. When high, the branch logic above is
    -- overridden and the system will branch back to the bundle which contains
    -- the stop instruction. In addition, the done output to run control is
    -- asserted.
    stop                        : std_logic;
    
    -- Return-from-interrupt override signal. When high, the branch logic above
    -- is overridden, and a branch to the trapPoint control register is taken
    -- unconditionally. In addition, the trap control registers are updated
    -- appropriately.
    RFI                         : std_logic;
    
  end record;
  
  -- Array type.
  type branchCtrlSignals_array is array (natural range <>) of branchCtrlSignals_type;
  
  -- Undefined value for the branch control signals.
  constant BRANCH_CTRL_UNDEF    : branchCtrlSignals_type := (
    others                      => RVEX_UNDEF
  );
  
end core_opcodeBranch_pkg;

package body core_opcodeBranch_pkg is
end core_opcodeBranch_pkg;
