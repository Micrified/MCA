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
-- This entity represents the instruction cache portion of the reconfigurable
-- cache for the rvex.
-------------------------------------------------------------------------------
entity cache_instr is
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
    -- Refer to the entity description in core.vhd for documentation on these
    -- signals. The timing of these signals is governed by clkEnCPU.
    
    -- Common memory interface.
    rv2icache_decouple          : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_blockReconfig     : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_stallIn           : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2icache_stallOut          : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    -- Instruction memory interface.
    rv2icache_PCs               : in  rvex_address_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2icache_fetch             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    rv2icache_cancel            : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_instr             : out rvex_syllable_array(2**RCFG.numLanesLog2-1 downto 0);
    icache2rv_busFault          : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_affinity          : out std_logic_vector(2**RCFG.numLaneGroupsLog2*RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_status_access     : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    icache2rv_status_miss       : out std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus master interface
    ---------------------------------------------------------------------------
    -- Bus interface for the caches. The timing of these signals is governed by
    -- clkEnBus. 
    icache2bus_bus              : out bus_mst2slv_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    bus2icache_bus              : in  bus_slv2mst_array(2**RCFG.numLaneGroupsLog2-1 downto 0);
    
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
    sc2icache_flush             : in  std_logic_vector(2**RCFG.numLaneGroupsLog2-1 downto 0)
    
  );
end cache_instr;

--=============================================================================
architecture Behavioral of cache_instr is
--=============================================================================
  
  -- This record represents an edge between two reconfigurable input merging
  -- nodes.
  type inNetworkEdge_type is record
    
    -- Read enable signal from the lane group, active high.
    readEnable                  : std_logic;
    
    -- Requested address/PC.
    PC                          : rvex_address_type;
    
    -- Cancel signal from the lane group, active high.
    cancel                      : std_logic;
    
    -- This signal is high when the associated cache block must attempt to
    -- update the cache line associated with the PC. This is based on the
    -- hit output of all coupled cache blocks and the registered readEnable:
    -- when readEnable is high and all hit signals are low, one of the cache
    -- blocks in the set will have updateEnable pulled high. The cache block
    -- selected for updating when multiple cache blocks are working together
    -- is based on the PC bits just above the cache index, but could be
    -- determined based on any replacement policy.
    updateEnable                : std_logic;
    
    -- Decouple bit network.
    decouple                    : std_logic;
    
    -- Combined pipeline stall signal from the lane groups.
    stall                       : std_logic;
    
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
    
    -- The stall output for a lane group is equal to readEnable and not hit for
    -- the last level of the output routing network.
    
    -- Registered version of the PC being requested by the lane group if
    -- readEnable was active in the previous cycle. Only the low bits which
    -- index within a cache line are actually used, so the rest will be
    -- optimized away during synthesis, but the rest is also handy for
    -- debugging.
    PC_r                        : rvex_address_type;
    
    -- Cache line data, valid when hit and readEnable are high.
    line                        : std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
    
    -- Block reconfiguration signal from the cache. This is asserted when any
    -- block is busy.
    blockReconfig               : std_logic;
    
    -- Cache affinity signal. This is set to the index of the block which
    -- services the instruction fetch. Its value is only valid while line is
    -- valid.
    affinity                    : std_logic_vector(RCFG.numLaneGroupsLog2-1 downto 0);
    
    -- Bus fault signal. This goes high when a bus fault occured while the
    -- cache line was being validated.
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
    
    -- Read enable signal from the lane group, active high.
    inNetwork(0)(i).readEnable <= rv2icache_fetch(i);
    
    -- Requested address/PC.
    inNetwork(0)(i).PC <= rv2icache_PCs(i);
    
    -- Connect cancel signal.
    inNetwork(0)(i).cancel <= rv2icache_cancel(i);
    
    -- Determine whether the cache must be updated due to a miss.
    inNetwork(0)(i).updateEnable <=
      outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r and not (
        outNetwork(RCFG.numLaneGroupsLog2)(i).hit
        or outNetwork(RCFG.numLaneGroupsLog2)(i).busFault
      );
    
    -- Decouple bit network input.
    inNetwork(0)(i).decouple <= rv2icache_decouple(i);
    
    -- Stall network input.
    inNetwork(0)(i).stall <= rv2icache_stallOut(i);
    
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
            
            -- Hi input is always the master, so ignore the slave inputs and
            -- forward the master inputs to both cache blocks.
            outLo.readEnable  := inHi.readEnable;
            outLo.PC          := inHi.PC;
            
            -- Determine which cache should be updated on a miss based on the
            -- lowest PC bits used for the cache tag. Technically, any
            -- replacement policy may be used here, though. Note that we need
            -- to take this value from the output mux, because updateEnable is
            -- valid one pipelane stage later than the input PC, and the output
            -- mux PC has this attribute.
            if outNetwork(lvl)(to_integer(indLo)).PC_r(icacheTagLSB(RCFG, CCFG) + lvl) = '0' then
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
    
    cache_block_inst: entity rvex.cache_instr_block
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
        route2block_PC            => inNetwork(RCFG.numLaneGroupsLog2)(i).PC,
        block2route_PC_r          => outNetwork(0)(i).PC_r,
        route2block_readEnable    => inNetwork(RCFG.numLaneGroupsLog2)(i).readEnable,
        block2route_readEnable_r  => outNetwork(0)(i).readEnable_r,
        block2route_hit           => outNetwork(0)(i).hit,
        route2block_updateEnable  => inNetwork(RCFG.numLaneGroupsLog2)(i).updateEnable,
        route2block_cancel        => inNetwork(RCFG.numLaneGroupsLog2)(i).cancel,
        route2block_stall         => inNetwork(RCFG.numLaneGroupsLog2)(i).stall,
        block2route_line          => outNetwork(0)(i).line,
        block2route_blockReconfig => outNetwork(0)(i).blockReconfig,
        block2route_busFault      => outNetwork(0)(i).busFault,
        
        -- Bus master interface.
        icache2bus_bus            => icache2bus_bus(i),
        bus2icache_bus            => bus2icache_bus(i),
        
        -- Bus snooping interface.
        bus2icache_invalAddr      => bus2icache_invalAddr,
        bus2icache_invalEnable    => bus2icache_invalEnable,
        
        -- Status and control signals.
        sc2icache_flush           => sc2icache_flush(i)
        
      );
    
  end generate;

  -----------------------------------------------------------------------------
  -- Connect the inputs of the output routing network
  -----------------------------------------------------------------------------
  out_network_input_gen : for i in 0 to 2**RCFG.numLaneGroupsLog2-1 generate
    
    -- Stall network input.
    outNetwork(0)(i).affinity
      <= std_logic_vector(to_unsigned(i, RCFG.numLaneGroupsLog2));
    
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
            
            -- Make both outputs identical and choose their inputs based on
            -- the inLo hit signal.
            if inLo.hit = '1' then
              outHi := inLo;
            else
              outLo := inHi;
            end if;
            
            -- Override the PC output bits related to the offset within the
            -- cache line. Note: if unaligned reads are to become a thing later
            -- on, this needs to become a full blown adder.
            outLo.PC_r(laneGroupInstrSizeBLog2(RCFG, CCFG) + lvl) := '0';
            outHi.PC_r(laneGroupInstrSizeBLog2(RCFG, CCFG) + lvl) := '1';
            
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
    signal miss : std_logic;
  begin
    
    -- Instruction output to the lane group. Valid when stall is low and
    -- readEnable from the highest indexed coupled lane group was high in the
    -- previous cycle.
    process (outNetwork(RCFG.numLaneGroupsLog2)(i)) is
      variable omd                    : outNetworkEdge_type;
      variable offset                 : natural range 0 to 2**RCFG.numLaneGroupsLog2-1;
      constant LANE_GROUP_SIZE_BLOG2  : natural := laneGroupInstrSizeBLog2(RCFG, CCFG);
      constant LANE_GROUP_SIZE_BITS   : natural := 8 * 2**LANE_GROUP_SIZE_BLOG2;
    begin
      
      -- Shorthand for our output signal.
      omd := outNetwork(RCFG.numLaneGroupsLog2)(i);
      
      -- Compute the offset within the cache line based upon the PC.
      offset := to_integer(unsigned(omd.PC_r(
        LANE_GROUP_SIZE_BLOG2 + RCFG.numLaneGroupsLog2 - 1 downto LANE_GROUP_SIZE_BLOG2
      )));
      
      -- VHDL doesn't seem to understand that we're only ever assigning part
      -- of icache2rv_instr each time this process is instantiated by the
      -- generate statement. To get it to stop forcing 'U' on signals from
      -- processes which shouldn't even be assigning the signal, we initialize
      -- with 'Z' instead and let the std_logic resolution function handle it.
      -- Synthesis tools should handle this appropriately too, I would think;
      -- this is very ugly though.
      icache2rv_instr <= (others => (others => 'Z'));
      
      -- Drive the syllable outputs.
      for laneIndex in 0 to 2**(RCFG.numLanesLog2 - RCFG.numLaneGroupsLog2)-1 loop
        icache2rv_instr(group2firstLane(i, RCFG) + laneIndex)
          <= omd.line(
            LANE_GROUP_SIZE_BITS*offset + 32*laneIndex + 31
            downto
            LANE_GROUP_SIZE_BITS*offset + 32*laneIndex
          );
      end loop;
      
    end process;
    
    -- Stall output. If readEnable from the highest indexed coupled lane group
    -- is low, this is always low.
    icache2rv_stallIn(i)
      <= outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r and not (
        outNetwork(RCFG.numLaneGroupsLog2)(i).hit
        or outNetwork(RCFG.numLaneGroupsLog2)(i).busFault
      );
    
    -- Block reconfiguration output. This is asserted when any of the coupled
    -- cache blocks is busy.
    icache2rv_blockReconfig(i)
      <= outNetwork(RCFG.numLaneGroupsLog2)(i).blockReconfig;
    
    -- Affinity output.
    icache2rv_affinity(
      i*RCFG.numLaneGroupsLog2+RCFG.numLaneGroupsLog2-1
      downto i*RCFG.numLaneGroupsLog2
    ) <= outNetwork(RCFG.numLaneGroupsLog2)(i).affinity;
    
    -- Bus fault output.
    icache2rv_busFault(i)
      <= outNetwork(RCFG.numLaneGroupsLog2)(i).busFault;
    
    -- Generate cache miss status register.
    miss_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          miss <= '0';
        elsif clkEnCPU = '1' then
          if rv2icache_stallOut(i) = '0' then
            miss <= '0';
          elsif (
            (outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r = '1')
            and (outNetwork(RCFG.numLaneGroupsLog2)(i).hit = '0')
          ) then
            miss <= '1';
          end if;
        end if;
      end if;
    end process;
    
    -- Drive the miss and access status outputs.
    icache2rv_status_access(i)
      <= outNetwork(RCFG.numLaneGroupsLog2)(i).readEnable_r
      when (
        outNetwork(RCFG.numLaneGroupsLog2)(i).affinity
        = std_logic_vector(to_unsigned(i, RCFG.numLaneGroupsLog2))
      )
      else '0';
    
    icache2rv_status_miss(i)
      <= miss
      when (
        outNetwork(RCFG.numLaneGroupsLog2)(i).affinity
        = std_logic_vector(to_unsigned(i, RCFG.numLaneGroupsLog2))
      )
      else '0';
    
  end generate;
  
end Behavioral;

