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
use rvex.utils_pkg.all;
use rvex.bus_pkg.all;

--=============================================================================
-- This peripheral acts as a sink for the trace bytestream which the rvex core
-- can output when its trace unit is enabled. It consists of two (by default)
-- 4kiB buffers which can be accessed from the bus. When one of the buffers is
-- read from, its contents are frozen, and the contents of the other buffer are
-- released for writing. The first four bytes of each page are reserved,
-- holding the number of valid bytes within the page when it was frozen,
-- including the four reserved bytes themselves.
-------------------------------------------------------------------------------
entity periph_trace is
--=============================================================================
  generic (
    
    -- Size of the memory, specified as log2(size_in_bytes).
    DEPTH_LOG2B                 : natural := 13 -- 8kiB = 2x 4kiB
    
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
    -- Slave bus
    ---------------------------------------------------------------------------
    -- Bus interface for accessing the trace buffers. Bit DEPTH_LOG2B-1 selects
    -- the page, bits DEPTH_LOG2B-2..0 index within the page.
    bus2trace                   : in  bus_mst2slv_type;
    trace2bus                   : out bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Trace bytestream input
    ---------------------------------------------------------------------------
    -- When high, data is valid and should be registered.
    rv2trace_push               : in  std_logic;
    
    -- Trace data signal. Valid when push is high.
    rv2trace_data               : in  rvex_byte_type;
    
    -- When high while push is high, the trace unit is stalled. While stalled,
    -- push will stay high and data and end will remain stable.
    trace2rv_busy               : out std_logic
    
  );
end periph_trace;

--=============================================================================
architecture Behavioral of periph_trace is
--=============================================================================
  
  -- Current page ownership. When high, the lower page is selected for writing
  -- and the upper page is selected for bus access; when low, the roles are
  -- reversed.
  signal ownership              : std_logic;
  
  -- Byte counter type.
  subtype byteCounter_type is unsigned(DEPTH_LOG2B-1 downto 0);
  type byteCounter_array is array (natural range <>) of byteCounter_type;
  
  -- Trace side counter value, increment signal and full signal.
  signal bcnt_trace             : byteCounter_type;
  signal bcnt_inc               : std_logic;
  signal bcnt_full              : std_logic;
  
  -- Bus side counter value and clear signal.
  signal bcnt_bus               : byteCounter_type;
  signal bcnt_clear             : std_logic;
  
  -- Trace <-> RAM block interface.
  signal traceEnable            : rvex_mask_type;
  signal traceAddress           : rvex_address_type;
  signal traceData              : rvex_byte_type;
  
  -- Bus <-> RAM block interface.
  signal busEnable              : std_logic;
  signal busAddress             : rvex_address_type;
  signal busData                : rvex_data_type;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Instantiate memory
  -----------------------------------------------------------------------------
  memory_block: block is
    
    -- RAM block port A interface.
    signal trace2mem            : bus_mst2slv_type;
    
    -- RAM block port B interface.
    signal bus2mem              : bus_mst2slv_type;
    signal mem2bus              : bus_slv2mst_type;
    
    -- RAM data.
    subtype ram_type is rvex_data_array(0 to 2**(DEPTH_LOG2B-2)-1);
    shared variable ram : ram_type := (others => (others => '0'));
    
  begin
    
    -- I'm lazily abusing a RAM block implementation intended to be connected
    -- to a bus here because XST wasn't recognizing my dumbed-down description
    -- of exactly this implementation as RAM blocks for some reason.
    ram_block_inst: entity rvex.bus_ramBlock
      generic map (
        DEPTH_LOG2B             => DEPTH_LOG2B
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Memory port A.
        mst2mem_portA           => trace2mem,
        mem2mst_portA           => open,
        
        -- Memory port B.
        mst2mem_portB           => bus2mem,
        mem2mst_portB           => mem2bus
        
      );
    
    -- Connect port A to the trace interface.
    trace2mem.address     <= traceAddress;
    trace2mem.readEnable  <= '0';
    trace2mem.writeEnable <= '1';
    trace2mem.writeMask   <= traceEnable;
    trace2mem.writeData   <= traceData & traceData & traceData & traceData;
    
    -- Connect port B to the bus.
    bus2mem.address       <= busAddress;
    bus2mem.readEnable    <= busEnable;
    bus2mem.writeEnable   <= '0';
    bus2mem.writeMask     <= "0000";
    bus2mem.writeData     <= (others => '0');
    busData               <= mem2bus.readData;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Instantiate byte counters
  -----------------------------------------------------------------------------
  byte_counter_block: block is
    
    -- Physical byte counter registers.
    signal byteCounters           : byteCounter_array(1 downto 0);
    
    -- Next values for the trace and bus side byte counters.
    signal bcnt_trace_next        : byteCounter_type;
    signal bcnt_bus_next          : byteCounter_type;
    
  begin
    
    -- Instantiate the byte counter registers.
    byte_counter_regs: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          byteCounters <= (others => to_unsigned(4, DEPTH_LOG2B));
        elsif clkEn = '1' then
          if ownership = '1' then
            byteCounters(0) <= bcnt_trace_next;
            byteCounters(1) <= bcnt_bus_next;
          else
            byteCounters(0) <= bcnt_bus_next;
            byteCounters(1) <= bcnt_trace_next;
          end if;
        end if;
      end if;
    end process;
    
    -- Mux between the byte counters for the current values.
    bcnt_trace <= byteCounters(0) when ownership = '1' else byteCounters(1);
    bcnt_bus   <= byteCounters(1) when ownership = '1' else byteCounters(0);
    
    -- Instantiate the incrementer for the trace side byte counter.
    bcnt_trace_next <= bcnt_trace + 1 when bcnt_inc = '1' and bcnt_full = '0' else bcnt_trace;
    
    -- Determine whether the trace side is full.
    bcnt_full <= '1' when bcnt_trace(DEPTH_LOG2B-1) = '1' else '0';
    
    -- Instantiate the clear logic for the bus side counter.
    bcnt_bus_next <= to_unsigned(4, DEPTH_LOG2B) when bcnt_clear = '1' else bcnt_bus;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Trace interface
  -----------------------------------------------------------------------------
  trace_iface_proc: process (
    rv2trace_data, rv2trace_push, bcnt_trace, bcnt_full, ownership
  ) is
  begin
    
    -- Set default values.
    bcnt_inc <= '0';
    traceEnable <= (others => '0');
    
    -- Assign the buffer write data signal.
    traceData <= rv2trace_data;
    
    -- Determine the buffer write address.
    traceAddress(31 downto DEPTH_LOG2B-1) <= (others => '0');
    traceAddress(DEPTH_LOG2B-1) <= not ownership;
    traceAddress(DEPTH_LOG2B-2 downto 2)
      <= std_logic_vector(bcnt_trace(DEPTH_LOG2B-2 downto 2));
    
    -- Write to the buffer when a write is requested and the buffer is not
    -- full.
    if rv2trace_push = '1' and bcnt_full = '0' then
      bcnt_inc <= '1';
      case bcnt_trace(1 downto 0) is
        when "00"   => traceEnable <= "1000";
        when "01"   => traceEnable <= "0100";
        when "10"   => traceEnable <= "0010";
        when others => traceEnable <= "0001";
      end case;
    end if;
    
    -- Stall the trace data stream when the buffer is full.
    trace2rv_busy <= bcnt_full;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Bus interface
  -----------------------------------------------------------------------------
  bus_iface_block: block is
    
    -- FSM states. In idle, the bus can make single-cycle normal requests to
    -- the currently frozen page. When the other page is accessed, delay cycles
    -- are injected to allow the switch to occur without data loss or
    -- complicated forwarding-like logic.
    type state_type is (S_IDLE, S_SWITCH_1, S_SWITCH_2, S_SWITCH_LAST);
    
    -- Current and next FSM states.
    signal state                : state_type;
    signal state_next           : state_type;
    
    -- Next state for the ownership signal.
    signal ownership_next       : std_logic;    
    
    -- Next state for the byte counter clear signal.
    signal clear_next           : std_logic;    
    
    -- Current and next states for the bus busy and acknowledge signals.
    signal ack                  : std_logic;
    signal ack_next             : std_logic;
    signal busy                 : std_logic;
    signal busy_next            : std_logic;
    
    -- Current and next states of the bus read data mux signal. When high, the
    -- count word is selected; when low, the buffer itself is selected.
    signal dataMux              : std_logic;
    signal dataMux_next         : std_logic;
    
  begin
    
    -- Registers for the FSM.
    reg_proc: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          state       <= S_IDLE;
          ownership   <= '1';
          bcnt_clear  <= '0';
          ack         <= '0';
          busy        <= '0';
          dataMux     <= '0';
        elsif clkEn = '1' then
          state       <= state_next;
          ownership   <= ownership_next;
          bcnt_clear  <= clear_next;
          ack         <= ack_next;
          busy        <= busy_next;
          dataMux     <= dataMux_next;
        end if;
      end if;
    end process;
    
    -- Comnbinatorial FSM process.
    comb_proc: process (state, ownership, bus2trace, dataMux) is
    begin
      
      -- Set defaults.
      state_next      <= state;
      ownership_next  <= ownership;
      clear_next      <= '0';
      ack_next        <= '0';
      busy_next       <= '0';
      dataMux_next    <= dataMux;
      
      -- Handle states.
      case state is
        
        when S_IDLE =>
          if bus_requesting(bus2trace) = '1' then
            if unsigned(bus2trace.address(DEPTH_LOG2B-2 downto 2)) = 0 then
              dataMux_next <= '1';
            else
              dataMux_next <= '0';
            end if;
            if bus2trace.address(DEPTH_LOG2B-1) = ownership then
              ack_next <= '1';
            else
              state_next <= S_SWITCH_1;
              busy_next <= '1';
              clear_next <= '1';
            end if;
          end if;
          
        when S_SWITCH_1 =>
          ownership_next <= not ownership;
          state_next  <= state_type'succ(state);
          busy_next   <= '1';
          
        when S_SWITCH_LAST =>
          state_next  <= S_IDLE;
          ack_next    <= '1';
        
        when others =>
          state_next  <= state_type'succ(state);
          busy_next   <= '1';
        
      end case;
      
    end process;
    
    -- Assign the bus address signal.
    busEnable <= bus2trace.readEnable and not dataMux_next;
    busAddress <= bus2trace.address;
    
    -- Bus reply process.
    bus_reply_proc: process (
      ack, busy, dataMux, ownership, busData, bcnt_bus
    ) is
    begin
      trace2bus <= BUS_SLV2MST_IDLE;
      trace2bus.ack <= ack;
      trace2bus.busy <= busy;
      
      -- Mux between read data sources.
      if dataMux = '0' then
        
        -- Select the RAM block.
        trace2bus.readData <= busData;
        
      else
        
        -- Select the byte counters.
        trace2bus.readData <= (others => '0');
        trace2bus.readData(DEPTH_LOG2B-1 downto 0)
          <= std_logic_vector(bcnt_bus);
        
      end if;
    end process;
      
  end block;
  
end Behavioral;

