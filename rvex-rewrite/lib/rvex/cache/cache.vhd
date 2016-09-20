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
use rvex.bus_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;

--=============================================================================
-- This is the toplevel entity for the reconfigurable instruction and data
-- cache designed for the rvex core.
-------------------------------------------------------------------------------
entity cache is
--=============================================================================
  generic (
    
    -- Core configuration. Must be equal to the configuration presented to the
    -- rvex core connected to the cache.
    RCFG                        : rvex_generic_config_type := rvex_cfg;
    
    -- Cache configuration.
    CCFG                        : cache_generic_config_type := cache_cfg
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high CPU interface clock enable input.
    clkEnCPU                    : in  std_logic;
    
    -- Active high bus interface clock enable input.
    clkEnBus                    : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Core interface
    ---------------------------------------------------------------------------
    -- The data cache bypass signal may be used to access volatile memory
    -- regions (i.e. peripherals): when high, the cache is bypassed and the bus
    -- is accessed transparently. Refer to the entity description in core.vhd
    -- for documentation on the rest of the signals. The timing of these
    -- signals is governed by clkEnCPU.
    
    -- Common memory interface.
    rv2cache_decouple           : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    cache2rv_blockReconfig      : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    cache2rv_stallIn            : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2cache_stallOut           : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    cache2rv_status             : out rvex_cacheStatus_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    -- Instruction memory interface.
    rv2icache_PCs               : in  rvex_address_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2icache_fetch             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2icache_cancel            : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_instr             : out rvex_syllable_array(2**RCFG.numLanesLog2-1 downto 0);
    icache2rv_busFault          : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_affinity          : out std_logic_vector(2**RCFG.numLaneGroupsLog2*RCFG.numLaneGroupsLog2-1 downto 0);
    
    -- Data memory interface.
    rv2dcache_addr              : in  rvex_address_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_readEnable        : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_writeData         : in  rvex_data_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_writeMask         : in  rvex_mask_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_writeEnable       : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_bypass            : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_readData          : out rvex_data_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_busFault          : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_ifaceFault        : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus master interface
    ---------------------------------------------------------------------------
    -- Bus interface for the caches. The timing of these signals is governed by
    -- clkEnBus. 
    cache2bus_bus               : out bus_mst2slv_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    bus2cache_bus               : in  bus_slv2mst_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus snooping interface
    ---------------------------------------------------------------------------
    -- These signals are optional. They are needed for cache coherency on
    -- multi-processor systems and/or for dynamic cores. The timing of these
    -- signals is governed by clkEnBus.
    
    -- Bus address which is to be invalidated when invalEnable is high.
    bus2cache_invalAddr         : in  rvex_address_type := (others => '0');
    
    -- If one of the data caches is causing the invalidation due to a write,
    -- the signal in this vector indexed by that data cache must be high. In
    -- all other cases, these signals should be low.
    bus2cache_invalSource       : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    
    -- Active high enable signal for line invalidation.
    bus2cache_invalEnable       : in  std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- Status and control signals
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Cache flush request signals for each instruction and data cache.
    sc2icache_flush             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    sc2dcache_flush             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0) := (others => '0')
    
  );
end cache;

--=============================================================================
architecture Behavioral of cache is
--=============================================================================
  
  -- Instruction cache signals.
  signal icache2bus_bus         : bus_mst2slv_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal bus2icache_bus         : bus_slv2mst_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_blockReconfig: std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_stallIn      : std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_status_access: std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_status_miss  : std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  
  -- Data cache signals.
  signal dcache2bus_bus         : bus_mst2slv_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal bus2dcache_bus         : bus_slv2mst_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_blockReconfig: std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_stallIn      : std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_status       : dcache_status_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Instantiate the instruction cache
  -----------------------------------------------------------------------------
  icache_inst: entity rvex.cache_instr
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEnCPU                  => clkEnCPU,
      clkEnBus                  => clkEnBus,
      
      -- Core interface.
      rv2icache_decouple        => rv2cache_decouple,
      icache2rv_blockReconfig   => icache2rv_blockReconfig,
      icache2rv_stallIn         => icache2rv_stallIn,
      rv2icache_stallOut        => rv2cache_stallOut,
      rv2icache_PCs             => rv2icache_PCs,
      rv2icache_fetch           => rv2icache_fetch,
      rv2icache_cancel          => rv2icache_cancel,
      icache2rv_instr           => icache2rv_instr,
      icache2rv_affinity        => icache2rv_affinity,
      icache2rv_busFault        => icache2rv_busFault,
      icache2rv_status_access   => icache2rv_status_access,
      icache2rv_status_miss     => icache2rv_status_miss,
      
      -- Bus master interface.
      icache2bus_bus            => icache2bus_bus,
      bus2icache_bus            => bus2icache_bus,
      
      -- Bus snooping interface.
      bus2icache_invalAddr      => bus2cache_invalAddr,
      bus2icache_invalEnable    => bus2cache_invalEnable,
      
      -- Status and control signals.
      sc2icache_flush           => sc2icache_flush
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the data cache
  -----------------------------------------------------------------------------
  dcache_inst: entity rvex.cache_data
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEnCPU                  => clkEnCPU,
      clkEnBus                  => clkEnBus,
      
      -- Core interface.
      rv2dcache_decouple        => rv2cache_decouple,
      dcache2rv_blockReconfig   => dcache2rv_blockReconfig,
      dcache2rv_stallIn         => dcache2rv_stallIn,
      rv2dcache_stallOut        => rv2cache_stallOut,
      rv2dcache_addr            => rv2dcache_addr,
      rv2dcache_readEnable      => rv2dcache_readEnable,
      rv2dcache_writeData       => rv2dcache_writeData,
      rv2dcache_writeMask       => rv2dcache_writeMask,
      rv2dcache_writeEnable     => rv2dcache_writeEnable,
      rv2dcache_bypass          => rv2dcache_bypass,
      dcache2rv_readData        => dcache2rv_readData,
      dcache2rv_busFault        => dcache2rv_busFault,
      dcache2rv_ifaceFault      => dcache2rv_ifaceFault,
      dcache2rv_status          => dcache2rv_status,
      
      -- Bus master interface.
      dcache2bus_bus            => dcache2bus_bus,
      bus2dcache_bus            => bus2dcache_bus,
      
      -- Bus snooping interface.
      bus2dcache_invalAddr      => bus2cache_invalAddr,
      bus2dcache_invalSource    => bus2cache_invalSource,
      bus2dcache_invalEnable    => bus2cache_invalEnable,
      
      -- Status and control signals.
      sc2dcache_flush           => sc2dcache_flush
      
    );
  
  -----------------------------------------------------------------------------
  -- Merge blockReconfig and stallIn signals
  -----------------------------------------------------------------------------
  cache2rv_blockReconfig  <= icache2rv_blockReconfig or dcache2rv_blockReconfig;
  cache2rv_stallIn        <= icache2rv_stallIn       or dcache2rv_stallIn;
  
  -----------------------------------------------------------------------------
  -- Generate the status output signal
  -----------------------------------------------------------------------------
  status_output_gen: for laneGroup in 2**RCFG.numLaneGroupsLog2-1 downto 0 generate
    cache2rv_status(laneGroup)
      <= RVEX_CACHE_STATUS_IDLE when rv2cache_stallOut(laneGroup) = '1' else (
        instr_access                => icache2rv_status_access(laneGroup),
        instr_miss                  => icache2rv_status_miss(laneGroup),
        data_accessType             => dcache2rv_status(laneGroup).accessType,
        data_bypass                 => dcache2rv_status(laneGroup).bypass,
        data_miss                   => dcache2rv_status(laneGroup).miss,
        data_writePending           => dcache2rv_status(laneGroup).writePending
      );
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the data/instruction update bus arbiters
  -----------------------------------------------------------------------------
  bus_arbiter_gen: for laneGroup in 2**RCFG.numLaneGroupsLog2-1 downto 0 generate
    
    bus_arbiter_inst: entity rvex.bus_arbiter
      generic map (
        NUM_MASTERS             => 2
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEnBus,
        
        -- Master busses.
        mst2arb(1)              => icache2bus_bus(laneGroup),
        mst2arb(0)              => dcache2bus_bus(laneGroup),
        arb2mst(1)              => bus2icache_bus(laneGroup),
        arb2mst(0)              => bus2dcache_bus(laneGroup),
        
        -- Slave bus.
        arb2slv                 => cache2bus_bus(laneGroup),
        slv2arb                 => bus2cache_bus(laneGroup)
        
      );
    
  end generate;
  
end Behavioral;

