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
-- This entity represents the data cache portion of the reconfigurable cache
-- for the rvex.
-- 
-- Write-through behavior, read miss behavior and cache coherency
-- --------------------------------------------------------------
-- The following rules should be followed by the cache implementation in order
-- to ensure cache coherency.
--
--  - When a write is performed and one or more cache blocks have the word in
--    storage, the highest indexed cache block must service the write.
--
--  - When a write is performed while none of the cache blocks have the word
--    in storage, the cache block servicing the write will be the first cache
--    block of which the write buffer is ready for a new command, in order to
--    service the request as soon as possible.
--
--  - When the write buffer is or becomes free for multiple cache blocks at
--    the same time, the highest indexed cache block services the write.
--
--  - When a write is serviced, the cache is updated immediately. If the write
--    is not a full word, the cache is to first behave as if there was a read
--    miss in order to retrieve the remaining data. The CPU must be stalled
--    while this read is in progress to ensure conherency, otherwise another
--    cache block might perform a cache update before the cache update for this
--    block finishes, with the old memory data. The memory write access after
--    that however may be buffered.
--
--  - To ensure that a read following a write returns the new value even when
--    multiple cache blocks have the same memory location in storage, of which
--    one may be invalid due to the memory write/invalidation being buffered,
--    the highest indexed cache with a hit must be used for reads.
--
--  - When a memory write is performed on the bus, beit issued by one of the
--    data caches or an external source, all caches receive an invalidate
--    signal. However, when a data cache issues a memory write, it must ignore
--    its own invalidation signal, as it would be stupid to throw away a cache
--    line which was just updated and is known to be valid.
--
--  - The choice of using the highest-indexed cache when there is otherwise no
--    preference is not arbitrary due to cache consistency during configuration
--    switches. When there is a switch from 2x4 to 1x8 for example, the higher
--    indexed core will continue executing its program, which means that the
--    higher indexed caches must take precedence over the lower ones, as cache
--    coherency between independent cores is more relaxed than within a core.
--
-------------------------------------------------------------------------------
entity cache_data is
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
    rv2dcache_decouple          : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_blockReconfig     : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_stallIn           : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2dcache_stallOut          : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    dcache2rv_status            : out dcache_status_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
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
    dcache2bus_bus              : out bus_mst2slv_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    bus2dcache_bus              : in  bus_slv2mst_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus snooping interface
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Bus address which is to be invalidated when invalEnable is high.
    bus2dcache_invalAddr        : in  rvex_address_type;
    
    -- If one of the data caches is causing the invalidation due to a write,
    -- the signal in this vector indexed by that data cache must be high. In
    -- all other cases, these signals should be low.
    bus2dcache_invalSource      : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high enable signal for line invalidation.
    bus2dcache_invalEnable      : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Status and control signals
    ---------------------------------------------------------------------------
    -- The timing of these signals is governed by clkEnBus.
    
    -- Cache flush request signals for each block.
    sc2dcache_flush             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0)
    
  );
end cache_data;

--=============================================================================
architecture Behavioral of cache_data is
--=============================================================================
  
  -- This record represents an edge between two reconfigurable input merging
  -- nodes.
  type inNetworkEdge_type is record
    
    -- Decouple bit network.
    decouple                    : std_logic;
    
    -- Requested address.
    addr                        : rvex_address_type;
    
    -- Read enable signal from the lane group, active high.
    readEnable                  : std_logic;
    
    -- This signal is high when the associated cache block must attempt to
    -- update the cache line associated with the previous address due to a
    -- read miss. This is based on the hit output of all coupled cache blocks
    -- and the registered readEnable: when readEnable is high and all hit
    -- signals are low, one of the cache blocks in the set will have
    -- updateEnable pulled high. The cache block selected for updating when
    -- multiple cache blocks are working together is based on the address bits
    -- just above the cache index, but could be determined based on any
    -- replacement policy.
    updateEnable                : std_logic;
    
    -- Data for write accesses.
    writeData                   : rvex_data_type;
    
    -- Active high bytemask for writes.
    writeMask                   : rvex_mask_type;
    
    -- Write enable signal from the lane group, active high.
    writeEnable                 : std_logic;
    
    -- When this signal is high, the cache must ignore the command given and
    -- must instead forward it directly to the memory bus. The highest indexed
    -- cache block is always used for bypass accesses.
    bypass                      : std_logic;
    
    -- Combined pipeline stall signal from the lane groups.
    stall                       : std_logic;
    
    -- This signal goes high when multiple lanes within a coupled group try to
    -- make requests at the same time; this is not supported.
    ifaceFault                  : std_logic;
    
  end record;
  
  -- Input routing network array types.
  type inNetworkLevel_type is array (0 to 2**RCFG.numLaneGroupsLog2-1) of inNetworkEdge_type;
  type inNetworkLevels_type is array (0 to RCFG.numLaneGroupsLog2) of inNetworkLevel_type;
  
  -- Input routing network.
  signal inNetwork              : inNetworkLevels_type;
  
  -- This record represents an edge between two reconfigurable output merging
  -- nodes.
  type outNetworkEdge_type is record
    
    -- Registered read enable signal from the lane group, active high.
    readEnable_r                : std_logic;
    
    -- Hit output from the cache.
    hit                         : std_logic;
    
    -- Stall output for writes and bypassed memory accesses. The stall signal
    -- for reads is computed at the end of the output network based on
    -- readEnable and not hit. The final stall signal to the lane group is
    -- high when either signal is high.
    writeOrBypassStall          : std_logic;
    
    -- Block reconfiguration signal from the cache. This is asserted when any
    -- block is busy.
    blockReconfig               : std_logic;
    
    -- Bypass output from the cache. When this is high for the higher indexed
    -- block, the read data should be taken from that block, regardless of
    -- hit state.
    bypass_r                    : std_logic;
    
    -- Write servicing priority output for the associated cache block. The
    -- encoding is as follows when writeEnable was high in the previous cycle.
    --   "11" - already servicing the request (to prevent priority switches
    --          while servicing in progress)
    --   "10" - cache hit
    --   "01" - no cache hit, but write buffer is ready
    --   "00" - no cache hit, write buffer is full
    -- The signal should not be used when no write has been requested.
    writePrio                   : std_logic_vector(1 downto 0);
    
    -- Write servicing select signal, determines which cache block should
    -- service the previously requested write, if there is one. The inputs
    -- for the writeSel network should be set to '1'. At the output of the
    -- network, it is guaranteed that only one writeSel bit is active.
    writeSel                    : std_logic;
    
    -- Registered version of the address being requested by the lane group.
    -- This signal is only used partially by the read miss replacement policy
    -- logic, most of it will be optimized away.
    addr_r                      : rvex_address_type;
    
    -- Cache data output, valid when hit and readEnable were high in the
    -- previous cycle.
    data                        : rvex_data_type;
    
    -- This goes high when a bus fault occurs while reading from the bus or
    -- while writing in bypass mode (writing without bypass mode cannot
    -- generate bus faults at this time because of the write buffer, TODO?).
    busFault                    : std_logic;
    
  end record;
  
  -- Output routing network array types.
  type outNetworkLevel_type is array (0 to 2**RCFG.numLaneGroupsLog2-1) of outNetworkEdge_type;
  type outNetworkLevels_type is array (0 to RCFG.numLaneGroupsLog2) of outNetworkLevel_type;
  
  -- Output routing network signals.
  signal outNetwork             : outNetworkLevels_type;

--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Connect the inputs of the input routing network
  -----------------------------------------------------------------------------
  in_network_input_gen : for i in 0 to 2**RCFG.numLaneGroupsLog2-1 generate
    
    -- Decouple bit network input.
    inNetwork(0)(i).decouple <= rv2dcache_decouple(i);
    
    -- Requested address.
    inNetwork(0)(i).addr <= rv2dcache_addr(i);
    
    -- Read enable signal from the lane group, active high.
    inNetwork(0)(i).readEnable <= rv2dcache_readEnable(i);
    
    -- Determine whether the cache must be updated due to a miss.
    inNetwork(0)(i).updateEnable <=
      outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r
      and not (
        outNetwork(RCFG.numLaneGroupsLog2)(i).hit
        or outNetwork(RCFG.numLaneGroupsLog2)(i).bypass_r
        or outNetwork(RCFG.numLaneGroupsLog2)(i).busFault
        or inNetwork(RCFG.numLaneGroupsLog2)(i).ifaceFault
      );
    
    -- Data for write accesses.
    inNetwork(0)(i).writeData <= rv2dcache_writeData(i);
    
    -- Byte mask for write accesses.
    inNetwork(0)(i).writeMask <= rv2dcache_writeMask(i);
    
    -- Active high write enable signals from the lane groups.
    inNetwork(0)(i).writeEnable <= rv2dcache_writeEnable(i);
    
    -- Active high bypass signals from the lane groups. Only pass this through
    -- when readEnable or writeEnable is high.
    inNetwork(0)(i).bypass
      <= rv2dcache_bypass(i)
      and (rv2dcache_readEnable(i) or rv2dcache_writeEnable(i));
    
    -- Stall network input.
    inNetwork(0)(i).stall <= rv2dcache_stallOut(i);
    
    -- Interfacing fault input.
    inNetwork(0)(i).ifaceFault <= '0';
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate the input routing network
  -----------------------------------------------------------------------------
  in_network_logic_gen : if RCFG.numLaneGroupsLog2 > 0 generate
    -- The code below generates approximately a structure like this when
    -- RCFG.numLaneGroupsLog2 equals 3. Each block represents the for loop
    -- body. The horizontal axis of the signals is specified by lvl, the
    -- vertical index is computed for every i in the loop body. The number
    -- specified in the block is the decouple bit used. When the decouple bit
    -- is high, a block passes its inputs to its outputs unchanged save for the
    -- decouple bit network interconnect. When the decouple bit is low, both
    -- outputs are set to the bottom (hi) input and the updateEnable bit is
    -- and'ed based on the PC bit corrosponding to the level. The lo input
    -- decouple bit is used for the muxing of a stage, whereas the hi output
    -- is forwarded to the outputs in order to connect the indices as shown
    -- below.
    --        ___       ___        ___
    --  ---->| 0 |---->| 1 |----->| 3 |------->
    --       |   |     | __|      | __|
    --  ---->|___|----->| 1 |----->| 3 |------>
    --        ___      ||   |     || __|
    --  ---->| 2 |---->||   | ----->| 3 |----->
    --       |   |      |   |     ||| __|
    --  ---->|___|----->|___|------->| 3 |---->
    --        ___       ___       ||||   |
    --  ---->| 4 |---->| 5 |----->||||   | --->
    --       |   |     | __|       |||   |
    --  ---->|___|----->| 5 |----->|||   | --->
    --        ___      ||   |       ||   |
    --  ---->| 6 |---->||   | ----->||   | --->
    --       |   |      |   |        |   |
    --  ---->|___|----->|___|------->|___|---->
    --
    in_network_logic_gen_b: for lvl in 0 to RCFG.numLaneGroupsLog2 - 1 generate
      in_network_logic: process (inNetwork(lvl), outNetwork(lvl)) is
        variable inLo, inHi       : inNetworkEdge_type;
        variable outLo, outHi     : inNetworkEdge_type;
        variable ind              : unsigned(RCFG.numLaneGroupsLog2-2 downto 0);
        variable indLo, indHi     : unsigned(RCFG.numLaneGroupsLog2-1 downto 0);
      begin
        for i in 0 to (2**RCFG.numLaneGroupsLog2 / 2) - 1 loop
          
          -- Decode i into an unsigned so we can play around with the bits.
          ind := to_unsigned(i, RCFG.numLaneGroupsLog2-1);
          
          -- Determine the lo and hi indices.
          for j in 0 to RCFG.numLaneGroupsLog2 - 1 loop
            if j < lvl then
              indLo(j) := ind(j);
              indHi(j) := ind(j);
            elsif j = lvl then
              indLo(j) := '0';
              indHi(j) := '1';
            else
              indLo(j) := ind(j-1);
              indHi(j) := ind(j-1);
            end if;
          end loop;
          
          -- Read the input signals into variables for shorthand notation.
          inLo := inNetwork(lvl)(to_integer(indLo));
          inHi := inNetwork(lvl)(to_integer(indHi));
          
          -- Passthrough by default.
          outLo := inLo;
          outHi := inHi;
          
          -- Overwrite lo decouple output to hi decouple input to generate the
          -- decouple network.
          outLo.decouple := inHi.decouple;
          
          -- If the lo decouple input is low, perform magic to make cache
          -- blocks work together.
          if inLo.decouple = '0' then
            
            -- Select the request signals from the lane which is making the
            -- request. If both are requesting, assert the ifaceFault signal
            -- and disable both requests.
            if inLo.readEnable = '1' or inLo.writeEnable = '1' then
              outHi.addr        := inLo.addr;
              outHi.readEnable  := inLo.readEnable;
              outHi.writeData   := inLo.writeData;
              outHi.writeMask   := inLo.writeMask;
              outHi.writeEnable := inLo.writeEnable;
              outHi.bypass      := inLo.bypass;
              if inHi.readEnable = '1' or inHi.writeEnable = '1' then
                outHi.readEnable  := '0';
                outHi.writeEnable := '0';
                outHi.ifaceFault  := '1';
                outLo.readEnable  := '0';
                outLo.writeEnable := '0';
                outLo.ifaceFault  := '1';
              end if;
            else
              outLo.addr        := inHi.addr;
              outLo.readEnable  := inHi.readEnable;
              outLo.writeData   := inHi.writeData;
              outLo.writeMask   := inHi.writeMask;
              outLo.writeEnable := inHi.writeEnable;
              outLo.bypass      := inHi.bypass;
            end if;
            
            -- If bypass is active, set the lo output request signals to idle,
            -- so only the highest indexed block will service the bypass
            -- access.
            if inHi.bypass = '1' or inLo.bypass = '1' then
              outLo.readEnable  := '0';
              outLo.writeEnable := '0';
              outLo.bypass      := '0';
            end if;
            
            -- Determine which cache should be updated on a miss based on the
            -- lowest address bits used for the cache tag. Technically, any
            -- replacement policy may be used here, though. Note that we need
            -- to take this value from the output mux, because updateEnable is
            -- valid one pipelane stage later than the input address, and the
            -- output mux address has this attribute.
            if outNetwork(lvl)(to_integer(indLo)).addr_r(dcacheTagLSB(RCFG, CCFG) + lvl) = '0' then
              outLo.updateEnable := inHi.updateEnable;
              outHi.updateEnable := '0';
            else
              outLo.updateEnable := '0';
              outHi.updateEnable := inHi.updateEnable;
            end if;
            
            -- Merge the stall signals when two lane groups are coupled.
            outLo.stall := inLo.stall or inHi.stall;
            outHi.stall := inLo.stall or inHi.stall;
            
          end if;
          
          -- Assign the output signals.
          inNetwork(lvl+1)(to_integer(indLo)) <= outLo;
          inNetwork(lvl+1)(to_integer(indHi)) <= outHi;
          
        end loop; -- i
      end process;
    end generate; -- lvl
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the cache blocks
  -----------------------------------------------------------------------------
  cache_block_gen : for i in 0 to 2**RCFG.numLaneGroupsLog2-1 generate
    
    cache_block_inst : entity rvex.cache_data_block
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
        
        -- Routing interface.
        route2block_addr          => inNetwork(RCFG.numLaneGroupsLog2)(i).addr,
        block2route_addr_r        => outNetwork(0)(i).addr_r,
        route2block_readEnable    => inNetwork(RCFG.numLaneGroupsLog2)(i).readEnable,
        block2route_readEnable_r  => outNetwork(0)(i).readEnable_r,
        route2block_writeData     => inNetwork(RCFG.numLaneGroupsLog2)(i).writeData,
        route2block_writeMask     => inNetwork(RCFG.numLaneGroupsLog2)(i).writeMask,
        route2block_writeEnable   => inNetwork(RCFG.numLaneGroupsLog2)(i).writeEnable,
        route2block_bypass        => inNetwork(RCFG.numLaneGroupsLog2)(i).bypass,
        block2route_bypass_r      => outNetwork(0)(i).bypass_r,
        block2route_hit           => outNetwork(0)(i).hit,
        route2block_updateEnable  => inNetwork(RCFG.numLaneGroupsLog2)(i).updateEnable,
        block2route_writePrio     => outNetwork(0)(i).writePrio,
        route2block_handleWrite   => outNetwork(RCFG.numLaneGroupsLog2)(i).writeSel,
        block2route_writeOrBypassStall => outNetwork(0)(i).writeOrBypassStall,
        route2block_stall         => inNetwork(RCFG.numLaneGroupsLog2)(i).stall,
        block2route_data          => outNetwork(0)(i).data,
        block2route_blockReconfig => outNetwork(0)(i).blockReconfig,
        block2route_busFault      => outNetwork(0)(i).busFault,
        
        -- Bus master interface.
        dcache2bus_bus            => dcache2bus_bus(i),
        bus2dcache_bus            => bus2dcache_bus(i),
        
        -- Bus snooping interface.
        bus2dcache_invalAddr      => bus2dcache_invalAddr,
        bus2dcache_invalLoopback  => bus2dcache_invalSource(i),
        bus2dcache_invalEnable    => bus2dcache_invalEnable,
        
        -- Status and control signals.
        sc2dcache_flush           => sc2dcache_flush(i),
        dcache2rv_status          => dcache2rv_status(i)
        
      );
    
  end generate;

  -----------------------------------------------------------------------------
  -- Connect the inputs of the output routing network
  -----------------------------------------------------------------------------
  out_network_input_gen : for i in 0 to 2**RCFG.numLaneGroupsLog2-1 generate
    
    -- Initialize the writeSel signal.
    outNetwork(0)(i).writeSel <= '1';
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate the output routing network
  -----------------------------------------------------------------------------
  out_network_logic_gen : if RCFG.numLaneGroupsLog2 > 0 generate
  
    -- The code below generates the same structure as the input routing network
    -- code, so you can refer to the ASCII picture there.
    out_network_logic_gen_b : for lvl in 0 to RCFG.numLaneGroupsLog2 - 1 generate
      out_network_logic: process (outNetwork(lvl), inNetwork(lvl)) is
        variable inLo, inHi       : outNetworkEdge_type;
        variable outLo, outHi     : outNetworkEdge_type;
        variable ind              : unsigned(RCFG.numLaneGroupsLog2-2 downto 0);
        variable indLo, indHi     : unsigned(RCFG.numLaneGroupsLog2-1 downto 0);
      begin
        for i in 0 to (2**RCFG.numLaneGroupsLog2 / 2) - 1 loop
          
          -- Decode i into an unsigned so we can play around with the bits.
          ind := to_unsigned(i, RCFG.numLaneGroupsLog2-1);
          
          -- Determine the lo and hi indices.
          for j in 0 to RCFG.numLaneGroupsLog2 - 1 loop
            if j < lvl then
              indLo(j) := ind(j);
              indHi(j) := ind(j);
            elsif j = lvl then
              indLo(j) := '0';
              indHi(j) := '1';
            else
              indLo(j) := ind(j-1);
              indHi(j) := ind(j-1);
            end if;
          end loop;
          
          -- Read the input signals into variables for shorthand notation.
          inLo := outNetwork(lvl)(to_integer(indLo));
          inHi := outNetwork(lvl)(to_integer(indHi));
          
          -- Passthrough by default.
          outLo := inLo;
          outHi := inHi;
          
          -- If the input network lo decouple input is low, perform magic
          -- to make cache blocks work together. Note the lack of a register
          -- here even though we're crossing a pipeline stage. This should not
          -- be necessary due to the preconditions placed on the decouple
          -- inputs: in all cases when a decouple signal switches, behavior
          -- is unaffected due to all readEnables and stalls being low.
          if inNetwork(lvl)(to_integer(indLo)).decouple = '0' then
            
            -- For the read data and control pipeline, make both outputs
            -- identical and choose their inputs based on the inHi hit signal.
            -- When a bypass index is going on, we always want to use the data
            -- from the higher indexed block.
            if inHi.hit = '1' or inHi.bypass_r = '1' then
              outLo := inHi;
            else
              outHi := inLo;
            end if;
            
            -- For the write control signals we select based on which has the
            -- higher priority. When the priorities are equal, choose the
            -- higher indexed cache block as per the cache coherence rules.
            if unsigned(inHi.writePrio) >= unsigned(inLo.writePrio) then
              outLo.writePrio := inHi.writePrio;
              outLo.writeSel  := '0';
              outHi.writePrio := inHi.writePrio;
              outHi.writeSel  := inHi.writeSel;
            else
              outLo.writePrio := inLo.writePrio;
              outLo.writeSel  := inLo.writeSel;
              outHi.writePrio := inLo.writePrio;
              outHi.writeSel  := '0';
            end if;
            
            -- Merge the stall signals.
            outLo.writeOrBypassStall := inLo.writeOrBypassStall or inHi.writeOrBypassStall;
            outHi.writeOrBypassStall := inLo.writeOrBypassStall or inHi.writeOrBypassStall;
            
            -- Merge the blockReconfig signals.
            outLo.blockReconfig := inLo.blockReconfig or inHi.blockReconfig;
            outHi.blockReconfig := inLo.blockReconfig or inHi.blockReconfig;
            
            -- Merge the bus fault signals.
            outLo.busFault := inLo.busFault or inHi.busFault;
            outHi.busFault := inLo.busFault or inHi.busFault;
            
          end if;
          
          -- Assign the output signals.
          outNetwork(lvl+1)(to_integer(indLo)) <= outLo;
          outNetwork(lvl+1)(to_integer(indHi)) <= outHi;
          
        end loop; -- i
      end process;
    end generate; -- lvl
  end generate;
  
  -----------------------------------------------------------------------------
  -- Connect the outputs from the output network to the lane groups
  -----------------------------------------------------------------------------
  out_network_output_gen : for i in 0 to 2**RCFG.numLaneGroupsLog2-1 generate
    
    -- Read data output to the lane group. Valid when stall is low and
    -- readEnable from the highest indexed coupled lane group was high in the
    -- previous cycle.
    dcache2rv_readData(i) <=
      outNetwork(RCFG.numLaneGroupsLog2)(i).data;
    
    -- Stall output.
    dcache2rv_stallIn(i) <=
      
      -- Normal operation...
      (
        
        -- Stall due to read miss.
        (outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r
          and not outNetwork(RCFG.numLaneGroupsLog2)(i).hit
          and not outNetwork(RCFG.numLaneGroupsLog2)(i).bypass_r)
        
        -- Write stall (either due to a miss for a sub-word write or due to the
        -- write buffer being full).
        or outNetwork(RCFG.numLaneGroupsLog2)(i).writeOrBypassStall
       
      -- Faults.
      ) and not (
        outNetwork(RCFG.numLaneGroupsLog2)(i).busFault
        or inNetwork(RCFG.numLaneGroupsLog2)(i).ifaceFault
      );
    
    -- Block reconfiguration output. This is asserted when any of the coupled
    -- cache blocks are busy.
    dcache2rv_blockReconfig(i) <=
      outNetwork(RCFG.numLaneGroupsLog2)(i).blockReconfig;
    
    -- Bus fault output.
    dcache2rv_busFault(i) <=
      outNetwork(RCFG.numLaneGroupsLog2)(i).busFault;
    
  end generate;
  
  -- The interfacing fault output needs to be delayed by one CPU cycle,
  -- because it is generated based on the request from the CPU instead of a
  -- bus result.
  iface_fault_reg: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        dcache2rv_ifaceFault <= (others => '0');
      elsif clkEnCPU = '1' then
        for i in 0 to 2**RCFG.numLaneGroupsLog2-1 loop
          if inNetwork(RCFG.numLaneGroupsLog2)(i).stall = '0' then
            dcache2rv_ifaceFault(i)
              <= inNetwork(RCFG.numLaneGroupsLog2)(i).ifaceFault
              and (rv2dcache_readEnable(i) or rv2dcache_writeEnable(i));
          end if;
        end loop;
      end if;
    end if;
    
  end process;
  
end Behavioral;

