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
-- This entity represents a single data cache block.
-------------------------------------------------------------------------------
entity cache_data_block is
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
    -- Requested address.
    route2block_addr            : in rvex_address_type;
    
    -- Registered version of the address being requested.
    block2route_addr_r          : out rvex_address_type;
    
    -- Read enable signal from the lane group, active high.
    route2block_readEnable      : in std_logic;
    
    -- Registered read enable signal from the lane group, active high.
    block2route_readEnable_r    : out std_logic;
    
    -- Data for write accesses.
    route2block_writeData       : in  rvex_data_type;
    
    -- Active high bytemask for writes.
    route2block_writeMask       : in  rvex_mask_type;
    
    -- Write enable signal from the lane group, active high.
    route2block_writeEnable     : in  std_logic;
    
    -- When this signal is high, the block must ignore the command given and
    -- must instead forward it directly to the memory bus.
    route2block_bypass          : in  std_logic;
    
    -- Registered version of the bypass control signal.
    block2route_bypass_r        : out std_logic;
    
    -- Hit output from the cache.
    block2route_hit             : out std_logic;
    
    -- This signal is high when this block should update the currently
    -- requested address. When it is low and there is a miss, the block must
    -- remain idle.
    route2block_updateEnable    : in  std_logic;
    
    -- Write servicing priority output for the associated cache block. The
    -- encoding is as follows when writeEnable was high in the previous cycle.
    --   "11" - already servicing the request (to prevent priority switches
    --          while servicing in progress)
    --   "10" - cache hit
    --   "01" - no cache hit, but write buffer is ready
    --   "00" - no cache hit, write buffer is full
    -- The signal should not be used when no write has been requested.
    block2route_writePrio       : out std_logic_vector(1 downto 0);
    
    -- This signal is high when this cache block must service the currently
    -- requested write.
    route2block_handleWrite     : in  std_logic;
    
    -- Stall output for writes and bypassed memory accesses. The stall signal
    -- for reads is computed at the end of the output network based on
    -- readEnable and not hit. The final stall signal to the lane group is
    -- high when either signal is high.
    block2route_writeOrBypassStall : out std_logic;
    
    -- Combined pipeline stall signal from the lane groups.
    route2block_stall           : in  std_logic;
    
    -- Cache data output, valid when hit and readEnable were high in the
    -- previous cycle.
    block2route_data            : out rvex_data_type;
    
    -- Block reconfiguration signal from the cache. This is asserted when the
    -- block is busy.
    block2route_blockReconfig   : out std_logic;
    
    -- Bus fault output. This is asserted when a bus fault occurs.
    block2route_busFault        : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Bus master interface
    ---------------------------------------------------------------------------
    -- Bus interface for the cache block. The timing of these signals is
    -- governed by clkEnBus. 
    dcache2bus_bus              : out bus_mst2slv_type;
    bus2dcache_bus              : in  bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Bus snooping interface
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Bus address which is to be invalidated when invalEnable is high.
    bus2dcache_invalAddr        : in  rvex_address_type;
    
    -- This signal is high when the cache invalidation is caused by this cache
    -- block. Depending on the situation, this causes the invalidation to be
    -- ignored.
    bus2dcache_invalLoopback    : in  std_logic;
    
    -- Active high enable signal for line invalidation.
    bus2dcache_invalEnable      : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Status and control signals
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Cache flush request signals for each instruction cache block.
    sc2dcache_flush             : in  std_logic;
    
    -- Performance counter/trace status output.
    dcache2rv_status            : out dcache_status_type
    
  );
end cache_data_block;

--=============================================================================
architecture Behavioral of cache_data_block is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- CPU data network signals
  -----------------------------------------------------------------------------
  -- Registers for the CPU memory access commands. These store the command from
  -- the CPU whenever the CPU clock is enabled and the CPU is not stalled.
  -- Thus, these command signals are valid after the first cycle of the
  -- command.
  signal cpuAddr_r            : rvex_address_type;
  signal readEnable_r         : std_logic;
  signal writeData_r          : rvex_data_type;
  signal writeMask_r          : rvex_mask_type;
  signal writeEnable_r        : std_logic;
  signal bypass_r             : std_logic;
  
  -- Memory access command from the CPU. This is kept valid throughout the
  -- entire duration of the command, including the first cycle. In the first
  -- cycle (stall is low) the input from the CPU is selected, in later cycles
  -- (stall is high) the value from the command registers is selected because
  -- the CPU will already have prepared its next command by this time.
  signal cpuAddr              : rvex_address_type;
  signal readEnable           : std_logic;
  signal writeEnable          : std_logic;
  
  -- Clock gate signal for the data and tag RAM blocks for power saving. This
  -- is pulled low whenever the internal readEnable and writeEnable signals are
  -- low or clkEnCPU is low.
  signal clkEnCPUAndAccess    : std_logic;
  
  -- Signals that the CPU tag matches the stored tag at the addressed offset.
  -- Does NOT take the valid bit in consideration, that's what cpuHitValid
  -- does. This is just the tag comparator output.
  signal cpuHit               : std_logic;
  
  -- Whether the addressed cache line is valid.
  signal cpuValid             : std_logic;
  
  -- Whether the memory addressed by the CPU is valid.
  signal cpuHitValid          : std_logic;
  
  -- Performance counter/trace status register.
  signal status_r             : dcache_status_type;
  
  -- This register is set when updateEnable is high and reset when stall is
  -- low, in order to detect whether status_r is valid due to a read miss being
  -- serviced by this block.
  signal readMiss_r           : std_logic;
  
  -- This signal is high when this block is servicing or has serviced a write.
  -- It is reset when stall is low.
  signal servicedWrite        : std_logic;
  
  -- This signal is high when a write is currently buffered.
  signal writeBuffered        : std_logic;
  
  -----------------------------------------------------------------------------
  -- Invalidation network signals
  -----------------------------------------------------------------------------
  -- Signals that the invalidate tag matches the stored tag at the addressed
  -- offset. This signal is valid in the same pipeline stage as invalAddr_r and
  -- invalEnable_r.
  signal invalHit             : std_logic;
  
  -- Invalidate address register. This stores the invalidation request address
  -- while the tag is being compared.
  signal invalAddr_r          : rvex_address_type;
  
  -- Invalidate enable register. This stores the invalidation request enable
  -- while a tag is being compared.
  signal invalEnable_r        : std_logic;
  
  -- When high, signals that the line addressed by invalAddr_r should be
  -- invalidated.
  signal invalidate           : std_logic;
  
  -----------------------------------------------------------------------------
  -- Cache memory signals
  -----------------------------------------------------------------------------
  -- Active high cache line update signal. When high, updateData must be
  -- written to the cache line selected by cpuAddr respecting the byte mask in
  -- updateMask, the cache tag must be updated and the valid bit must be set.
  signal update               : std_logic;
  
  -- New data for the currently addressed cache line.
  signal updateData           : rvex_data_type;
  
  -- Byte mask for writing to the currently addressed cache line.
  signal updateMask           : rvex_mask_type;
  
  -- Cache data output.
  signal cacheReadData        : rvex_data_type;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- CPU (pipeline) logic
  -----------------------------------------------------------------------------
  -- Instantiate registers for the incoming memory access command signals. We
  -- need to store these because the CPU is stalled one cycle after the
  -- request is made.
  cpu_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        readEnable_r  <= '0';
        writeEnable_r <= '0';
        bypass_r      <= '0';
      elsif clkEnCPU = '1' and route2block_stall = '0' then
        cpuAddr_r     <= route2block_addr;
        readEnable_r  <= route2block_readEnable;
        writeData_r   <= route2block_writeData;
        writeMask_r   <= route2block_writeMask;
        writeEnable_r <= route2block_writeEnable;
        bypass_r      <= route2block_bypass;
      end if;
    end if;
  end process;
  
  -- Select either the registers or the combinatorial command signals based on
  -- the stall signal.
  cpuAddr     <= cpuAddr_r     when route2block_stall = '1' else route2block_addr;
  readEnable  <= readEnable_r  when route2block_stall = '1' else route2block_readEnable;
  writeEnable <= writeEnable_r when route2block_stall = '1' else route2block_writeEnable;
  
  -- Forward the contents of the addr, readEnable and bypass registers to the
  -- mux/demux logic. readEnable is used to determine the read stall signal
  -- after merging, addr is used to select which cache block gets to update its
  -- cache when a miss occurs, bypass is used to force the datapath to choose
  -- the highest indexed cache block for the read data.
  block2route_addr_r <= cpuAddr_r;
  block2route_readEnable_r <= readEnable_r;
  block2route_bypass_r <= bypass_r;
  
  -- Determine whether the RAM blocks forming the cache need to be enabled or
  -- not.
  clkEnCPUAndAccess <= (readEnable or writeEnable) and clkEnCPU;
  
  -- Compute whether we have a hit and forward it up the hierarchy.
  cpuHitValid <= cpuHit and cpuValid;
  block2route_hit <= cpuHitValid;
  
  -- Instantiate performance counter/trace status registers.
  status_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        status_r.accessType <= "00";
        status_r.bypass <= '0';
        status_r.miss <= '0';
        status_r.writePending <= '0';
      elsif clkEnCPU = '1' then
        if route2block_stall = '0' then
          status_r.accessType(1) <= route2block_writeEnable;
          if route2block_writeEnable = '1' then
            if route2block_writeMask = "1111" then
              status_r.accessType(0) <= '0';
            else
              status_r.accessType(0) <= '1';
            end if;
          else
            status_r.accessType(0) <= route2block_readEnable;
          end if;
          status_r.bypass <= route2block_bypass;
          status_r.miss <= '0';
          status_r.writePending <= writeBuffered;
          readMiss_r <= '0';
        else
          if cpuHitValid = '0' then
            status_r.miss <= '1';
          end if;
          if route2block_updateEnable = '1' then
            readMiss_r <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Drive the status output signal.
  status_comb: process (
    status_r, readEnable_r, cpuHitValid, readMiss_r, servicedWrite, bypass_r
  ) is
  begin
    dcache2rv_status <= status_r;
    if not (
      ((readEnable_r and cpuHitValid) = '1')  -- Serviced a cached read (hit).
      or (readMiss_r = '1')                   -- Serviced a cached read (miss).
      or (servicedWrite = '1')                -- Serviced a cached write.
      or (bypass_r = '1')                     -- Serviced a bypass read/write.
    ) then
      dcache2rv_status.accessType <= "00";
    end if;
  end process;
  
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
        invalAddr_r <= bus2dcache_invalAddr;
        invalEnable_r <= bus2dcache_invalEnable
          and (bypass_r or not bus2dcache_invalLoopback);
        -- ^- Don't invalidate a cache line when this block initiated the
        --    invalidation by writing to the memory, UNLESS this is a bypass
        --    access. Our cache line is guaranteed to match the memory written
        --    if this is a normal access, so it makes no sense to invalidate it.
      end if;
    end if;
  end process;
  
  -- Determine whether the line addressed by invalAddr_r needs to be
  -- invalidated.
  invalidate <= invalEnable_r and invalHit;
  
  -----------------------------------------------------------------------------
  -- Instantiate cache line storage
  -----------------------------------------------------------------------------
  data_ram: entity rvex.cache_data_blockData
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      enable                    => clkEnCPUAndAccess,
      cpuAddr                   => cpuAddr,
      readData                  => cacheReadData,
      writeEnable               => update,
      writeData                 => updateData,
      writeMask                 => updateMask
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate cache tag storage and comparators
  -----------------------------------------------------------------------------
  tag_ram: entity rvex.cache_data_blockTag
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      enableCPU                 => clkEnCPUAndAccess,
      enableBus                 => clkEnBus,
      cpuAddr                   => cpuAddr,
      cpuHit                    => cpuHit,
      writeCpuTag               => update,
      invalAddr                 => bus2dcache_invalAddr,
      invalHit                  => invalHit
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate cache line valid bit storage
  -----------------------------------------------------------------------------
  valid_ram: entity rvex.cache_data_blockValid
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      enableCPU                 => clkEnCPUAndAccess,
      enableBus                 => clkEnBus,
      cpuAddr                   => cpuAddr,
      cpuValid                  => cpuValid,
      validate                  => update,
      invalAddr                 => invalAddr_r,
      invalidate                => invalidate,
      flush                     => sc2dcache_flush
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the controllers
  -----------------------------------------------------------------------------
  -- This controller handles read misses and CPU writes to cache and the write
  -- buffer.
  main_controller: entity rvex.cache_data_mainCtrl
    generic map (
      RCFG                      => RCFG,
      CCFG                      => CCFG
    )
    port map (
      
      -- System control.
      clk                     => clk,
      reset                   => reset,
      clkEnCPU                => clkEnCPU,
      clkEnBus                => clkEnBus,
      
      -- CPU interface signals.
      addr                    => cpuAddr_r,
      readEnable              => readEnable_r,
      readData                => block2route_data,
      writeEnable             => writeEnable_r,
      writeData               => writeData_r,
      writeMask               => writeMask_r,
      bypass                  => bypass_r,
      stall                   => route2block_stall,
      blockReconfig           => block2route_blockReconfig,
      writeOrBypassStall      => block2route_writeOrBypassStall,
      busFault                => block2route_busFault,
      
      -- Mux control signals.
      updateEnable            => route2block_updateEnable,
      handleWrite             => route2block_handleWrite,
      writePrio               => block2route_writePrio,
      
      -- Cache memory interface signals.
      hit                     => cpuHitValid,
      cacheReadData           => cacheReadData,
      update                  => update,
      updateData              => updateData,
      updateMask              => updateMask,
      
      -- Main memory interface signals.
      cacheToBus              => dcache2bus_bus,
      busToCache              => bus2dcache_bus,
      
      -- Status signals.
      servicedWrite           => servicedWrite,
      writeBuffered           => writeBuffered
      
    );
  
end Behavioral;

