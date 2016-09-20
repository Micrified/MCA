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

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
-- pragma translate_off
use rvex.simUtils_pkg.all;
use rvex.simUtils_mem_pkg.all;
-- pragma translate_on
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;
use rvex.rvsys_grlib_pkg.all;

library grlib;
use grlib.amba.all;
use grlib.devices.all;

library gaisler;
use gaisler.leon3.all;

--=============================================================================
-- This entity is designed such that it can be used in place of the LEON3 core
-- from grlib, but with a different interrupt controller.
-------------------------------------------------------------------------------
entity rvsys_grlib_rctrl is
--=============================================================================
  generic (
    
    -- Configuration vector.
    CFG                         : rvex_grlib_generic_config_type := rvex_grlib_cfg;
    
    -- Platform version tag. This is put in the global control registers of the
    -- processors.
    PLATFORM_TAG                : std_logic_vector(55 downto 0) := (others => '0');
    
    -- AHB master starting index. There will be as many AHB masters as there
    -- are lane groups in the core.
    AHB_MASTER_INDEX_START      : integer range 0 to NAHBMST-1 := 0;
    
    -- When true, memory accesses made by the rvex will be checked for
    -- consistency. When a memory access does not behave as if a basic
    -- unlimited sized memory were connected to the bus, a warning is
    -- reported.
    CHECK_MEM                   : boolean := false;
    
    -- S-record initialization file for the memory checking code.
    CHECK_MEM_FILE              : string := ""
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Clock input, registers are rising edge triggered.
    clki                        : in  std_ulogic;
    
    -- Active *low* synchronous reset input.
    rstn                        : in  std_ulogic;
    
    ---------------------------------------------------------------------------
    -- Processor interface
    ---------------------------------------------------------------------------
    -- AHB master interface. This is used for instruction and data access. Each
    -- lane group has its own AHB master.
    ahbmi                       : in  ahb_mst_in_type;
    ahbmo                       : out ahb_mst_out_vector_type(2**CFG.core.numLaneGroupsLog2-1 downto 0);
    
    -- AHB slave input for bus snooping.
    ahbsi                       : in  ahb_slv_in_type;
    
    -- Slave rvex bus, to be connected to an ahb2bus bridge up the hierarchy.
    -- Used to access debug control and status registers for the core, cache
    -- and any other support systems. The register map is as follows.
    --          _____________________________
    --  0x3FFF |                             |
    --         ~ Trace data buffer B         ~
    --  0x3000 |_____________________________|
    --  0x2FFF |                             |
    --         ~ Trace data buffer A         ~
    --  0x2000 |_____________________________|
    --  0x1FFF |                             |
    --         | Context 7 ctrl regs         |
    --         |                             |
    --  0x1E00 |_____________________________|
    --  0x1DFF | Context 7 GP regs           |
    --  0x1D00 |_____________________________|
    --         |_____________________________|
    --  0x1BFF |                             |
    --         | Context 6 ctrl regs         |
    --         |                             |
    --  0x1A00 |_____________________________|
    --  0x19FF | Context 6 GP regs           |
    --  0x1900 |_____________________________|
    --         |_____________________________|
    --  0x17FF |                             |
    --         | Context 5 ctrl regs         |
    --         |                             |
    --  0x1600 |_____________________________|
    --  0x15FF | Context 5 GP regs           |
    --  0x1500 |_____________________________|
    --         |_____________________________|
    --  0x13FF |                             |
    --         | Context 4 ctrl regs         |
    --         |                             |
    --  0x1200 |_____________________________|
    --  0x11FF | Context 4 GP regs           |
    --  0x1100 |_____________________________|
    --         |_____________________________|
    --  0x0FFF |                             |
    --         | Context 3 ctrl regs         |
    --         |                             |
    --  0x0E00 |_____________________________|
    --  0x0DFF | Context 3 GP regs           |
    --  0x0D00 |_____________________________|
    --  0x0CFF | Reserved for MMU ctrl regs  |
    --  0x0C00 |_____________________________|
    --  0x0BFF |                             |
    --         | Context 2 ctrl regs         |
    --         |                             |
    --  0x0A00 |_____________________________|
    --  0x09FF | Context 2 GP regs           |
    --  0x0900 |_____________________________|
    --  0x08FF | Cache control regs          |
    --  0x0800 |_____________________________|
    --  0x07FF |                             |
    --         | Context 1 ctrl regs         |
    --         |                             |
    --  0x0600 |_____________________________|
    --  0x05FF | Context 1 GP regs           |
    --  0x0500 |_____________________________|
    --  0x04FF | Global control regs         |
    --  0x0400 |_____________________________|
    --  0x03FF |                             |
    --         | Context 0 ctrl regs         |
    --         |                             |
    --  0x0200 |_____________________________|
    --  0x01FF | Context 0 GP regs           |
    --  0x0100 |_____________________________|
    --  0x00FF | Core ctrl regs              |
    --  0x0000 |_____________________________|

    bus2dgb                     : in  bus_mst2slv_type;
    dbg2bus                     : out bus_slv2mst_type;
    
    -- r-VEX run control interface.
    rctrl2rv_irq                : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '0');
    rctrl2rv_irqID              : in  rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0) := (others => (others => '0'));
    rv2rctrl_irqAck             : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    rctrl2rv_run                : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '1');
    rv2rctrl_idle               : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    rv2rctrl_break              : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    rv2rctrl_traceStall         : out std_logic;
    rctrl2rv_traceStall         : in  std_logic := '0';
    rctrl2rv_reset              : in  std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0) := (others => '0');
    rctrl2rv_resetVect          : in  rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0) := CFG.core.resetVectors(2**CFG.core.numContextsLog2-1 downto 0);
    rv2rctrl_done               : out std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
    
    -- GPIO input that can be read from address 0x404 (word) or 0x407 (byte).
    gpio_dip                    : in std_logic_vector(7 downto 0) := (others => '0')
    
  );
end rvsys_grlib_rctrl;

--=============================================================================
architecture Behavioral of rvsys_grlib_rctrl is
--=============================================================================
  
  -- System control signals in the rvex library format.
  signal resetCPU               : std_logic;
  signal resetBus               : std_logic;
  signal clk                    : std_logic;
  signal clkEnCPU               : std_logic;
  signal clkEnBus               : std_logic;
  
  -- Soft reset signal from the APB bus.
  signal dbg_reset              : std_logic;
  
  -- Common cache interface signals.
  signal rv2cache_decouple      : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_blockReconfig : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_stallIn       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2cache_stallOut      : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal cache2rv_status        : rvex_cacheStatus_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
 
  -- Instruction cache interface signals.
  signal rv2icache_PCs          : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2icache_fetch        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2icache_cancel       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_instr        : rvex_syllable_array(2**CFG.core.numLanesLog2-1 downto 0);
  signal icache2rv_affinity     : std_logic_vector(2**CFG.core.numLaneGroupsLog2*CFG.core.numLaneGroupsLog2-1 downto 0);
  signal icache2rv_busFault     : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Data cache interface signals.
  signal rv2dcache_addr         : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_readEnable   : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeData    : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeMask    : rvex_mask_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_writeEnable  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal rv2dcache_bypass       : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_readData     : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_ifaceFault   : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal dcache2rv_busFault     : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Trace data interface signals.
  signal rv2trace_push          : std_logic;
  signal rv2trace_data          : rvex_byte_type;
  signal trace2rv_busy          : std_logic;
  
  -- Cache to AHB bus bridge interface signals.
  signal cache2bridge_bus       : bus_mst2slv_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal bridge2cache_bus       : bus_slv2mst_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  
  -- Bus snooper cache invalidation signals.
  signal bus2cache_invalAddr    : rvex_address_type;
  signal bus2cache_invalSource  : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal bus2cache_invalEnable  : std_logic;
  
  -- Cache control signals.
  signal sc2icache_flush        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal sc2dcache_flush        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
  signal sc2dcache_bypass       : std_logic;
  
  -- Debug bus demuxer to global control registers.
  signal demux2glob             : bus_mst2slv_type;
  signal glob2demux             : bus_slv2mst_type;
  
  -- Debug bus demuxer to cache control registers.
  signal demux2cache            : bus_mst2slv_type;
  signal cache2demux            : bus_slv2mst_type;
  
  -- Debug bus demuxer to MMU control registers.
  signal demux2mmu              : bus_mst2slv_type;
  signal mmu2demux              : bus_slv2mst_type;
  
  -- Debug bus demuxer to core control registers.
  signal demux2rv               : bus_mst2slv_type;
  signal rv2demux               : bus_slv2mst_type;
  
  -- Debug bus demuxer to trace buffer.
  signal demux2trace            : bus_mst2slv_type;
  signal trace2demux            : bus_slv2mst_type;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- System control
  -----------------------------------------------------------------------------
  resetCPU  <= dbg_reset or not rstn;
  resetBus  <= not rstn;
  clk       <= clki;
  
  -- clkEnCPU and clkEnBus kinda don't work in this platform because there's no
  -- synchronization between the debug register bus and the registers, and
  -- the bus clk is always enabled because AMBA doesn't have a clock enable. So
  -- they're just tied to '1' here and exist only as a formality.
  clkEnCPU  <= '1';
  clkEnBus  <= '1';
  
  -----------------------------------------------------------------------------
  -- Instantiate the rvex core
  -----------------------------------------------------------------------------
  rvex_block: block is
    
    -- Raw rvex debug bus interface signals.
    signal dbg2rv_addr          : rvex_address_type;
    signal dbg2rv_readEnable    : std_logic;
    signal dbg2rv_writeEnable   : std_logic;
    signal dbg2rv_writeMask     : rvex_mask_type;
    signal dbg2rv_writeData     : rvex_data_type;
    signal rv2dbg_readData      : rvex_data_type;
    
    -- Bus ack register.
    signal ack                  : std_logic;
    
  begin
    
    -- Instantiate the rvex core.
    rvex_inst: entity rvex.core
      generic map (
        CFG                       => CFG.core,
        coreID                    => AHB_MASTER_INDEX_START,
        PLATFORM_TAG              => PLATFORM_TAG
      )
      port map (
        
        -- System control.
        reset                     => resetCPU,
        clk                       => clk,
        clkEn                     => clkEnCPU,
        
        -- Run control interface.
        rctrl2rv_irq              => rctrl2rv_irq,
        rctrl2rv_irqID            => rctrl2rv_irqID,
        rv2rctrl_irqAck           => rv2rctrl_irqAck,
        rctrl2rv_run              => rctrl2rv_run,
        rv2rctrl_idle             => rv2rctrl_idle,
        rv2rctrl_break            => rv2rctrl_break,
        rv2rctrl_traceStall       => rv2rctrl_traceStall,
        rctrl2rv_traceStall       => rctrl2rv_traceStall,
        rctrl2rv_reset            => rctrl2rv_reset,
        rctrl2rv_resetVect        => rctrl2rv_resetVect,
        rv2rctrl_done             => rv2rctrl_done,
        
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
        rv2trsink_push            => rv2trace_push,
        rv2trsink_data            => rv2trace_data,
        trsink2rv_busy            => trace2rv_busy
        
      );
    
    -- Connect the debug bus.
    dbg2rv_addr         <= demux2rv.address;
    dbg2rv_readEnable   <= demux2rv.readEnable;
    dbg2rv_writeEnable  <= demux2rv.writeEnable;
    dbg2rv_writeMask    <= demux2rv.writeMask;
    dbg2rv_writeData    <= demux2rv.writeData;
    
    -- Generate the bus acknowledge signal.
    ack_reg_proc: process (clk) is
    begin
      if rising_edge(clk) then
        if resetBus = '1' then
          ack <= '0';
        elsif clkEnBus = '1' then
          ack <= demux2rv.readEnable or demux2rv.writeEnable;
        end if;
      end if;
    end process;
    
    -- Drive the bus result signals.
    bus_result_proc: process (rv2dbg_readData, ack) is
    begin
      rv2demux <= BUS_SLV2MST_IDLE;
      rv2demux.ack <= ack;
      rv2demux.readData <= rv2dbg_readData;
    end process;
    
    -- Check memory accesses.
    -- pragma translate_off
    mem_check_gen: if CHECK_MEM generate
      signal PCs_r                : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal fetch_r              : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal addr_r               : rvex_address_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal readEnable_r         : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal writeData_r          : rvex_data_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal writeMask_r          : rvex_mask_array(2**CFG.core.numLaneGroupsLog2-1 downto 0);
      signal writeEnable_r        : std_logic_vector(2**CFG.core.numLaneGroupsLog2-1 downto 0);
    begin
      test_mem_regs: process (clk) is
      begin
        if rising_edge(clk) then
          if resetCPU = '1' then
            PCs_r         <= (others => (others => '0'));
            fetch_r       <= (others => '0');
            addr_r        <= (others => (others => '0'));
            readEnable_r  <= (others => '0');
            writeData_r   <= (others => (others => '0'));
            writeMask_r   <= (others => (others => '0'));
            writeEnable_r <= (others => '0');
          elsif clkEnCPU = '1' then
            for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 loop
              if rv2cache_stallOut(laneGroup) = '0' then
                PCs_r(laneGroup)          <= rv2icache_PCs(laneGroup);
                fetch_r(laneGroup)        <= rv2icache_fetch(laneGroup);
                addr_r(laneGroup)         <= rv2dcache_addr(laneGroup);
                readEnable_r(laneGroup)   <= rv2dcache_readEnable(laneGroup);
                writeData_r(laneGroup)    <= rv2dcache_writeData(laneGroup);
                writeMask_r(laneGroup)    <= rv2dcache_writeMask(laneGroup);
                writeEnable_r(laneGroup)  <= rv2dcache_writeEnable(laneGroup);
              end if;
            end loop;
          end if;
        end if;
      end process;
      
      mem_check_model: process is
        variable mem      : rvmem_memoryState_type;
        variable readData : rvex_data_type;
        variable lane     : natural;
        variable PC       : rvex_address_type;
        variable aff      : std_logic_vector(CFG.core.numLaneGroupsLog2-1 downto 0);
      begin
        
        -- Load the srec file into the memory.
        rvmem_clear(mem, '0');
        if CHECK_MEM_FILE /= "" then
          rvmem_loadSRec(mem, CHECK_MEM_FILE);
        end if;
        
        -- Check memory results as seen by the core.
        loop
          
          -- Wait for the next clock.
          wait until rising_edge(clk) and clkEnCPU = '1' and resetCPU = '0';
          
          -- Loop over all the lane groups.
          for laneGroup in 0 to 2**CFG.core.numLaneGroupsLog2-1 loop
            if rv2cache_stallOut(laneGroup) = '0' then
              
              -- Check data access.
              if readEnable_r(laneGroup) = '1' then
                rvmem_read(mem, addr_r(laneGroup), readData);
                if not std_match(readData, dcache2rv_readData(laneGroup)) then
                  report "*****ERROR***** Data read from address " & rvs_hex(addr_r(laneGroup))
                      & " should have returned " & rvs_hex(readData)
                      & " but returned " & rvs_hex(dcache2rv_readData(laneGroup))
                    severity warning;
                else
                  --report "Data read from address " & rvs_hex(addr_r(laneGroup))
                  --     & " correctly returned " & rvs_hex(dcache2rv_readData(laneGroup))
                  --  severity note;
                end if;
              elsif writeEnable_r(laneGroup) = '1' then
                rvmem_write(mem, addr_r(laneGroup), writeData_r(laneGroup), writeMask_r(laneGroup));
                report "Processed write to address " & rvs_hex(addr_r(laneGroup))
                     & ", value is " & rvs_hex(writeData_r(laneGroup))
                     & " with mask " & rvs_bin(writeMask_r(laneGroup))
                  severity note;
              end if;
              
              -- Check instruction access.
              if fetch_r(laneGroup) = '1' and rv2icache_cancel(laneGroup) = '0' then
                aff := icache2rv_affinity(
                  laneGroup*CFG.core.numLaneGroupsLog2 + CFG.core.numLaneGroupsLog2 - 1
                  downto
                  laneGroup*CFG.core.numLaneGroupsLog2
                );
                for laneIndex in 0 to 2**(CFG.core.numLanesLog2-CFG.core.numLaneGroupsLog2)-1 loop
                  lane := group2firstLane(laneGroup, CFG.core) + laneIndex;
                  PC := std_logic_vector(unsigned(PCs_r(laneGroup)) + laneIndex*4);
                  rvmem_read(mem, PC, readData);
                  if not std_match(readData, icache2rv_instr(lane)) then
                    report "*****ERROR***** Instruction read from address " & rvs_hex(PC)
                        & " should have returned " & rvs_hex(readData)
                        & " but returned " & rvs_hex(icache2rv_instr(lane))
                        & " from block " & rvs_uint(aff)
                      severity warning;
                  else
                    --report "Instruction read from address " & rvs_hex(PC)
                    --     & " correctly returned " & rvs_hex(icache2rv_instr(lane))
                    --     & " from block " & rvs_uint(aff)
                    --  severity note;
                  end if;
                end loop;
              end if;
              
            end if;
          end loop;
          
        end loop;
        
      end process;
    end generate; -- mem_check_gen
    -- pragma translate_on
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Instantiate the trace data buffer
  -----------------------------------------------------------------------------
  trace_buffer: entity rvex.periph_trace
    generic map (
      DEPTH_LOG2B                 => 13 -- 8kiB = 2x 4kiB
    )
    port map (
      
      -- System control.
      reset                       => resetCPU,
      clk                         => clk,
      clkEn                       => clkEnCPU,
      
      -- Slave bus.
      bus2trace                   => demux2trace,
      trace2bus                   => trace2demux,
      
      -- Trace bytestream input.
      rv2trace_push               => rv2trace_push,
      rv2trace_data               => rv2trace_data,
      trace2rv_busy               => trace2rv_busy
      
    );
  
  -----------------------------------------------------------------------------
  -- Generate the bypass signals
  -----------------------------------------------------------------------------
  -- When the bypass signal is high, memory accesses bypass the cache. This is
  -- important for peripheral accesses. Because the rvex core does not generate
  -- such a signal, we generate one here based on the address: we assume that
  -- everything in the high 2 GiB memory space is mapped to peripherals and
  -- should not be cached.
  bypass_gen: for laneGroup in 2**CFG.core.numLaneGroupsLog2-1 downto 0 generate
    rv2dcache_bypass(laneGroup)
      <= rv2dcache_addr(laneGroup)(31)
      or sc2dcache_bypass;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the cache
  -----------------------------------------------------------------------------
  cache_inst: entity rvex.cache
    generic map (
      RCFG                      => CFG.core,
      CCFG                      => CFG.cache
    )
    port map (
      
      -- System control.
      reset                     => resetCPU,
      clk                       => clk,
      clkEnCPU                  => clkEnCPU,
      clkEnBus                  => clkEnBus,
      
      -- Core common memory interface.
      rv2cache_decouple         => rv2cache_decouple,
      cache2rv_blockReconfig    => cache2rv_blockReconfig,
      cache2rv_stallIn          => cache2rv_stallIn,
      rv2cache_stallOut         => rv2cache_stallOut,
      cache2rv_status           => cache2rv_status,
      
      -- Core instruction memory interface.
      rv2icache_PCs             => rv2icache_PCs,
      rv2icache_fetch           => rv2icache_fetch,
      rv2icache_cancel          => rv2icache_cancel,
      icache2rv_instr           => icache2rv_instr,
      icache2rv_affinity        => icache2rv_affinity,
      icache2rv_busFault        => icache2rv_busFault,
      
      -- Core data memory interface.
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
      cache2bus_bus             => cache2bridge_bus,
      bus2cache_bus             => bridge2cache_bus,
      
      -- Bus snooping interface.
      bus2cache_invalAddr       => bus2cache_invalAddr,
      bus2cache_invalSource     => bus2cache_invalSource,
      bus2cache_invalEnable     => bus2cache_invalEnable,
      
      -- Status and control signals.
      sc2icache_flush           => sc2icache_flush,
      sc2dcache_flush           => sc2dcache_flush
      
    );

  ---------------------------------------------------------------------------
  -- Cache Control Register
  ---------------------------------------------------------------------------
  --
  --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
  -- CACHE |       |  IFL  |       |  DFL  |               |             |B|
  --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
  --
  -- IFL    = Instruction Cache Flush bits. One bit per context.
  --
  -- DFL    = Data Cache Flush bits. One bit per context.
  --
  -- B      = Data Cache Bypass bit. This bit causes the data cache to be
  --          globally bypassed.
  
  -- Instantiate the cache registers.
  cache_control_reg_proc: process (clk) is
    
    -- Assigns signals to their reset/idle/default state.
    procedure defaultState is
    begin
      cache2demux <= BUS_SLV2MST_IDLE;
      sc2icache_flush <= (others => '0');
      sc2dcache_flush <= (others => '0');
    end defaultState;
    
  begin
    if rising_edge(clk) then
      if resetBus = '1' then
        defaultState;
        sc2dcache_bypass <= '0';
      elsif clkEnBus = '1' then
        defaultState;
        
        -- Acknowledge any bus requests we're given.
        cache2demux.ack <= bus_requesting(demux2cache);
        
        -- Address 0x00 write: instruction cache flush bits.
        if bus_writing(demux2cache, "------------------------00000000") then
          sc2icache_flush <= demux2cache.writeData(
            2**CFG.core.numLaneGroupsLog2 + 23 downto 24
          );
        end if;
        
        -- Address 0x01 write: data cache flush bits.
        if bus_writing(demux2cache, "------------------------00000001") then
          sc2dcache_flush <= demux2cache.writeData(
            2**CFG.core.numLaneGroupsLog2 + 15 downto 16
          );
        end if;
        
        -- Address 0x03 write: bypass flag.
        if bus_writing(demux2cache, "------------------------00000011") then
          sc2dcache_bypass <= demux2cache.writeData(0);
        end if;
        
        -- Readback of bypass flag.
        if bus_reading(demux2cache, "------------------------000000--") then
          cache2demux.readData(0) <= sc2dcache_bypass;
        end if;
        
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Instantiate the AHB bus bridges
  -----------------------------------------------------------------------------
  ahb_bus_bridge_gen: for laneGroup in 2**CFG.core.numLaneGroupsLog2-1 downto 0 generate
    
    ahb_bus_bridge_inst: entity rvex.bus2ahb
      generic map (
        
        -- Generic information as passed to grlib.dma2ahb.
        AHB_MASTER_INDEX        => AHB_MASTER_INDEX_START + laneGroup,
        AHB_VENDOR_ID           => VENDOR_TUDELFT,
        AHB_DEVICE_ID           => TUDELFT_RVEX,
        AHB_VERSION             => 0,
        
        -- rvex bus fault code used to indicate that an AHB bus error occured.
        BUS_ERROR_CODE          => X"00000000",
        
        -- rvex bus fault code used to indicate that an invalid rvex bus
        -- request was issued.
        REQ_ERROR_CODE          => X"00000001"
        
      )
      port map (
        
        -- System control.
        reset                   => resetBus,
        clk                     => clk,
        
        -- rvex library slave bus interface.
        bus2bridge              => cache2bridge_bus(laneGroup),
        bridge2bus              => bridge2cache_bus(laneGroup),
        
        -- AHB master interface.
        bridge2ahb              => ahbmo(laneGroup),
        ahb2bridge              => ahbmi
        
      );
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Bus snooper
  -----------------------------------------------------------------------------
  ahb_snoop_inst: entity rvex.ahb_snoop
    generic map (
      FIRST_MASTER        => AHB_MASTER_INDEX_START,
      NUM_CACHE_BLOCKS    => 2**CFG.core.numLaneGroupsLog2
    )
    port map (
      
      -- System control.
      reset               => resetBus,
      clk                 => clk,
      
      -- AHB interface.
      ahbsi               => ahbsi,
        
      -- Cache interface.
      invalAddr           => bus2cache_invalAddr,
      invalSource         => bus2cache_invalSource,
      invalEnable         => bus2cache_invalEnable
      
    );
  
  -----------------------------------------------------------------------------
  -- Global control registers
  -----------------------------------------------------------------------------
  --
  --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
  -- RESET |     Any write to this register resets the whole platform      |
  --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
  -- GPIO  |                                               |      DIP      |
  --       |-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|-+-+-+-+-+-+-+-|
  --
  -- DIP    = state of the DIP switches of the development board, if connected.
  --
  global_control_reg_proc: process (clk) is
    
    -- Assigns signals to their reset/idle/default state.
    procedure defaultState is
    begin
      glob2demux <= BUS_SLV2MST_IDLE;
      dbg_reset <= '0';
    end defaultState;
    
  begin
    if rising_edge(clk) then
      if resetBus = '1' then
        defaultState;
      elsif clkEnBus = '1' then
        defaultState;
        
        -- Acknowledge any bus requests we're given.
        glob2demux.ack <= bus_requesting(demux2glob);
        
        -- Address 0x00 write: reset rvex system.
        if bus_writing(demux2glob, "------------------------00000000") then
          dbg_reset <= '1';
        end if;
        
        -- Readback of GPIO DIP switch.
        if bus_reading(demux2glob, "------------------------000001--") then
          glob2demux.readData(7 downto 0) <= gpio_dip(7 downto 0);
        end if;
        
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Debug bus demuxer
  -----------------------------------------------------------------------------
  debug_bus_demux_block: block is
    
    constant ADDR_MAP : addrRangeAndMapping_array(0 to 4) := (
      0 => addrRangeAndMap( -- rvex debug interface (default).
        match => "------------------0-------------"
      ),
      1 => addrRangeAndMap( -- Global status/ctrl (256 bytes), overrides rvex global reg mirror at context 1.
        match => "------------------000100--------"
      ),
      2 => addrRangeAndMap( -- Cache status/ctrl (256 bytes), overrides rvex global reg mirror at context 2.
        match => "------------------001000--------"
      ),
      3 => addrRangeAndMap( -- MMU status/ctrl (256 bytes), overrides rvex global reg mirror at context 3.
        match => "------------------001100--------"
      ),
      4 => addrRangeAndMap( -- trace buffer.
        match => "------------------1-------------"
      )
    );
    
  begin
    
    -- Instantiate the demuxing unit.
    debug_bus_demux_inst: entity rvex.bus_demux
      generic map (
        ADDRESS_MAP       => ADDR_MAP
      )
      port map (
        
        -- System control.
        reset             => resetBus,
        clk               => clk,
        clkEn             => clkEnBus,
        
        -- Busses.
        mst2demux         => bus2dgb,
        demux2mst         => dbg2bus,
        demux2slv(0)      => demux2rv,
        demux2slv(1)      => demux2glob,
        demux2slv(2)      => demux2cache,
        demux2slv(3)      => demux2mmu,
        demux2slv(4)      => demux2trace,
        slv2demux(0)      => rv2demux,
        slv2demux(1)      => glob2demux,
        slv2demux(2)      => cache2demux,
        slv2demux(3)      => mmu2demux,
        slv2demux(4)      => trace2demux
        
      );
    
  end block;
  
  -- Respond with bus faults to the registers reserved for the MMU.
  mmu_control_reg_proc: process (clk) is
    
    -- Assigns signals to their reset/idle/default state.
    procedure defaultState is
    begin
      mmu2demux <= BUS_SLV2MST_IDLE;
    end defaultState;
    
  begin
    if rising_edge(clk) then
      if resetBus = '1' then
        defaultState;
      elsif clkEnBus = '1' then
        defaultState;
        
        -- Return a bus fault for any address.
        mmu2demux.ack <= bus_requesting(demux2mmu);
        mmu2demux.fault <= '1';
        
      end if;
    end if;
  end process;
  
end Behavioral;

