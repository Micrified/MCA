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

--=============================================================================
-- This entity controls long immediate routing between the pipelanes.
-------------------------------------------------------------------------------
entity core_limmRouting is
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
    
    -- Active high stall input for each pipelane group.
    stall                       : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
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
    -- LIMMH data from pipelanes. Enable is high when this pipelane is
    -- executing a LIMMH instruction, in which case target selects whether 
    -- value is intended for the neighboring pipelane or two pipelanes ahead by
    -- indexing the LSB of the destination pipelane index, and data contains
    -- the immediate. When valid is low, the LIMMH state is unaffected.
    pl2limm_valid               : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    pl2limm_enable              : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    pl2limm_target              : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    pl2limm_data                : in  rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- LIMMH data to pipelanes. When enable is high, the immediate operand for
    -- the associated lane should be extended using data.
    limm2pl_enable              : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    limm2pl_data                : out rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Error output. A bit in this goes high when a valid and enabled input
    -- has a target value which is not supported by the design-time core
    -- configuration.
    limm2pl_error               : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0)
    
  );
end core_limmRouting;

--=============================================================================
architecture Behavioral of core_limmRouting is
--=============================================================================
  
  -- LIMMH values and valid bits from the previous cycle, if
  -- limmhFromPreviousPair is selected in the generic configuration.
  signal limmh_r                : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
  signal limmh_r_valid          : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
  -- LIMMH from previous pair data and valid signals, routed to the appropriate
  -- destination lanes.
  signal limmhFromPrev          : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
  signal limmhFromPrevValid     : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
  -- LIMMH from neighboring lane in pair, routed to the appropriate destination
  -- lanes.
  signal limmhFromNeigh         : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
  signal limmhFromNeighValid    : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Check configuration
  -----------------------------------------------------------------------------
  assert CFG.limmhFromNeighbor or CFG.limmhFromPreviousPair
    report "LIMMH logic is completely disabled, are you sure this is what "
         & "you want? Check the values for CFG."
    severity warning;
    
  assert (CFG.numLanesLog2 - CFG.numLaneGroupsLog2) >= 1
    report "Lane group size is only 1, LIMMH logic does not make sense for "
         & "this configuration."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Generate registers for limmhFromPreviousPair
  -----------------------------------------------------------------------------
  -- Store the long immediates from the previous cycle if limmhFromPreviousPair
  -- is enabled.
  limmh_regs_gen: if CFG.limmhFromPreviousPair generate
    
    limmh_regs: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          
          -- Reset registers and validity flags.
          limmh_r <= (others => (others => '0'));
          limmh_r_valid <= (others => '0');
          
        elsif clkEn = '1' then
          for lane in 2**CFG.numLanesLog2-1 downto 0 loop
            
            -- Only update the registers when a valid instruction is being
            -- processed.
            if stall(lane2group(lane, CFG)) = '0' and pl2limm_valid(lane) = '1' then
              
              limmh_r(lane) <= pl2limm_data(lane);
              
              if lane mod 2 = 0 then
                limmh_r_valid(lane) <= pl2limm_enable(lane) and not pl2limm_target(lane);
              else
                limmh_r_valid(lane) <= pl2limm_enable(lane) and pl2limm_target(lane);
              end if;
              
            end if;
          end loop;
        end if;
      end if;
    end process;
    
  end generate;
  no_limmh_regs_gen: if not CFG.limmhFromPreviousPair generate
    
    -- Connect the register data to undefined/disabled values because they
    -- shouldn't be used.
    limmh_r <= (others => (others => RVEX_UNDEF));
    limmh_r_valid <= (others => '0');
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate limmhFromPreviousPair routing
  -----------------------------------------------------------------------------
  -- Generate LIMMH data routing for limmhFromPreviousPair.
  limmh_prev_routing_gen: if CFG.limmhFromPreviousPair generate
    
    limmh_prev_routing: process (
      limmh_r, limmh_r_valid,
      cfg2any_coupled, pl2limm_enable, pl2limm_target, pl2limm_data
    ) is
      variable limmhFromPrev_s      : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
      variable limmhFromPrevValid_s : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable laneA, laneB         : natural;
      variable coupled              : std_logic;
    begin
      
      -- Load the limmhFromPrev variables with the data from the previous
      -- cycle, so we can route that properly first.
      limmhFromPrev_s       := limmh_r;
      limmhFromPrevValid_s  := limmh_r_valid;
      
      -- Construct a binary tree to route the registered LIMMH data from the
      -- last lane pair to the first pair in a group. Refer to the
      -- documentation of binTreeIndices in utils_pkg.vhd for more info on the
      -- binary tree structure. Note that we start at level 1 because we're
      -- concerned with pairs, not single lanes.
      for level in 1 to CFG.numLanesLog2-1 loop
        for blockIndex in 0 to (2**CFG.numLanesLog2)/2-1 loop
          binTreeIndices(level, blockIndex, laneA, laneB);
          
          -- Determine whether these lanes are coupled.
          if lane2group(laneA, CFG) = lane2group(laneB, CFG) then
            coupled := '1';
          else
            coupled := cfg2any_coupled(lane2group(laneA, CFG) + lane2group(laneB, CFG) * 2**CFG.numLaneGroupsLog2);
          end if;
          
          -- If the lanes are coupled, route from the higher indexed lane to
          -- the lower indexed lane.
          if coupled = '1' then
            limmhFromPrev_s(laneA)      := limmhFromPrev_s(laneB);
            limmhFromPrevValid_s(laneA) := limmhFromPrevValid_s(laneB);
          end if;
          
        end loop;
      end loop;
      
      -- Override the routed data with the combinatorial inputs for lanes for
      -- which the previous pair is executed in the same cycle.
      for lane in 2 to 2**CFG.numLanesLog2-1 loop
        laneA := lane - 2;
        laneB := lane;
        
        -- Determine whether these lanes are coupled.
        if lane2group(laneA, CFG) = lane2group(laneB, CFG) then
          coupled := '1';
        else
          coupled := cfg2any_coupled(lane2group(laneA, CFG) + lane2group(laneB, CFG) * 2**CFG.numLaneGroupsLog2);
        end if;
        
        -- If the lanes are coupled, override the data for the higher indexed
        -- lane with the combinatorial data from the lower indexed lane. If
        -- they are not coupled, the registered data from the binary tree is
        -- valid so we shouldn't do anything.
        if coupled = '1' then
          limmhFromPrev_s(laneB)      := pl2limm_data(laneA);
          if laneA mod 2 = 0 then
            limmhFromPrevValid_s(laneB) := pl2limm_enable(laneA) and not pl2limm_target(laneA);
          else
            limmhFromPrevValid_s(laneB) := pl2limm_enable(laneA) and pl2limm_target(laneA);
          end if;
        end if;
        
      end loop;
      
      -- Drive the output signals.
      limmhFromPrev       <= limmhFromPrev_s;
      limmhFromPrevValid  <= limmhFromPrevValid_s;
      
    end process;
    
  end generate;
  no_limmh_prev_routing_gen: if not CFG.limmhFromPreviousPair generate
    
    -- Connect the output data to undefined/disabled so it isn't used by the
    -- muxing logic.
    limmhFromPrev <= (others => (others => RVEX_UNDEF));
    limmhFromPrevValid <= (others => '0');
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate limmhFromNeighbor routing
  -----------------------------------------------------------------------------
  -- Generate LIMMH data routing for limmhFromPreviousPair.
  limmh_neighbor_routing_gen: if CFG.limmhFromNeighbor generate
    
    limmh_neighbor_routing: process (
      pl2limm_enable, pl2limm_target, pl2limm_data
    ) is
      variable otherLane        : natural;
    begin
      
      -- Loop over all the lanes and connect the output to the other lane in
      -- their pair.
      for lane in 0 to 2**CFG.numLanesLog2-1 loop
        
        -- Flip the LSB of the lane index to get the index for the other lane
        -- in the pair.
        otherLane := flipBit(lane, 0);
        
        -- The data is valid when the other lane is executing a LIMMH
        -- instruction with target set to 1.
        limmhFromNeigh(lane) <= pl2limm_data(otherLane);
        if otherLane mod 2 = 0 then
          limmhFromNeighValid(lane) <= pl2limm_enable(otherLane) and pl2limm_target(otherLane);
        else
          limmhFromNeighValid(lane) <= pl2limm_enable(otherLane) and not pl2limm_target(otherLane);
        end if;
        
      end loop;
      
    end process;
    
  end generate;
  no_limmh_neighbor_routing_gen: if not CFG.limmhFromNeighbor generate
    
    -- Connect the output data to undefined/disabled so it isn't used by the
    -- muxing logic.
    limmhFromNeigh <= (others => (others => RVEX_UNDEF));
    limmhFromNeighValid <= (others => '0');
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Mux between LIMMH data signals and generate error signals
  -----------------------------------------------------------------------------
  limmh_data_and_error: process (
    limmhFromPrev, limmhFromPrevValid,
    limmhFromNeigh, limmhFromNeighValid,
    pl2limm_valid, pl2limm_enable, pl2limm_target
  ) is
  begin
    for lane in 2**CFG.numLanesLog2-1 downto 0 loop
      
      -- Drive the data and valid signals.
      if limmhFromPrevValid(lane) = '1' then
        limm2pl_data(lane)   <= limmhFromPrev(lane);
        limm2pl_enable(lane) <= limmhFromPrevValid(lane);
      else
        limm2pl_data(lane)   <= limmhFromNeigh(lane);
        limm2pl_enable(lane) <= limmhFromNeighValid(lane);
      end if;
      
      -- Drive the error signal. Assume no error, then try to find one.
      limm2pl_error(lane) <= '0';
      
      -- Check for unsupported forwarding requests.
      if pl2limm_valid(lane) = '1' and pl2limm_enable(lane) = '1' then
        
        -- Trying to target neighboring lane in pair.
        if ((pl2limm_target(lane) = '1') = (lane mod 2 = 0)) and not CFG.limmhFromNeighbor then
          limm2pl_error(lane) <= '1';
        end if;
        
        -- Trying to target next pair.
        if ((pl2limm_target(lane) = '0') = (lane mod 2 = 0)) and not CFG.limmhFromPreviousPair then
          limm2pl_error(lane) <= '1';
        end if;
        
      end if;
      
      -- Check for forwarding collisions (when two lanes try to forward to the
      -- same lane).
      if limmhFromPrevValid(lane) = '1' and limmhFromNeighValid(lane) = '1' then
        limm2pl_error(lane) <= '1';
      end if;
      
    end loop;
  end process;
  
end Behavioral;

