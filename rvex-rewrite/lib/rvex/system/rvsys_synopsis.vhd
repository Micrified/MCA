-- r-VEX processor
-- Copyright (C) 2008-2015 by TU Delft.
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

-- Copyright (C) 2008-2015 by TU Delft.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.bus_pkg.all;
use rvex.core_pkg.all;
use rvex.rvsys_standalone_pkg.all;
use rvex.rvsys_synopsis_pkg.all;

--=============================================================================
-- This unit wraps the rvex core, bridging between the raw data/instruction
-- I/O ports and a number of busses as specified in bus_pkg.vhd.
-------------------------------------------------------------------------------
entity rvsys_synopsis is
--=============================================================================
  generic (
    
    -- Standalone system configuration.
    CFG                         : rvex_sa_generic_config_type := rvex_synopsis_cfg
    
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
    -- Run control interface
    ---------------------------------------------------------------------------
    -- External interrupt request signal, active high.
    rctrl2rvsa_irq              : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '0');
    
    -- External interrupt identification. Guaranteed to be loaded in the trap
    -- argument register in the same clkEn'd cycle where irqAck is high.
    rctrl2rvsa_irqID            : in  rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0) := (others => (others => '0'));
    
    -- External interrupt acknowledge signal, active high. Goes high for one
    -- clkEn'abled cycle.
    rvsa2rctrl_irqAck           : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    -- Active high run signal. When released, the context will stop running as
    -- soon as possible.
    rctrl2rvsa_run              : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '1');
    
    -- Active high idle output. This is asserted when the core is no longer
    -- doing anything.
    rvsa2rctrl_idle             : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    -- Active high context reset input. When high, the context control
    -- registers (including PC, done and break flag) will be reset.
    rctrl2rvsa_reset            : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '0');
    
    -- Active high done output. This is asserted when the context encounters
    -- a stop syllable. Processing a stop signal also sets the BRK control
    -- register, which stops the core. This bit can be reset by issuing a core
    -- reset or by means of the debug interface.
    rvsa2rctrl_done             : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus interfaces
    ---------------------------------------------------------------------------
    -- Instruction memory busses. There are as many of these as there are
    -- lanes in the rvex, since the bus width is 32 bits. The write requests
    -- are tied to no-op. The combined request of a lane group is always an
    -- aligned read of the width of the lanes in the group.
    rv2imem                     : out bus_mst2slv_array(2**CFG.core.numLanesLog2-1 downto 0);
    imem2rv                     : in  bus_slv2mst_array(2**CFG.core.numLanesLog2-1 downto 0);
    
    -- Data memory busses.
    rv2dmem                     : out bus_mst2slv_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
    dmem2rv                     : in  bus_slv2mst_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
    
    -- Debug bus.
    dbg2rv                      : in  bus_mst2slv_type;
    rv2dbg                      : out bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Trace interface
    ---------------------------------------------------------------------------
    -- These signals connect to the optional trace unit. When the trace unit is
    -- disabled in CFG, these signals are unused.
    
    -- When high, data is valid and should be registered in the next clkEn'd
    -- cycle.
    rv2trsink_push              : out std_logic;
    
    -- Trace data signal. Valid when push is high.
    rv2trsink_data              : out rvex_byte_type;
    
    -- When high, this is the last byte of this trace packet. This has the same
    -- timing as the data signal.
    rv2trsink_end               : out std_logic;
    
    -- When high while push is high, the trace unit is stalled. While stalled,
    -- push will stay high and data and end will remain stable.
    trsink2rv_busy              : in  std_logic := '0'
    
  );
end rvsys_synopsis;

--=============================================================================
architecture Behavioral of rvsys_synopsis is
--=============================================================================
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Check configuration.
  assert CFG.core.gpRegImpl /= RVEX_GPREG_IMPL_SIMPLE
    report "rvsys_synopsis instantiated with wrong register file arch "
         & "(CFG.gpRegImpl). It should be set to RVEX_GPREG_IMPL_SIMPLE."
    severity failure;

  -- Instantiate the standalone core.
  core: entity rvex.rvsys_standalone_core
    generic map (
      CFG                     => CFG
    )
    port map (
      
      -- System control.
      reset                   => reset,
      clk                     => clk,
      clkEn                   => clkEn,
      
      -- Run control interface.
      rctrl2rvsa_irq          => rctrl2rvsa_irq,
      rctrl2rvsa_irqID        => rctrl2rvsa_irqID,
      rvsa2rctrl_irqAck       => rvsa2rctrl_irqAck,
      rctrl2rvsa_run          => rctrl2rvsa_run,
      rvsa2rctrl_idle         => rvsa2rctrl_idle,
      rctrl2rvsa_reset        => rctrl2rvsa_reset,
      rvsa2rctrl_done         => rvsa2rctrl_done,
      
      -- Instruction memory busses.
      rv2imem                 => rv2imem,
      imem2rv                 => imem2rv,
      
      -- Data memory busses.
      rv2dmem                 => rv2dmem,
      dmem2rv                 => dmem2rv,
      
      -- Debug bus.
      dbg2rv                  => dbg2rv,
      rv2dbg                  => rv2dbg,
      
      -- Trace interface.
      rv2trsink_push          => rv2trsink_push,
      rv2trsink_data          => rv2trsink_data,
      trsink2rv_busy          => trsink2rv_busy
      
    );
  
end Behavioral;

