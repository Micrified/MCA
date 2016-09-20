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
use IEEE.numeric_std.all;

library rvex;
use rvex.common_pkg.all;

--=============================================================================
-- This package contains constants specifying the word addresses of the control
-- registers as accessed from the debug bus or by a memory unit. It also
-- contains methods which generate register logic for several different kinds
-- of registers.
-------------------------------------------------------------------------------
package core_ctrlRegs_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Control register geometry
  -----------------------------------------------------------------------------
  -- The control register memory map is coarsely hardcoded in core_ctrlRegs.vhd
  -- as follows.
  --                                    | Core  | Debug |
  --         ___________________________|_______|_______|
  --  0x3FF | Context registers         |  R/W  |  R/W  |
  --  0x200 |___________________________|_______|_______|
  --  0x1FF | General purpose registers |   -   |  R/W  |
  --  0x100 |___________________________|_______|_______|
  --  0x0FF | Global registers          |   R   |  R/W  |
  --  0x000 |___________________________|_______|_______|
  --
  -- There are two ways to access these registers. The first is from the core
  -- itself, by making memory accesses to a contiguous region of memory mapped
  -- to the registers. The region is 1kiB in size and must be aligned to 1kiB
  -- boundaries; other than that, the location is specified by cregStartAddress
  -- in CFG. The second method is the debug bus. Because there is no context
  -- associated with the debug bus, bits 12..10 of the address are used to
  -- specify it. The global registers are mirrored for each context, but should
  -- always be read from context 0. That way, platforms can override those
  -- 256-byte regions with platform-specific registers without wasting address
  -- space. The debug bus can read from and write to everything, but the core
  -- itself has limited access, as shown in the table above.
  --
  -- The core can only access registers belonging to the context it is
  -- currently running internally. If cross-context access is needed, the
  -- memory bus of the rvex must be connected to the debug bus externally.
  --
  -- The registers are fully specified in the :/config/ directory of the
  -- repository.
  
  -- Size of the control register file accessible from the core through data
  -- memory operations.
  constant CRG_SIZE_BLOG2       : natural := 10;
  
  @CREG_CONSTANTS
end core_ctrlRegs_pkg;

package body core_ctrlRegs_pkg is
end core_ctrlRegs_pkg;
