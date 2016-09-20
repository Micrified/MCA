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
-- This entity contains the state machine which handles cache misses for an
-- instruction cache block.
-------------------------------------------------------------------------------
entity cache_instr_missCtrl is
--=============================================================================
  generic (
    
    -- Core configuration. Must be equal to the configuration presented to the
    -- rvex core connected to the cache.
    RCFG                        : rvex_generic_config_type := rvex_cfg;
    
    -- Cache configuration.
    CCFG                        : cache_generic_config_type := cache_cfg
    
  );
  port (
    
    -- Clock input.
    clk                         : in  std_logic;
    
    -- Active high reset input.
    reset                       : in  std_logic;
    
    -- Active high clock enable input for the CPU domain.
    clkEnCPU                    : in  std_logic;
    
    -- Active high clock enable input for the bus domain.
    clkEnBus                    : in  std_logic;
    
    -- CPU stall output.
    stall                       : in  std_logic;
    
    -- CPU address/PC input.
    cpuAddr                     : in  rvex_address_type;
    
    -- Update enable signal from the mux/demux logic signalling that the
    -- cache line which contains cpuAddr should be refreshed. While an
    -- update is in progress, cpuAddr is assumed to be stable. Governed by 
    -- the clkEnCPU clock gate signal.
    updateEnable                : in  std_logic;
    
    -- Signals that the line fetch is complete and that the data in line is
    -- to be written to the data memory. Governed by the clkEnCPU clock gate
    -- signal.
    done                        : out std_logic;
    
    -- Cache line data output, valid when done is high.
    line                        : out std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
    
    -- This signal is high when the controller is busy, signalling that
    -- reconfiguration is not possible at this time.
    blockReconfig               : out std_logic;
    
    -- Bus fault output. This is asserted when a bus fault occurs while
    -- handling a miss.
    busFault                    : out std_logic;
    
    -- Connections to the memory bus. Governed by clkEnBus.
    cacheToBus                  : out bus_mst2slv_type;
    busToCache                  : in  bus_slv2mst_type
    
  );
end cache_instr_missCtrl;

--=============================================================================
architecture Behavioral of cache_instr_missCtrl is
--=============================================================================
  
  -- The number of bus accesses necessary to update an entire cache line.
  constant ACCESSES_PER_LINE    : natural := 2**RCFG.numLanesLog2;
  
  -- Current state.
  signal state                  : natural range 0 to ACCESSES_PER_LINE+1;
  
  -- When set, advances to the next state.
  signal advance                : std_logic;
  
  -- When set, returns to idle state.
  signal resetState             : std_logic;
  
  -- When set, the bus fault output will be asserted until stall stall goes low
  -- (at which point the core should start handling it).
  signal fault                  : std_logic;
  
  -- This register will always be cleared when stall is low, and will otherwise
  -- be set when fault is high. Together with fault, it forms the bus_fault
  -- signal, which is sent to the core.
  signal fault_r                : std_logic;
  
  -- Next state.
  signal state_next             : natural range 0 to ACCESSES_PER_LINE+1;
  
  -- State names.
  constant IDLE_STATE           : natural := 0;
  constant REQ_N_STATE          : natural := ACCESSES_PER_LINE;
  constant WAIT_STATE           : natural := ACCESSES_PER_LINE+1;
  
  -- Line buffer registers.
  signal line_buffer            : std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
  
  -- To get around a weird bug in XST, we need to provide some extra delay
  -- between the line buffer registers and the inputs of the block RAM, because
  -- it's having trouble doing this on its own to avoid hold violations.
  signal line_buffer_d          : std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
  attribute keep                : string;
  attribute keep of line_buffer_d : signal is "true";
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- FSM documentation
  -----------------------------------------------------------------------------
  -- This component implements the following FSM to handle cache line retrieval
  -- over the memory bus, taking sycnhronization of the two clock gate domains
  -- into consideration. This allows the CPU to be stopped for debugging
  -- without the bus being affected somehow, for example.
  --
  --       reset
  --         v                   | idle state, waiting for commands. Part 0 of
  --     .-------.               | the line is already requested when advance
  -- .-->| idle  | - - - - - - - | is high, but the FSM passes through req_0
  -- |   '-------'               | regardless of the done output to save on
  -- |       | clkEnCPU          | logic resources.
  -- |       v & updateEnable      
  -- |   .-------.               | Requesting cache line part 0 on the memory
  -- |   | req_0 | - - - - - - - | bus, i.e. readEnable is high. When advance
  -- |   '-------'               | is high, the read data is stored in r0.
  -- |       | clkEnBus
  -- |       v & mem.ack
  -- |      ...  - - - - - - - - | Same behavior as req_0 for next parts.
  -- |       | clkEnBus
  -- |       v & mem.ack
  -- |   .-------.               | Same behavior as req_0, but now when advance
  -- |`--| req_n | - - - - - - - | is high done is also asserted. line is set
  -- | * '-------'               | to r0..rn-1 & mem.data.
  -- |       | clkEnBus
  -- |       | & mem.ack         * clkEnBus & mem.ack & clkEnCpu
  -- |       v & !clkEnCpu
  -- |   .-------.               
  -- |   | wait  | - - - - - - - | done is asserted, line is set to r0..rn.
  -- |   '-------'
  -- |       | clkEnCpu
  -- '-------'
  -- 
  -- advance is used to go to the next state, resetState is used to return to
  -- the idle state.
  
  -----------------------------------------------------------------------------
  -- FSM registers
  -----------------------------------------------------------------------------
  fsm_ctrl: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state <= 0;
        fault_r <= '0';
      else
        state <= state_next;
        if stall = '0' then
          fault_r <= '0';
        elsif fault = '1' then
          fault_r <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- FSM state decoding
  -----------------------------------------------------------------------------
  -- Determine the values for the advance and resetState signals.
  fsm_decode_1: process (
    state, clkEnCPU, clkEnBus, stall, updateEnable, busToCache.ack
  ) is
  begin
    
    -- Do nothing by default.
    advance <= '0';
    resetState <= '0';
    fault <= '0';
    
    -- Figure out what to do next.
    if state = IDLE_STATE then
      if clkEnCPU = '1' and updateEnable = '1' then
        advance <= '1';
      end if;
    elsif state = WAIT_STATE then
      if clkEnCPU = '1' then
        resetState <= '1';
      end if;
    else
      if clkEnBus = '1' and busToCache.ack = '1' then
        if busToCache.fault = '1' then
          fault <= '1';
          resetState <= '1';
        else
          if clkEnCPU = '1' and state = REQ_N_STATE then
            resetState <= '1';
          else
            advance <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Determine the next state based on the advance and resetState signals.
  state_next <= IDLE_STATE  when resetState = '1' else
                state + 1   when advance = '1' else
                state;
  
  -- Determine the memory bus address and whether we should request a read.
  det_mem_bus_access: process (state_next, cpuAddr) is
    variable burstStart : std_logic;
  begin
    
    -- Set the bus defaults.
    cacheToBus <= BUS_MST2SLV_IDLE;
    cacheToBus.address <= (others => '0');
    
    cacheToBus.address(31 downto icacheOffsetLSB(RCFG, CCFG))
      <= cpuAddr(31 downto icacheOffsetLSB(RCFG, CCFG));
    
    if state_next >= 1 and state_next <= ACCESSES_PER_LINE then
      
      -- Determine whether this is the first bus transfer in the burst.
      if state_next = 1 then
        burstStart := '1';
      else
        burstStart := '0';
      end if;
      
      -- Request the next part. Set the burst and lock bus flags in order to do
      -- a burst transfer to speed things up.
      cacheToBus.readEnable <= '1';
      cacheToBus.flags <= bus_flags_gen(
        burstStart  => burstStart,
        burstEnable => '1',
        lock        => '1'
      );
      cacheToBus.address(icacheOffsetLSB(RCFG, CCFG)-1 downto 2)
        <= std_logic_vector(to_unsigned(state_next-1, icacheOffsetLSB(RCFG, CCFG)-2));
      
    end if;
  end process;
  
  -- Generate the done signal.
  done <= '1' when (
    (state_next = WAIT_STATE or resetState = '1')
    and ((fault or fault_r) = '0')
  ) else '0';
  
  -- Generate the bus fault signal.
  busFault <= fault_r;
  
  -- Generate the blockReconfig signal.
  blockReconfig <= '1' when state /= IDLE_STATE else updateEnable;
  
  -- Instantiate the line buffer registers.
  line_buf_reg_gen: for i in 0 to ACCESSES_PER_LINE-1 generate
    line_buf_reg_n: process (clk) is
    begin
      if rising_edge(clk) then
        if state = i + 1 then
          line_buffer(32*i + 31 downto 32*i)
            <= busToCache.readData;
        end if;
      end if;
      
      -- Prevent hold timing violations on this signal, because XST doesn't
      -- know how to deal with them for some reason.
      if falling_edge(clk) then
        line_buffer_d <= line_buffer;
      end if;
    end process;
  end generate;
  
  -- Forward the cache line to the cache memory.
  line_buf_forward_a: if ACCESSES_PER_LINE > 1 generate
    line(icacheLineWidth(RCFG, CCFG)-32-1 downto 0)
      <= line_buffer_d(icacheLineWidth(RCFG, CCFG)-32-1 downto 0);
  end generate;
  
  line(icacheLineWidth(RCFG, CCFG)-1 downto icacheLineWidth(RCFG, CCFG)-32) <=
    busToCache.readData when state = WAIT_STATE - 1 else
    line_buffer_d(icacheLineWidth(RCFG, CCFG)-1 downto icacheLineWidth(RCFG, CCFG)-32);
    
end Behavioral;

