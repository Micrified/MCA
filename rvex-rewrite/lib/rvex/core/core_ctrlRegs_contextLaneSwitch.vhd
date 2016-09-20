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

--=============================================================================
-- This entity contains the bus interconnect between the pipelane memory unit
-- busses and the context specific register file. When two groups try to access
-- the same context simultaneously, the highest indexed group will take
-- precedence. However, this is not something which should ever happen; after
-- all, the lower indexed group(s) will be ignored and read garbage.
-------------------------------------------------------------------------------
entity core_ctrlRegs_contextLaneSwitch is
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
    
    ---------------------------------------------------------------------------
    -- Pipelane group bus interfaces
    ---------------------------------------------------------------------------
    -- Control register address from memory unit, shared between read and write
    -- command. Address bits 9..0 are forwarded to the contexts, bits 12..10
    -- are used to select the context.
    plgrp2sw_addr               : in  rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    plgrp2sw_writeEnable        : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    plgrp2sw_writeMask          : in  rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    plgrp2sw_writeData          : in  rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    plgrp2sw_readEnable         : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    sw2plgrp_readData           : out rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Context interface
    ---------------------------------------------------------------------------
    -- Control register address from memory unit, shared between read and write
    -- command. Address bits 9..0 are forwarded to the contexts, bits 12..10
    -- are used to select the context.
    sw2ctxt_addr                : out rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    sw2ctxt_writeEnable         : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    sw2ctxt_writeMask           : out rvex_mask_array(2**CFG.numContextsLog2-1 downto 0);
    sw2ctxt_writeData           : out rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    sw2ctxt_readEnable          : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    ctxt2sw_readData            : in  rvex_data_array(2**CFG.numContextsLog2-1 downto 0)
    
  );
end core_ctrlRegs_contextLaneSwitch;

--=============================================================================
architecture Behavioral of core_ctrlRegs_contextLaneSwitch is
--=============================================================================
  
  -- Context to lane group mapping for the command muxes.
  subtype laneGroup_type is std_logic_vector(CFG.numLaneGroupsLog2-1 downto 0);
  type laneGroup_array is array (natural range <>) of laneGroup_type;
  signal contextMap             : laneGroup_array(2**CFG.numContextsLog2-1 downto 0);
  
  -- Enable signal for each context. The enable signal goes high when at least
  -- one core is accessing the context. When low, the read/write enable signals
  -- coming from the mux should be masked.
  signal contextEnable          : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  
  -- Lane group to context mapping for the read results.
  subtype context_type is std_logic_vector(CFG.numContextsLog2-1 downto 0);
  type context_array is array (natural range <>) of context_type;
  signal laneGroupMap_r         : context_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Command muxing from lane groups to contexts (bus command)
  -----------------------------------------------------------------------------
  -- Generate the context to lane group mapping signal.
  context_map_proc: process (
    plgrp2sw_addr, plgrp2sw_writeEnable, plgrp2sw_readEnable
  ) is
    variable laneGroup  : laneGroup_type;
  begin
    for ctxt in 2**CFG.numContextsLog2-1 downto 0 loop
      
      -- When there is no access, default to bus zero with the context
      -- disabled.
      contextMap(ctxt) <= (others => '0');
      contextEnable(ctxt) <= '0';
      
      -- Override lane group choice when a lane group tries to access ctxt.
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        if CFG.numContextsLog2 = 0 or vect2uint(
          plgrp2sw_addr(laneGroup)(10+CFG.numContextsLog2-1 downto 10)
        ) = ctxt then
          if plgrp2sw_readEnable(laneGroup) = '1'
            or plgrp2sw_writeEnable(laneGroup) = '1'
          then
            contextMap(ctxt) <= uint2vect(laneGroup, CFG.numLaneGroupsLog2);
            contextEnable(ctxt) <= '1';
          end if;
        end if;
      end loop;
      
    end loop;
  end process;
  
  -- Generate the command muxes.
  command_mux_gen: for ctxt in 2**CFG.numContextsLog2-1 downto 0 generate
    sw2ctxt_addr(ctxt)        <= plgrp2sw_addr(vect2uint(contextMap(ctxt))) and X"000003FF";
    sw2ctxt_writeEnable(ctxt) <= plgrp2sw_writeEnable(vect2uint(contextMap(ctxt))) and contextEnable(ctxt);
    sw2ctxt_writeMask(ctxt)   <= plgrp2sw_writeMask(vect2uint(contextMap(ctxt)));
    sw2ctxt_writeData(ctxt)   <= plgrp2sw_writeData(vect2uint(contextMap(ctxt)));
    sw2ctxt_readEnable(ctxt)  <= plgrp2sw_readEnable(vect2uint(contextMap(ctxt))) and contextEnable(ctxt);
  end generate;
  
  -----------------------------------------------------------------------------
  -- Command muxing from contexts to lane groups (bus read result)
  -----------------------------------------------------------------------------
  -- Delay the lane group to context mapping signals from the incoming address
  -- by one cycle to align it with the read result.
  lane_group_map_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        laneGroupMap_r <= (others => (others => '0'));
      elsif clkEn = '1' then
        for laneGroup in 2**CFG.numLaneGroupsLog2-1 downto 0 loop
          laneGroupMap_r(laneGroup) <= plgrp2sw_addr(laneGroup)(10+CFG.numContextsLog2-1 downto 10);
        end loop;
      end if;
    end if;
  end process;
  
  -- Generate the result muxes.
  result_mux_gen: for laneGroup in 2**CFG.numLaneGroupsLog2-1 downto 0 generate
    sw2plgrp_readData(laneGroup) <= ctxt2sw_readData(vect2uint(laneGroupMap_r(laneGroup)));
  end generate;
  
end Behavioral;

