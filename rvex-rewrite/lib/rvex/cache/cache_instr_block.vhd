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
-- This entity represents a single instruction cache block.
-------------------------------------------------------------------------------
entity cache_instr_block is
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
    -- Routing interface
    ---------------------------------------------------------------------------
    -- Requested address/PC.
    route2block_PC              : in  rvex_address_type;
    
    -- Registered version of the requested PC.
    block2route_PC_r            : out rvex_address_type;
    
    -- Read enable signal from the lane group, active high.
    route2block_readEnable      : in  std_logic;
    
    -- Registered read enable signal from the lane group, active high.
    block2route_readEnable_r    : out std_logic;
    
    -- Hit output from the cache.
    block2route_hit             : out std_logic;
    
    -- This signal is high when this block should update the currently
    -- requested address. When it is low and there is a miss, the block must
    -- remain idle.
    route2block_updateEnable    : in  std_logic;
    
    -- Cancel signal from the lane group, active high. When high, miss handling
    -- may be interrupted because the core has determined it does not need the
    -- instruction.
    route2block_cancel          : in  std_logic;
    
    -- Combined pipeline stall signal from the lane groups.
    route2block_stall           : in  std_logic;
    
    -- Cache line data, valid when hit and readEnable are high.
    block2route_line            : out std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
    
    -- Block reconfiguration signal. This is asserted when any block is busy.
    block2route_blockReconfig   : out std_logic;    
    
    -- Bus fault signal. This is asserted when a bus fault occured while
    -- validating the cache.
    block2route_busFault        : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Bus master interface
    ---------------------------------------------------------------------------
    -- Bus interface for the cache block. The timing of these signals is
    -- governed by clkEnBus. 
    icache2bus_bus              : out bus_mst2slv_type;
    bus2icache_bus              : in  bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Bus snooping interface
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Bus address which is to be invalidated when invalEnable is high.
    bus2icache_invalAddr        : in  rvex_address_type;
    
    -- Active high enable signal for line invalidation.
    bus2icache_invalEnable      : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Status and control signals
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Cache flush request signals for each instruction cache block.
    sc2icache_flush             : in  std_logic
    
  );
end cache_instr_block;

--=============================================================================
architecture Behavioral of cache_instr_block is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- CPU data network signals
  -----------------------------------------------------------------------------
  -- CPU address register. This stores the address from the CPU whenever the
  -- CPU clock is enabled and the CPU is not stalled.
  signal cpuAddr_r              : rvex_address_type;
  
  -- Same as cpuAddr_r, but for the incoming readEnable signal.
  signal readEnable_r           : std_logic;
  
  -- CPU address input, which remains valid when the CPU is stalled. During a
  -- stall, the CPU address register is muxed to this signal, otherwise the
  -- CPU address is muxed here directly.
  signal cpuAddr                : rvex_address_type;
  
  -- Same as the cpuAddr signal, but for the incoming readEnable signal.
  signal readEnable             : std_logic;
  
  -- Clock gate signal for the data and tag RAM blocks for power saving. This
  -- is pulled low whenever the internal readEnable signal is low or clkEnCPU
  -- is low.
  signal clkEnCPUAndReadEnable  : std_logic;
  
  -- Signals that the CPU tag matches the stored tag at the addressed offset.
  -- Does NOT take the valid bit in consideration, that's what cpuHitValid
  -- does. This is just the tag comparator output.
  signal cpuHit                 : std_logic;
  
  -- Whether the addressed cache line is valid.
  signal cpuValid               : std_logic;
  
  -- Whether the memory addressed by the CPU is valid.
  signal cpuHitValid            : std_logic;
  
  -----------------------------------------------------------------------------
  -- Invalidation network signals
  -----------------------------------------------------------------------------
  -- Signals that the invalidate tag matches the stored tag at the addressed
  -- offset. This signal is valid in the same pipeline stage as invalAddr_r and
  -- invalEnable_r.
  signal invalHit               : std_logic;
  
  -- Invalidate address register. This stores the invalidation request address
  -- while the tag is being compared.
  signal invalAddr_r            : rvex_address_type;
  
  -- Invalidate enable register. This stores the invalidation request enable
  -- while a tag is being compared.
  signal invalEnable_r          : std_logic;
  
  -- When high, signals that the line addressed by invalAddr_r should be
  -- invalidated.
  signal invalidate             : std_logic;
  
  -----------------------------------------------------------------------------
  -- Cache line loading signals
  -----------------------------------------------------------------------------
  -- Active high cache line update signal. When high, the currently addressed
  -- cache line data should be set to updateData, the cache tag must be
  -- updated and the valid bit should be set.
  signal update                 : std_logic;
  
  -- New data for the currently addressed cache line.
  signal updateData             : std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
  
--=============================================================================
begin
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- CPU (pipeline) logic
  -----------------------------------------------------------------------------
  -- Instantiate registers for the incoming readEnable and PC signals. We need
  -- to store these because the CPU is stalled one cycle after the request.
  cpu_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        readEnable_r <= '0';
      elsif clkEnCPU = '1' and route2block_stall = '0' then
        cpuAddr_r <= route2block_PC;
        readEnable_r <= route2block_readEnable;
      end if;
    end if;
  end process;
  
  -- Select either the register or the CPU signal directly based on the stall
  -- signal.
  cpuAddr <= cpuAddr_r when route2block_stall = '1' else route2block_PC;
  readEnable <= readEnable_r when route2block_stall = '1' else route2block_readEnable;
  
  -- Forward the contents of the PC and readEnable registers to the routing
  -- logic one level up.
  block2route_PC_r <= cpuAddr_r;
  block2route_readEnable_r <= readEnable_r;
  
  -- Determine whether the RAM blocks forming the cache need to be enabled or
  -- not.
  clkEnCPUAndReadEnable <= readEnable and clkEnCPU;
  
  -- Compute whether we have a hit and forward it up the hierarchy.
  cpuHitValid <= cpuHit and cpuValid;
  block2route_hit <= cpuHitValid;
  
  -----------------------------------------------------------------------------
  -- Line invalidation (pipeline) logic
  -----------------------------------------------------------------------------
  -- Instantiate registers to store the invalidation request while the tag is
  -- being read and compared.
  inval_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        invalEnable_r <= '0';
      elsif clkEnBus = '1' then
        invalAddr_r <= bus2icache_invalAddr;
        invalEnable_r <= bus2icache_invalEnable;
      end if;
    end if;
  end process;
  
  -- Determine whether the line addressed by invalAddr_r needs to be
  -- invalidated.
  invalidate <= invalEnable_r and invalHit;
  
  -----------------------------------------------------------------------------
  -- Instantiate cache line storage
  -----------------------------------------------------------------------------
  data_ram: entity rvex.cache_instr_blockData
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      enable                    => clkEnCPUAndReadEnable,
      cpuAddr                   => cpuAddr,
      readData                  => block2route_line,
      writeEnable               => update,
      writeData                 => updateData
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate cache tag storage and comparators
  -----------------------------------------------------------------------------
  tag_ram: entity rvex.cache_instr_blockTag
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      enableCPU                 => clkEnCPUAndReadEnable,
      enableBus                 => clkEnBus,
      cpuAddr                   => cpuAddr,
      cpuHit                    => cpuHit,
      writeCpuTag               => update,
      invalAddr                 => bus2icache_invalAddr,
      invalHit                  => invalHit
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate cache line valid bit storage
  -----------------------------------------------------------------------------
  valid_ram: entity rvex.cache_instr_blockValid
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      enableCPU                 => clkEnCPUAndReadEnable,
      enableBus                 => clkEnBus,
      cpuAddr                   => cpuAddr,
      cpuValid                  => cpuValid,
      validate                  => update,
      invalAddr                 => invalAddr_r,
      invalidate                => invalidate,
      flush                     => sc2icache_flush
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the miss resolution controller
  -----------------------------------------------------------------------------
  miss_controller: entity rvex.cache_instr_missCtrl
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      clkEnCPU                  => clkEnCPU,
      clkEnBus                  => clkEnBus,
      stall                     => route2block_stall,
      cpuAddr                   => cpuAddr_r,
      updateEnable              => route2block_updateEnable,
      done                      => update,
      line                      => updateData,
      blockReconfig             => block2route_blockReconfig,
      busFault                  => block2route_busFault,
      cacheToBus                => icache2bus_bus,
      busToCache                => bus2icache_bus
    );
  
end Behavioral;

