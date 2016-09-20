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
use IEEE.math_real.all;

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;
use rvex.core_pkg.all;
use rvex.core_ctrlRegs_pkg.all;
use rvex.rvsys_standalone_pkg.all;

--=============================================================================
-- This unit wraps the rvex core and L1 cache.
-------------------------------------------------------------------------------
entity rvsys_standalone_cachedCore is
--=============================================================================
  generic (
    
    -- Standalone system configuration.
    CFG                         : rvex_sa_generic_config_type;
    
    -- This is used as the core index register in the global control registers.
    CORE_ID                     : natural := 0;
    
    -- Platform version tag. This is put in the global control registers of the
    -- processor.
    PLATFORM_TAG                : std_logic_vector(55 downto 0) := (others => '0');
    
    -- Register consistency check configuration (see core.vhd).
    RCC_RECORD                  : string := "";
    RCC_CHECK                   : string := "";
    RCC_CTXT                    : natural := 0
    
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
    
    -- Active high break output. This is asserted when the core is waiting for
    -- an externally handled breakpoint, or the B flag in DCR is otherwise set.
    rvsa2rctrl_break            : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    -- Active high trace stall output. This can be used to stall other cores
    -- and timers simultaneously in order to be able to trace more accurately.
    rvsa2rctrl_traceStall       : out std_logic;
    
    -- Trace stall input. This just stalls all lane groups when asserted.
    rctrl2rvsa_traceStall       : in  std_logic := '0';
    
    -- Active high context reset input. When high, the context control
    -- registers (including PC, done and break flag) will be reset.
    rctrl2rvsa_reset            : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '0');
    
    -- Reset vector. When the context or the entire core is reset, the PC
    -- register will be set to this value.
    rctrl2rvsa_resetVect        : in  rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0) := CFG.core.resetVectors(2**CFG.core.numContextsLog2-1 downto 0);
    
    -- Active high done output. This is asserted when the context encounters
    -- a stop syllable. Processing a stop signal also sets the BRK control
    -- register, which stops the core. This bit can be reset by issuing a core
    -- reset or by means of the debug interface.
    rvsa2rctrl_done             : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Bus interfaces
    ---------------------------------------------------------------------------
    -- Memory bus for the cache.
    rv2mem                      : out bus_mst2slv_type;
    mem2rv                      : in  bus_slv2mst_type;
    
    -- Debug bus. This is connected straight to the rvex, but there are a
    -- couple write-only things added to the CR_AFF register (which is read
    -- only in the core so there's no conflicts):
    --
    --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
    -- AFF(w)|    Latency    |               |  Data flush   | Instr. flush  |
    --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
    --
    -- Latency: sets simulated memory bus latency. 0 and 255 are not supported;
    -- for all other values latency+1 busy cycles are injected to the bus
    -- accesses made by the cache.
    -- 
    -- Data flush: each bit corresponds to its own data cache block; writing a
    -- one to it causes that block to be flushed. There may be less than 8
    -- blocks (based on configuration), in which case the MSBs are not
    -- connected.
    -- 
    -- Instr. flush: same as data flush, but for the instruction memory blocks.
    --
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
end rvsys_standalone_cachedCore;

--=============================================================================
architecture Behavioral of rvsys_standalone_cachedCore is
--=============================================================================
  
  -- Core common memory interface <-> cache.
  signal rv2cache_decouple      : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_blockReconfig : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_stallIn       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2cache_stallOut      : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_status        : rvex_cacheStatus_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Core instruction memory interface <-> cache.
  signal rv2icache_PCs          : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2icache_fetch        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2icache_cancel       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_instr        : rvex_syllable_array(2**CFG.core.numLanesLog2-1 downto 0);
  signal icache2rv_affinity     : std_logic_vector(2**CFG.core.numLaneGroupsLog2*CFG.core.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_busFault     : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Core data memory interface <-> cache.
  signal rv2dcache_addr         : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_readEnable   : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeData    : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeMask    : rvex_mask_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeEnable  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_bypass       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_readData     : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_ifaceFault   : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_busFault     : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Cache to bus interface, before the arbiter.
  signal cache2bus_bus          : bus_mst2slv_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal bus2cache_bus          : bus_slv2mst_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Cache to bus interface, after the arbiter.
  signal cache2bus_arb          : bus_mst2slv_type;
  signal bus2cache_arb          : bus_slv2mst_type;
  
  -- Index of the cache block making the current request on cache2bus_arb.
  signal arb_source             : rvex_data_type;
  
  -- Bus snooping interface.
  signal bus2cache_invalAddr    : rvex_address_type;
  signal bus2cache_invalSource  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal bus2cache_invalEnable  : std_logic;
  
  -- Cache flush control signal.
  signal sc2dcache_flush        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal sc2icache_flush        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Control/debug bus interface.
  signal dbg2rv_addr            : rvex_address_type;
  signal dbg2rv_readEnable      : std_logic;
  signal dbg2rv_writeEnable     : std_logic;
  signal dbg2rv_writeMask       : rvex_mask_type;
  signal dbg2rv_writeData       : rvex_data_type;
  signal rv2dbg_readData        : rvex_data_type;
  signal rv2dgb_ack             : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Check configuration.
  assert CFG.cache_enable
    report "rvsys_standalone_cachedCore instantiated without cache_enable set; "
         & "this is illegal. Use rvsys_standalone_core instead."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Instantiate the rvex core
  -----------------------------------------------------------------------------
  core: entity rvex.core
    generic map (
      CFG                       => CFG.core,
      CORE_ID                   => CORE_ID,
      PLATFORM_TAG              => PLATFORM_TAG,
      RCC_RECORD                => RCC_RECORD,
      RCC_CHECK                 => RCC_CHECK,
      RCC_CTXT                  => RCC_CTXT
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- Run control interface.
      rctrl2rv_irq              => rctrl2rvsa_irq,
      rctrl2rv_irqID            => rctrl2rvsa_irqID,
      rv2rctrl_irqAck           => rvsa2rctrl_irqAck,
      rctrl2rv_run              => rctrl2rvsa_run,
      rv2rctrl_idle             => rvsa2rctrl_idle,
      rv2rctrl_break            => rvsa2rctrl_break,
      rv2rctrl_traceStall       => rvsa2rctrl_traceStall,
      rctrl2rv_traceStall       => rctrl2rvsa_traceStall,
      rctrl2rv_reset            => rctrl2rvsa_reset,
      rctrl2rv_resetVect        => rctrl2rvsa_resetVect,
      rv2rctrl_done             => rvsa2rctrl_done,
      
      -- Common memory interface.
      rv2mem_decouple           => rv2cache_decouple,
      mem2rv_blockReconfig      => cache2rv_blockReconfig,
      mem2rv_stallIn            => cache2rv_stallIn,
      rv2mem_stallOut           => rv2cache_stallOut,
      mem2rv_cacheStatus        => cache2rv_status,
      
      -- Instruction memory interface.
      rv2imem_PCs               => rv2icache_PCs,
      rv2imem_fetch             => rv2icache_fetch,
      rv2imem_cancel            => rv2icache_cancel,
      imem2rv_instr             => icache2rv_instr,
      imem2rv_affinity          => icache2rv_affinity,
      imem2rv_busFault          => icache2rv_busFault,
      
      -- Data memory interface.
      rv2dmem_addr              => rv2dcache_addr,
      rv2dmem_readEnable        => rv2dcache_readEnable,
      rv2dmem_writeData         => rv2dcache_writeData,
      rv2dmem_writeMask         => rv2dcache_writeMask,
      rv2dmem_writeEnable       => rv2dcache_writeEnable,
      dmem2rv_readData          => dcache2rv_readData,
      dmem2rv_busFault          => dcache2rv_busFault,
      dmem2rv_ifaceFault        => dcache2rv_ifaceFault,
      
      -- Control/debug bus interface.
      dbg2rv_addr               => dbg2rv_addr,
      dbg2rv_readEnable         => dbg2rv_readEnable,
      dbg2rv_writeEnable        => dbg2rv_writeEnable,
      dbg2rv_writeMask          => dbg2rv_writeMask,
      dbg2rv_writeData          => dbg2rv_writeData,
      rv2dbg_readData           => rv2dbg_readData,
      
      -- Trace interface.
      rv2trsink_push            => rv2trsink_push,
      rv2trsink_data            => rv2trsink_data,
      rv2trsink_end             => rv2trsink_end,
      trsink2rv_busy            => trsink2rv_busy
      
    );
  
  -- Generate the bypass signal.
  bypass_gen: for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 generate
    
    rv2dcache_bypass(laneGroup) <= '1'
      when isAddrInRange(rv2dcache_addr(laneGroup), CFG.cache_bypassRange)
      else '0';
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the cache
  -----------------------------------------------------------------------------
  cache: entity rvex.cache
    generic map (
      RCFG                      => CFG.core,
      CCFG                      => CFG.cache_config
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEnCPU                  => clkEn,
      clkEnBus                  => clkEn,
      
      -- Common memory interface.
      rv2cache_decouple         => rv2cache_decouple,
      cache2rv_blockReconfig    => cache2rv_blockReconfig,
      cache2rv_stallIn          => cache2rv_stallIn,
      rv2cache_stallOut         => rv2cache_stallOut,
      cache2rv_status           => cache2rv_status,
      
      -- Instruction memory interface.
      rv2icache_PCs             => rv2icache_PCs,
      rv2icache_fetch           => rv2icache_fetch,
      rv2icache_cancel          => rv2icache_cancel,
      icache2rv_instr           => icache2rv_instr,
      icache2rv_affinity        => icache2rv_affinity,
      icache2rv_busFault        => icache2rv_busFault,
      
      -- Data memory interface.
      rv2dcache_addr            => rv2dcache_addr,
      rv2dcache_readEnable      => rv2dcache_readEnable,
      rv2dcache_writeData       => rv2dcache_writeData,
      rv2dcache_writeMask       => rv2dcache_writeMask,
      rv2dcache_writeEnable     => rv2dcache_writeEnable,
      rv2dcache_bypass          => rv2dcache_bypass,
      dcache2rv_readData        => dcache2rv_readData,
      dcache2rv_ifaceFault      => dcache2rv_ifaceFault,
      dcache2rv_busFault        => dcache2rv_busFault,
      
      -- Bus master interface.
      cache2bus_bus             => cache2bus_bus,
      bus2cache_bus             => bus2cache_bus,
      
      -- Bus snooping interface.
      bus2cache_invalAddr       => bus2cache_invalAddr,
      bus2cache_invalSource     => bus2cache_invalSource,
      bus2cache_invalEnable     => bus2cache_invalEnable,
      
      -- Status and control signals.
      sc2icache_flush           => sc2icache_flush,
      sc2dcache_flush           => sc2dcache_flush
      
    );
  
  -- Snoop the debug bus to generate the cache flush signals.
  sc2icache_flush <= dbg2rv_writeData(2**CFG.core.numLaneGroupsLog2-1 downto 0)
    when (dbg2rv_addr(7 downto 2) = uint2vect(CR_AFF, 6))
    and  (dbg2rv_writeEnable = '1')
    and  (dbg2rv_writeMask(0) = '1')
    else (others => '0');
  
  sc2dcache_flush <= dbg2rv_writeData(2**CFG.core.numLaneGroupsLog2+7 downto 8)
    when (dbg2rv_addr(7 downto 2) = uint2vect(CR_AFF, 6))
    and  (dbg2rv_writeEnable = '1')
    and  (dbg2rv_writeMask(1) = '1')
    else (others => '0');
  
  -----------------------------------------------------------------------------
  -- Arbitrate between the four busses coming from the cache.
  -----------------------------------------------------------------------------
  cache_arbiter: entity rvex.bus_arbiter
    generic map (
      NUM_MASTERS               => 2**CFG.core.numLaneGroupsLog2
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- Master busses.
      mst2arb                   => cache2bus_bus,
      arb2mst                   => bus2cache_bus,
      
      -- Slave bus.
      arb2slv                   => cache2bus_arb,
      slv2arb                   => bus2cache_arb,
      
      -- Index of the master which is making the current bus request.
      arb2slv_source            => arb_source
      
    );
  
  -----------------------------------------------------------------------------
  -- Generate line invalidation signals
  -----------------------------------------------------------------------------
  -- Connect address end enable trivially.
  bus2cache_invalAddr   <= cache2bus_arb.address;
  bus2cache_invalEnable <= cache2bus_arb.writeEnable;
  
  -- Decode arb2slv_source to get the bus2cache_invalSource signal.
  inval_source_proc: process (arb_source) is
  begin
    bus2cache_invalSource <= (others => '0');
    for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 loop
      if vect2uint(arb_source) = laneGroup then
        bus2cache_invalSource(laneGroup) <= '1';
      end if;
    end loop;
  end process;
  
  -----------------------------------------------------------------------------
  -- Connect the memory bus
  -----------------------------------------------------------------------------
  -- This block artificially delays bus requests to simulate a high-latency
  -- memory environment for the cache.
  bus_latency_extend_block: if CFG.inject_latency generate
    
    -- State register. The actual bus requests are made in state 0, the rest of
    -- the states are just used to lengthen the ack based on the latency
    -- register.
    signal state          : unsigned(7 downto 0);
    signal state_next     : unsigned(7 downto 0);
    
    -- Determines the amount of busy cycles injected into bus requests. The
    -- encoding is as follows:
    --     0 => 255 cycles
    --     1 =>   2 cycles
    --     2 =>   3 cycles
    --   ... => ... cycles
    --   254 => 255 cycles
    --   255 => 255 cycles
    -- It defaults to 64 => 65 cycles.
    signal latency        : unsigned(7 downto 0);
    signal latency_next   : unsigned(7 downto 0);
    signal readData       : rvex_data_type;
    signal readData_next  : rvex_data_type;
    signal ack            : std_logic;
    signal ack_next       : std_logic;
    
  begin
    
    -- Instantiate registers.
    bus_latency_extend_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          state     <= X"00";
          latency   <= X"40";
          readData  <= (others => '0');
          ack       <= '0';
        elsif clkEn = '1' then
          state     <= state_next;
          latency   <= latency_next;
          readData  <= readData_next;
          ack       <= ack_next;
        end if;
      end if;
    end process;
    
    -- Instantiate the combinatorial logic for the latency-injection state
    -- machine.
    bus_latency_extend_proc: process (
      state, latency, readData, ack, cache2bus_arb, mem2rv
    ) is
    begin
      
      -- Set default values.
      rv2mem                  <= BUS_MST2SLV_IDLE;
      bus2cache_arb           <= BUS_SLV2MST_IDLE;
      bus2cache_arb.busy      <= '1';
      bus2cache_arb.ack       <= ack;
      bus2cache_arb.readData  <= readData;
      state_next              <= state;
      readData_next           <= readData;
      ack_next                <= '0';
      
      -- Handle the states.
      case state is
        
        when X"00" => 
          
          if mem2rv.ack = '0' then
            
            -- Forward request and busy signals.
            rv2mem <= cache2bus_arb;
            bus2cache_arb.busy <= mem2rv.busy;
            
          else
            
            -- Go to the next state when the bus acknowledges and register the
            -- result.
            readData_next <= mem2rv.readData;
            state_next <= X"01";
            
          end if;
          
        when X"FF" =>
          
          -- Acknowledge the request in the next cycle.
          ack_next <= '1';
          state_next <= X"00";
          
        when others =>
          
          -- Jump to the last state when the state reaches the latency
          -- register, otherwise just increment.
          if state = latency then
            state_next <= X"FF";
          else
            state_next <= state + 1;
          end if;
          
      end case;
      
    end process;
    
    -- Connect the latency register input to the debug bus.
    latency_next <= unsigned(dbg2rv_writeData(31 downto 24))
      when (dbg2rv_addr(7 downto 2) = uint2vect(CR_AFF, 6))
      and  (dbg2rv_writeEnable = '1')
      and  (dbg2rv_writeMask(3) = '1')
      else latency;
    
  end generate;
  
  -- If latency injection is disabled, connect the external bus directly to the
  -- arbiter master bus.
  no_latency_block: if not CFG.inject_latency generate
  begin
    rv2mem <= cache2bus_arb;
    bus2cache_arb <= mem2rv;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Connect the debug bus trivially
  -----------------------------------------------------------------------------
  dbg2rv_addr         <= dbg2rv.address;
  dbg2rv_readEnable   <= dbg2rv.readEnable;
  dbg2rv_writeEnable  <= dbg2rv.writeEnable;
  dbg2rv_writeMask    <= dbg2rv.writeMask;
  dbg2rv_writeData    <= dbg2rv.writeData;
  rv2dbg.readData     <= rv2dbg_readData;
  rv2dbg.fault        <= '0';
  rv2dbg.busy         <= '0';
  rv2dbg.ack          <= rv2dgb_ack;
  
  debug_bus_ack: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rv2dgb_ack <= '0';
      elsif clkEn = '1' then
        rv2dgb_ack <= bus_requesting(dbg2rv);
      end if;
    end if;
  end process;
  
  
end Behavioral;

