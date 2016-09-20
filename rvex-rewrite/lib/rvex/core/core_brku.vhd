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
use rvex.utils_pkg.all;
use rvex.core_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_pipeline_pkg.all;
use rvex.core_trap_pkg.all;
use rvex.core_opcode_pkg.all;

--=============================================================================
-- This entity contains the optional hardware breakpoint unit for a pipelane.
-------------------------------------------------------------------------------
entity core_brku is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input.
    clkEn                       : in  std_logic;
    
    -- Active high stall input for the pipeline.
    stall                       : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Pipelane interface
    ---------------------------------------------------------------------------
    -- When high, breakpoints should be ignored this cycle.
    pl2brku_ignoreBreakpoint    : in  std_logic_vector(S_BRK to S_BRK);
    
    -- Opcode.
    pl2brku_opcode              : in  rvex_opcode_array(S_BRK to S_BRK);
    
    -- Address operand for the memory for access/write breakpoints.
    pl2brku_opAddr              : in  rvex_address_array(S_BRK to S_BRK);
    
    -- Current (bundle) PC for instruction breakpoints.
    pl2brku_PC_bundle           : in  rvex_address_array(S_BRK to S_BRK);
    
    -- (Debug) trap output.
    brku2pl_trap                : out trap_info_array(S_BRK+L_BRK to S_BRK+L_BRK);
    
    ---------------------------------------------------------------------------
    -- Debugging control signals
    ---------------------------------------------------------------------------
    -- Current breakpoint information.
    cxplif2brku_breakpoints     : in  cxreg2pl_breakpoint_info_array(S_BRK to S_BRK);
    
    -- Current value of the stepping flag in the debug control register. When
    -- high, a step trap must be triggered if there is no other trap and
    -- breakpoints are enabled.
    cxplif2brku_stepping        : in  std_logic_vector(S_BRK to S_BRK)
    
  );
end core_brku;

--=============================================================================
architecture Behavioral of core_brku is
--=============================================================================
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Make sure that the pipeline configuration correctly specifies that the
  -- breakpoint unit is combinatorial.
  assert L_BRK = 0
    report "Pipeline configuration: breakpoint unit latency (L_BRK) must be "
         & "set to 0."
    severity failure;

  -- We only support up to 4 breakpoints. Try to throw a nice error before
  -- killing simulation/synthesis with out-of-range errors.
  assert CFG.numBreakpoints <= 4
    report "Cannot support more than 4 breakpoints."
    severity failure;
  
  -- Determine whether to trigger a debug trap or not and if so, which.
  det_trap: process (
    pl2brku_ignoreBreakpoint, pl2brku_opcode, pl2brku_opAddr,
    pl2brku_PC_bundle, cxplif2brku_breakpoints, cxplif2brku_stepping
  ) is
    variable compareVal         : rvex_address_type;
    variable hit                : std_logic;
  begin
    
    -- Set to step complete breakpoint by default, with active set to the
    -- stepping mode flag.
    brku2pl_trap(S_BRK) <= (
      active => cxplif2brku_stepping(S_BRK),
      cause  => rvex_trap(RVEX_TRAP_STEP_COMPLETE),
      arg    => (others => '0')
    );
    
    -- Test for breakpoints.
    for i in 0 to CFG.numBreakpoints-1 loop
      
      -- Select between address and PC and select whether the breakpoint should
      -- be enabled based on breakpoint type.
      if cxplif2brku_breakpoints(S_BRK).cfg(i)(1) = '1' then
        
        -- Access breakpoint.
        compareVal := pl2brku_opAddr(S_BRK);
        
        if cxplif2brku_breakpoints(S_BRK).cfg(i)(0) = '1' then
          
          -- Hit on any memory access.
          hit := OPCODE_TABLE(vect2uint(pl2brku_opcode(S_MEM))).memoryCtrl.readEnable
              or OPCODE_TABLE(vect2uint(pl2brku_opcode(S_MEM))).memoryCtrl.writeEnable;
          
        else
          
          -- Hit only on writes.
          hit := OPCODE_TABLE(vect2uint(pl2brku_opcode(S_MEM))).memoryCtrl.writeEnable;
          
        end if;
        
      else
        
        -- Fetch breakpoint or breakpoint disabled.
        compareVal := pl2brku_PC_bundle(S_BRK);
        
        if cxplif2brku_breakpoints(S_BRK).cfg(i)(0) = '1' then
          
          -- Hit unconditionally if we have a match for fetch breakpoints.
          hit := '1';
          
        else
          
          -- Breakpoint disabled.
          hit := '0';
          
        end if;
        
      end if;
      
      -- Perform the address match.
      if compareVal /= cxplif2brku_breakpoints(S_BRK).addr(i) then
        hit := '0';
      end if;
      
      -- If we have a hit, activate the debug trap.
      if hit = '1' then
        brku2pl_trap(S_BRK).active <= '1';
        case i is
          when 0      => brku2pl_trap(S_BRK).cause <= rvex_trap(RVEX_TRAP_HW_BREAKPOINT_0);
          when 1      => brku2pl_trap(S_BRK).cause <= rvex_trap(RVEX_TRAP_HW_BREAKPOINT_1);
          when 2      => brku2pl_trap(S_BRK).cause <= rvex_trap(RVEX_TRAP_HW_BREAKPOINT_2);
          when others => brku2pl_trap(S_BRK).cause <= rvex_trap(RVEX_TRAP_HW_BREAKPOINT_3);
        end case;
      end if;
      
    end loop;
    
    -- Deactivate if breakpoints should be ignored.
    if pl2brku_ignoreBreakpoint(S_BRK) = '1' then
      brku2pl_trap(S_BRK).active <= '0';
    end if;
    
  end process;
  
end Behavioral;

