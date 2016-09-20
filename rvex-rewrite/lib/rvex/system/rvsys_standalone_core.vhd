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
use rvex.core_pkg.all;
use rvex.rvsys_standalone_pkg.all;

--=============================================================================
-- This unit wraps the rvex core, bridging between the raw data/instruction
-- I/O ports and a number of busses as specified in bus_pkg.vhd.
-------------------------------------------------------------------------------
entity rvsys_standalone_core is
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
end rvsys_standalone_core;

--=============================================================================
architecture Behavioral of rvsys_standalone_core is
--=============================================================================
  
  -- Common memory interface.
  signal rv2mem_decouple        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal mem2rv_stallIn         : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2mem_stallOut        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Instruction memory interface.
  signal rv2imem_PCs            : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2imem_fetch          : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal imem2rv_instr          : rvex_syllable_array(2**CFG.core.numLanesLog2-1 downto 0);
  signal imem2rv_fault          : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Fault signals from each instruction memory bus, before being merged for
  -- each group.
  signal imemFault              : std_logic_vector(2**CFG.core.numLanesLog2-1 downto 0);
  
  -- Data memory interface.
  signal rv2dmem_addr           : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dmem_writeEnable    : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dmem_writeMask      : rvex_mask_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dmem_writeData      : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dmem_readEnable     : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dmem2rv_readData       : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dmem2rv_fault          : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
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
  assert not CFG.cache_enable
    report "rvsys_standalone_core instantiated with cache_enable set; this is "
         & "illegal. Use rvsys_standalone_cachedCore instead."
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
      rv2mem_decouple           => rv2mem_decouple,
      mem2rv_stallIn            => mem2rv_stallIn,
      rv2mem_stallOut           => rv2mem_stallOut,
      
      -- Instruction memory interface.
      rv2imem_PCs               => rv2imem_PCs,
      rv2imem_fetch             => rv2imem_fetch,
      imem2rv_instr             => imem2rv_instr,
      imem2rv_busFault          => imem2rv_fault,
      
      -- Data memory interface.
      rv2dmem_addr              => rv2dmem_addr,
      rv2dmem_writeEnable       => rv2dmem_writeEnable,
      rv2dmem_writeMask         => rv2dmem_writeMask,
      rv2dmem_writeData         => rv2dmem_writeData,
      rv2dmem_readEnable        => rv2dmem_readEnable,
      dmem2rv_readData          => dmem2rv_readData,
      dmem2rv_busFault          => dmem2rv_fault,
      
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
  
  -----------------------------------------------------------------------------
  -- Generate the stall signals
  -----------------------------------------------------------------------------
  gen_stall: process (imem2rv, dmem2rv, rv2mem_decouple) is
    variable stall  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  begin
    
    -- Don't stall by default.
    stall := (others => '0');
    
    -- Assert the appropriate stall signals while any of the instruction
    -- memory busses is busy.
    for lane in 0 to 2**CFG.core.numLanesLog2-1 loop
      stall(lane2group(lane, CFG.core))
        := stall(lane2group(lane, CFG.core)) or imem2rv(lane).busy;
    end loop;
    
    -- Same for the data memory busses.
    for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 loop
      stall(laneGroup)
        := stall(laneGroup) or dmem2rv(laneGroup).busy;
    end loop;
    
    -- Merge the stall signals when lane groups are coupled.
    for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-2 loop
      if rv2mem_decouple(laneGroup) = '0' then
        stall(laneGroup+1) := stall(laneGroup+1) or stall(laneGroup);
      end if;
    end loop;
    
    -- Output the stall signals.
    mem2rv_stallIn <= stall;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Connect the instruction memory busses
  -----------------------------------------------------------------------------
  -- We cannot just connect the bus signals directly to the raw signals from
  -- the rvex core for the following reasons:
  --  - When the core is stalled by the busy signals, it will already be
  --    providing the signals for the next request, so we need to register the
  --    request signals.
  --  - The result is only valid while ack is high, but the core might still
  --    be waiting for other busses before it resumes. Therefore, we need to
  --    register the result as well.
  --  - We must ensure that the bus request is no-op when the core is waiting
  --    for other busses, or the request will be processed again.
  imem_bus_connect_gen: for lane in 0 to 2**CFG.core.numLanesLog2-1 generate
    
    -- Bus request for the instruction fetch for this lane.
    signal combinatorialRequest : bus_mst2slv_type;
    
    -- Registered bus request.
    signal registeredRequest    : bus_mst2slv_type;
    
    -- Holding registers for the bus result, for when the core is stalled
    -- longer than our bus took to process the request.
    signal readData_r           : rvex_data_type;
    signal fault_r              : std_logic;
    
  begin
    
    -- Generate the bus request.
    imem_bus_request_proc: process (rv2imem_PCs, rv2imem_fetch) is
      variable req  : bus_mst2slv_type;
    begin
      
      -- Load the trivial values.
      req := BUS_MST2SLV_IDLE;
      req.address := rv2imem_PCs(lane2group(lane, CFG.core));
      req.readEnable := rv2imem_fetch(lane2group(lane, CFG.core));
      
      -- Update the LSBs of the address to match the lane index.
      req.address(2+(CFG.core.numLanesLog2-CFG.core.numLaneGroupsLog2)-1 downto 2)
        := uint2vect(lane2indexInGroup(lane, CFG.core), CFG.core.numLanesLog2-CFG.core.numLaneGroupsLog2);
      
      -- Drive the output signal.
      combinatorialRequest <= req;
      
    end process;
    
    -- Generate the register for the bus request.
    imem_bus_request_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          registeredRequest <= BUS_MST2SLV_IDLE;
        elsif rv2mem_stallOut(lane2group(lane, CFG.core)) = '0' and clkEn = '1' then
          registeredRequest <= combinatorialRequest;
        end if;
      end if;
    end process;
    
    -- Select between the requests. Select the combinatorial request when stall
    -- is low so the busses can immediately start processing the next request,
    -- then switch to the registered request when any of the busses is busy
    -- (i.e. stall is high). When our bus is done but the processor is still
    -- stalled, gate the request so the request is not made again.
    rv2imem(lane)
      <= combinatorialRequest when rv2mem_stallOut(lane2group(lane, CFG.core)) = '0'
      else bus_gate(registeredRequest, imem2rv(lane).busy);
    
    -- Register the bus result when ack is high.
    imem_bus_result_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          readData_r  <= (others => '0');
          fault_r     <= '0';
        elsif imem2rv(lane).ack = '1' and clkEn = '1' then
          readData_r  <= imem2rv(lane).readData;
          fault_r     <= imem2rv(lane).fault;
        end if;
      end if;
    end process;
    
    -- Select between combinatorial and registered result based on the ack
    -- signal.
    imem2rv_instr(lane)
      <=   X"00000000"            when imem2rv_fault(lane2group(lane, CFG.core)) = '1'
      else imem2rv(lane).readData when imem2rv(lane).ack = '1'
      else readData_r;
    
    imemFault(lane)
      <=   imem2rv(lane).fault    when imem2rv(lane).ack = '1'
      else fault_r;
    
  end generate;
  
  -- Combine the fault signals from the lanes within each group.
  process (imemFault) is
    variable f  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  begin
    f := (others => '0');
    for lane in 0 to 2**CFG.core.numLanesLog2-1 loop
      f(lane2group(lane, CFG.core)) := f(lane2group(lane, CFG.core)) or imemFault(lane);
    end loop;
    imem2rv_fault <= f;
  end process;
  
  -----------------------------------------------------------------------------
  -- Connect the data memory busses
  -----------------------------------------------------------------------------
  -- We cannot just connect the bus signals directly to the raw signals from
  -- the rvex core for the following reasons:
  --  - When the core is stalled by the busy signals, it will already be
  --    providing the signals for the next request, so we need to register the
  --    request signals.
  --  - The result is only valid while ack is high, but the core might still
  --    be waiting for other busses before it resumes. Therefore, we need to
  --    register the result as well.
  --  - We must ensure that the bus request is no-op when the core is waiting
  --    for other busses, or the request will be processed again.
  dmem_bus_connect_gen: for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 generate
    
    -- Bus request for the instruction fetch for this lane.
    signal combinatorialRequest : bus_mst2slv_type;
    
    -- Registered bus request.
    signal registeredRequest    : bus_mst2slv_type;
    
    -- Holding registers for the bus result, for when the core is stalled
    -- longer than our bus took to process the request.
    signal readData_r           : rvex_data_type;
    signal fault_r              : std_logic;
    
  begin
    
    -- Generate the bus request.
    dmem_bus_request_proc: process (
      rv2imem_PCs, rv2imem_fetch, rv2dmem_addr, rv2dmem_readEnable,
      rv2dmem_writeEnable, rv2dmem_writeMask, rv2dmem_writeData
    ) is
      variable req  : bus_mst2slv_type;
    begin
      
      -- Load the requests.
      req := BUS_MST2SLV_IDLE;
      req.address     := rv2dmem_addr(laneGroup);
      req.readEnable  := rv2dmem_readEnable(laneGroup);
      req.writeEnable := rv2dmem_writeEnable(laneGroup);
      req.writeMask   := rv2dmem_writeMask(laneGroup);
      req.writeData   := rv2dmem_writeData(laneGroup);
      
      -- Drive the output signal.
      combinatorialRequest <= req;
      
    end process;
    
    -- Generate the register for the bus request.
    dmem_bus_request_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          registeredRequest <= BUS_MST2SLV_IDLE;
        elsif rv2mem_stallOut(laneGroup) = '0' and clkEn = '1' then
          registeredRequest <= combinatorialRequest;
        end if;
      end if;
    end process;
    
    -- Select between the requests. Select the combinatorial request when stall
    -- is low so the busses can immediately start processing the next request,
    -- then switch to the registered request when any of the busses is busy
    -- (i.e. stall is high). When our bus is done but the processor is still
    -- stalled, gate the request so the request is not made again.
    rv2dmem(laneGroup)
      <= combinatorialRequest when rv2mem_stallOut(laneGroup) = '0'
      else bus_gate(registeredRequest, dmem2rv(laneGroup).busy);
    
    -- Register the bus result when ack is high.
    dmem_bus_result_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          readData_r    <= (others => '0');
          fault_r       <= '0';
        elsif clkEn = '1' then
          if dmem2rv(laneGroup).ack = '1' then
            readData_r  <= dmem2rv(laneGroup).readData;
            fault_r     <= dmem2rv(laneGroup).fault;
          end if;
          if rv2mem_stallOut(laneGroup) = '0' then
            fault_r     <= '0';
          end if;
        end if;
      end if;
    end process;
    
    -- Select between combinatorial and registered result based on the ack
    -- signal.
    dmem2rv_readData(laneGroup)
      <=   dmem2rv(laneGroup).readData when dmem2rv(laneGroup).ack = '1'
      else readData_r;
    
    dmem2rv_fault(laneGroup)
      <=   dmem2rv(laneGroup).fault    when dmem2rv(laneGroup).ack = '1'
      else fault_r;
    
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

