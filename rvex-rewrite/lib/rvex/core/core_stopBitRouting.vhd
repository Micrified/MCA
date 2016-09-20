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
use rvex.core_opcode_pkg.all;

--=============================================================================
-- This entity controls stop bit based lane invalidation, and forwards the last
-- syllable in the compressed bundle to the last lane if its a branch
-- operation.
-------------------------------------------------------------------------------
entity core_stopBitRouting is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type
    
  );
  port (
    
    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : in  std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface
    ---------------------------------------------------------------------------
    -- Stop bit inputs from the pipelanes.
    pl2sbit_stop                : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Branch unit information from each pipelane.
    pl2sbit_valid               : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    pl2sbit_syllable            : in  rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
    pl2sbit_PC_ind              : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    pl2sbit_PC_fetchInd         : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Stop bit output. Processed such that exactly one lane within a coupled
    -- group has this bit set.
    sbit2pl_stop                : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Invalidation output for each pipelane. When high, the pipelane should
    -- not execute/commit its syllable.
    sbit2pl_invalidate          : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Information for the branch unit. This is all forwarded from the pipelane
    -- with the stop bit to the last lane, which contains the active branch
    -- unit.
    sbit2pl_valid               : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    sbit2pl_syllable            : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    sbit2pl_PC_ind              : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    sbit2pl_PC_fetchInd         : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0)
    
  );
end core_stopBitRouting;

--=============================================================================
architecture Behavioral of core_stopBitRouting is
--=============================================================================
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  routing: process (
    cfg2any_coupled, pl2sbit_stop, pl2sbit_valid, pl2sbit_syllable,
    pl2sbit_PC_ind, pl2sbit_PC_fetchInd
  ) is
    
    -- This is set to true when the current pipelane is the last in the set of
    -- coupled pipelane groups.
    variable endsGroup          : boolean;
    
    -- Temporary variable, high when the incoming syllable for the current
    -- pipelane is a branch syllable.
    variable isBranch           : std_logic;
    
    -- Routing network (when loop-unrolled) for the stop bit.
    variable invalidate         : std_logic;
    
    -- Routing networks (when loop-unrolled) for the branch units.
    variable branchValid        : std_logic;
    variable syllable           : rvex_address_type;
    variable PC_ind             : rvex_address_type;
    variable PC_fetchInd        : rvex_address_type;
    
  begin
    
    -- Initialize the routing network variables.
    invalidate    := '0';
    branchValid   := '0';
    syllable      := pl2sbit_syllable(0);     -- Don't care.
    PC_ind        := pl2sbit_PC_ind(0);       -- Don't care.
    PC_fetchInd   := pl2sbit_PC_fetchInd(0);  -- Don't care.
    
    for lane in 0 to 2**CFG.numLanesLog2-1 loop
      
      -- Determine endsGroup.
      endsGroup := true;
      if lane < 2**CFG.numLanesLog2-1 then
        if cfg2any_coupled(lane2group(lane+1, CFG) + lane2group(lane, CFG)*2**CFG.numLaneGroupsLog2) = '1' then
          endsGroup := false;
        end if;
      end if;
      
      -- Set defaults for the outputs.
      sbit2pl_stop(lane)            <= '0';
      sbit2pl_invalidate(lane)      <= invalidate;
      sbit2pl_valid(lane)           <= '0';
      sbit2pl_syllable(lane)        <= syllable;
      
      -- If there is a branch operation pending in the network, revalidate the
      -- last lane using that operation.
      if endsGroup and branchValid = '1' then
        sbit2pl_valid(lane) <= '1';
        sbit2pl_invalidate(lane) <= '0';
      end if;
      
      -- Update the network signals.
      if (endsGroup or pl2sbit_stop(lane) = '1') and invalidate = '0' then
        invalidate  := '1';
        
        -- Report that this is the last valid syllable in the bundle.
        sbit2pl_stop(lane) <= '1';
        
        -- Determine whether the incoming syllable is a branch operation.
        isBranch    := OPCODE_TABLE(vect2uint(pl2sbit_syllable(lane)(rvex_opcode_type'range))).branchCtrl.isBranchInstruction;
        
        -- If stop is set and syllable marks a valid branch operation,
        -- forward the branch operation to the last coupled pipelane, which
        -- contains the branch unit.
        branchValid     := pl2sbit_valid(lane) and isBranch;
        syllable        := pl2sbit_syllable(lane);
        PC_ind          := pl2sbit_PC_ind(lane);
        PC_fetchInd     := pl2sbit_PC_fetchInd(lane);
        
        -- If we're forwarding the branch operation to the last lane,
        -- invalidate this lane so we don't execute the syllable twice.
        -- Unless, of course, this already is the last lane.
        if not endsGroup and branchValid = '1' then
          sbit2pl_invalidate(lane) <= '1';
        end if;
        
      end if;
      
      -- Output the PC.
      sbit2pl_PC_ind(lane)      <= PC_ind;
      sbit2pl_PC_fetchInd(lane) <= PC_fetchInd;
      
      -- Reset the network when we're at the end of a group.
      if endsGroup then
        invalidate := '0';
        branchValid := '0';
      end if;
      
    end loop;
    
  end process;
  
end Behavioral;

