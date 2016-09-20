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
use rvex.core_trap_pkg.all;
use rvex.core_pipeline_pkg.all;

--=============================================================================
-- This entity controls trap arbitration, merging and forwarding.
-------------------------------------------------------------------------------
entity core_trapRouting is
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
    -- Indicates whether an exception is active for each pipeline stage and
    -- lane and if so, which.
    pl2trap_trap                : in  trap_info_stages_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Trap information record from the final pipeline stage, combined from all
    -- coupled pipelines.
    trap2pl_trapToHandle        : out trap_info_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether a trap is in the pipeline somewhere. When this is high,
    -- instruction fetching can be halted to speed things up.
    trap2pl_trapPending         : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Trap disable outputs. When high, any trap caused by the instruction in
    -- the respective stage/lane should be disabled/ignored, which happens when
    -- an earlier instruction in a coupled lane is causing a trap.
    trap2pl_disable             : out std_logic_stages_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Stage flushing outputs. When high, the instruction in the respective
    -- stage/lane should no longer be committed/be deactivated.
    trap2pl_flush               : out std_logic_stages_array(2**CFG.numLanesLog2-1 downto 0)
    
  );
end core_trapRouting;

--=============================================================================
architecture Behavioral of core_trapRouting is
--=============================================================================
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Route all the traps.
  trap_routing: process (cfg2any_coupled, pl2trap_trap) is
    variable combinedTraps      : trap_info_stages_array(2**CFG.numLanesLog2-1 downto 0);
    variable combined           : trap_info_type;
    variable choice             : std_logic;
    variable laneA, laneB       : natural;
    variable coupled            : std_logic;
    variable firstLane          : natural;
    variable trapInPipeline     : std_logic;
  begin
    
    -- Load the trap signals into a variable so we can modify them.
    combinedTraps := pl2trap_trap;
    
    -- Construct a binary tree to connect everything together. Refer to the
    -- documentation of binTreeIndices in utils_pkg.vhd for more info.
    for level in 0 to CFG.numLanesLog2-1 loop
      for blockIndex in 0 to (2**CFG.numLanesLog2)/2-1 loop
        binTreeIndices(level, blockIndex, laneA, laneB);
        
        -- Determine whether these lanes are coupled.
        if lane2group(laneA, CFG) = lane2group(laneB, CFG) then
          coupled := '1';
        else
          coupled := cfg2any_coupled(lane2group(laneA, CFG) + lane2group(laneB, CFG) * 2**CFG.numLaneGroupsLog2);
        end if;
        
        -- Merge the trap signals for each stage, giving priority to the lower
        -- indexed pipelane, unless the lower indexed pipelane trap is a step
        -- trap, which is always recessive.
        if coupled = '1' then
          for stage in S_FIRST to S_LTRP loop
            
            -- Determine whether we should use the trap information from the
            -- lower of higher indexed pipelane. Choose the upper if the
            -- lower is not active.
            choice := not combinedTraps(laneA)(stage).active;
            
            -- If the upper is active and the lower is a step trap, override
            -- the default and choose the upper.
            -- 04/2016: um, this is a bit dubious. Shouldn't debug traps always
            -- take precedence? I have no idea anymore why I wrote it this way.
            if combinedTraps(laneB)(stage).active = '1' then
              if combinedTraps(laneA)(stage).cause = rvex_trap(RVEX_TRAP_STEP_COMPLETE) then
                choice := '1';
              end if;
            end if;
            
            -- Mux between the lower and higher indexed traps.
            if choice = '1' then
              combined := combinedTraps(laneB)(stage);
            else
              combined := combinedTraps(laneA)(stage);
            end if;
            
            -- Shortcut for the active signal, which is always just an or
            -- function regardless of the complicated choice logic above.
            combined.active := combinedTraps(laneA)(stage).active
                            or combinedTraps(laneB)(stage).active;
            
            combinedTraps(laneA)(stage) := combined;
            combinedTraps(laneB)(stage) := combined;
            
          end loop;
        end if;
        
      end loop;
    end loop;
    
    -- Drive the signals for each lane.
    for lane in 2**CFG.numLanesLog2-1 downto 0 loop
      
      -- Compute the index of the first pipelane in the group and use that as
      -- the trap info source. This is just to make sure the unnecessary
      -- outputs of the binary tree network are properly optimized away.
      firstLane := lane2firstLane(lane, CFG);
      
      -- Handle the flushing logic.
      trapInPipeline := '0';
      for stage in S_LTRP downto S_FIRST loop
        
        -- Disable trap if there is a trap in a later pipeline stage.
        trap2pl_disable(lane)(stage) <= trapInPipeline;
        
        -- Look for traps in connected pipelanes.
        trapInPipeline := trapInPipeline or combinedTraps(firstLane)(stage).active;
        
        -- Disable instruction if there is a trap in this or a later pipeline
        -- stage.
        trap2pl_flush(lane)(stage) <= trapInPipeline;
        
      end loop;
      
      -- Drive trapPending signal. This will cause the branch unit to
      -- constantly "branch" to the current instruction, which will essentially
      -- prevent instruction fetches. Note though, that when the branch unit
      -- branches, S_IF+1 through S_BR-1 are flushed. We have to make sure that
      -- that doesn't happen yet there's a trap before S_BR-1, because the
      -- branch unit could then incorrectly flush an instruction *before* the
      -- trapping instruction, mistaking it for a branch delay slot! So we can't
      -- just connect trap2pl_trapPending to the trapInPipeline signal above.
      -- The same thing goes for a trap in S_BR-1, but then it's even worse
      -- because the pipeline is actually supposed to disable/flush the stage
      -- which is causing the trap... which makes no sense. So basically, we
      -- should only start the check from S_BR onwards. In reality it doesn't
      -- matter because the pipelanes only start forwarding traps from S_BR
      -- onwards anyway, but from a defensive programming point of view it's not
      -- a bad idea to check it here.
      --
      -- In addition, for some reason S_LTRP should not be taken into
      -- consideration. At least, that's the way I found it a year after I wrote
      -- the code and I'm not sure why.
      trapInPipeline := '0';
      for stage in S_LTRP-1 downto S_BR loop
        trapInPipeline := trapInPipeline or combinedTraps(firstLane)(stage).active;
      end loop;
      trap2pl_trapPending(lane) <= trapInPipeline;
      
      -- Forward trapToHandle signal.
      trap2pl_trapToHandle(lane) <= combinedTraps(firstLane)(S_LTRP);
      
    end loop;
    
  end process;
  
  
end Behavioral;


-- The commented out architecture below can handle any kind of couple matrix,
-- but it's also a little big:
--   1-bit 2-to-1 multiplexer         : 377
--   32-bit 2-to-1 multiplexer        : 61
--   8-bit 2-to-1 multiplexer         : 61
--   Maximum combinational path delay : 6.898ns
--
-- These are synthesis results for 8-way core with 4 lane groups.
--
-- For comparison, the code above gives this:
--   1-bit 2-to-1 multiplexer         : 80
--   32-bit 2-to-1 multiplexer        : 16
--   8-bit 2-to-1 multiplexer         : 16
--   Maximum combinational path delay : 3.443ns
--
----=============================================================================
--architecture Behavioral of core_trapRouting is
----=============================================================================
--
----=============================================================================
--begin -- architecture
----=============================================================================
--  
--  -- Route all the traps.
--  trap_routing: process (cfg2any_coupled, pl2trap_trap) is
--    variable trapInPipeline     : std_logic;
--    variable trapToHandle       : trap_info_type;
--  begin
--    
--    -- Loop over all the lanes for the destination lane.
--    for destLane in 2**CFG.numLanesLog2-1 downto 0 loop
--      
--      -- Handle the flushing logic.
--      trapInPipeline := '0';
--      for stage in S_LTRP downto S_FIRST loop
--        
--        -- Disable trap if there is a trap in a later pipeline stage.
--        trap2pl_disable(destLane)(stage) <= trapInPipeline;
--        
--        -- Look for traps in connected pipelanes.
--        for srcLane in 2**CFG.numLanesLog2-1 downto 0 loop
--          if cfg2any_coupled(
--            lane2group(srcLane, CFG) + 2**CFG.numLaneGroupsLog2*lane2group(destLane, CFG)
--          ) = '1' then
--            if pl2trap_trap(srcLane)(stage).active = '1' then
--              trapInPipeline := '1';
--            end if;
--          end if;
--        end loop;
--        
--        -- Disable instruction if there is a trap in this or a later pipeline
--        -- stage.
--        trap2pl_flush(destLane)(stage) <= trapInPipeline;
--        
--      end loop;
--      
--      -- Drive trapPending signal.
--      trap2pl_trapPending(destLane) <= trapInPipeline;
--      
--      -- Combine the traps from the last stage in connected pipelanes for the
--      -- trap which should be handled next cycle. Note that the & operator is
--      -- overloaded to combine two trap information typed records properly.
--      trapToHandle := TRAP_INFO_NONE;
--      for srcLane in 2**CFG.numLanesLog2-1 downto 0 loop
--        if cfg2any_coupled(
--          lane2group(srcLane, CFG) + 2**CFG.numLaneGroupsLog2*lane2group(destLane, CFG)
--        ) = '1' then
--          trapToHandle := trapToHandle & pl2trap_trap(srcLane)(S_LTRP);
--        end if;
--      end loop;
--      trap2pl_trapToHandle(destLane) <= trapToHandle;
--      
--    end loop;
--    
--  end process;
--  
--end Behavioral;
--
