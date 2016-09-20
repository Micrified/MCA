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
-- This unit handles the bit-level part of the I2C protocol. It can generate
-- start, repeated start, stop, and data/ack bit signals. When the addressed
-- input signal is asserted, it will clock stretch until the next bit request.
-- The absolute maximum SCL frequency is clk / 12, though this is not
-- recommended. At normal FPGA/r-VEX frequencies this is more than fast-mode
-- plus (1 MHz) anyway.
-------------------------------------------------------------------------------
entity periph_i2c_bit is
--=============================================================================
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
    -- Pin control signals
    ---------------------------------------------------------------------------
    -- SDA pin control signals from/to its periph_i2c_pin instance.
    sda_rise                    : in  std_logic;
    sda_fall                    : in  std_logic;
    sda_read                    : in  std_logic;
    sda_release                 : out std_logic;
    sda_assert                  : out std_logic;
  
    -- SCL pin control signals from/to its periph_i2c_pin instance.
    scl_rise                    : in  std_logic;
    scl_fall                    : in  std_logic;
    scl_read                    : in  std_logic;
    scl_release                 : out std_logic;
    scl_assert                  : out std_logic;
    
    ---------------------------------------------------------------------------
    -- State machine handshaking
    ---------------------------------------------------------------------------
    -- Request signal:
    --   000: no request.
    --   001: start. Master mode is entered.
    --   010: stop.
    --   011: repeated start. If arbitration lost, slave mode is entered.
    --        Otherwise, master mode is entered.
    --   100: send 0.
    --   101: send 1. If arbitration lost, slave mode is entered.
    --   111: wait for first SCL rising edge after receiving a start condition.
    -- This signal is ignored while the state machine is busy.
    bit_request                 : in  std_logic_vector(2 downto 0);
    
    -- Acknowledge signal. High for one cycle some time after bit_request to
    -- signal completion. Request is checked again starting from the cycle
    -- after the acknowledgement.
    bit_ack                     : out std_logic;
    
    -- While ack is high in response to a bit request, this returns the
    -- received bit.
    bit_read                    : out std_logic;
    
    -- This is asserted for one cycle when we lose arbitration in master mode.
    -- This may be asserted before ack.
    arb_lost                    : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Timing configuration register value
    ---------------------------------------------------------------------------
    -- The values below are in diminished-one notation. i.e., a value of 1
    -- means 2 cycles.
    
    -- SCL low time in cycles:
    --   standard-mode:  >= 4.7us
    --   fast-mode:      >= 1.3us
    --   fast-mode plus: >= 0.5us
    time_low                    : in  std_logic_vector(11 downto 0);
    
    -- SCL high time in cycles:
    --   standard-mode:  >= 4.0us
    --   fast-mode:      >= 0.6us
    --   fast-mode plus: >= 0.26us
    time_high                   : in  std_logic_vector(11 downto 0);
    
    -- SDA edge to SCL release time in cycles:
    --   standard-mode:  >= 250ns + worst-case edge time
    --   fast-mode:      >= 100ns + worst-case edge time
    --   fast-mode plus: >= 50ns  + worst-case edge time
    time_edge                   : in  std_logic_vector(7 downto 0)
    
  );
end periph_i2c_bit;

--=============================================================================
architecture Behavioral of periph_i2c_bit is
--=============================================================================
  
  -- Bit state machine state type.
  type state_type is (
    S_IDLE, --> S_REPSTA_A, S_STA_A, S_STO_A, S_BIT0_A, S_BIT1_A, S_BIT0_C
                -- (conditional)
    
    -- Start and repeated start signal states.
    S_REPSTA_A,
    S_REPSTA_B,
    S_REPSTA_C,
    S_STA_A,
    S_STA_B, --> S_ACK0
    
    -- Stop signal states.
    S_STO_A,
    S_STO_B,
    S_STO_C,
    S_STO_D, --> S_ACK0
    
    -- Low bit states.
    S_BIT0_A,
    S_BIT0_B,
    S_BIT0_C,
    S_BIT0_D,
    S_ACK0, --> S_IDLE
    
    -- High bit states. 1_C goes to 0_D if another device asserted the SDA
    -- line.
    S_BIT1_A,
    S_BIT1_B,
    S_BIT1_C, --> S_BIT0_D (conditional)
    S_BIT1_D,
    S_ACK1 --> S_IDLE
    
  );
  
  -- Timer load type.
  type timer_load_type is (TL_NONE, TL_LOW, TL_HIGH, TL_EDGE);
  
  -- State machine registers.
  signal state                  : state_type;
  signal timer                  : std_logic_vector(11 downto 0);
  signal timer_zero             : std_logic;
  signal master                 : std_logic;
  signal first                  : std_logic;
  
  -- Next state control.
  signal state_next             : state_type;
  signal timer_load             : timer_load_type;
  signal wait_scl_high          : std_logic;
  signal wait_scl_low           : std_logic;
  signal continue               : std_logic;
  
  -- Master/slave mode selection.
  signal master_assert          : std_logic;
  signal master_release         : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- State registers.
  state_reg: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state <= S_IDLE;
        timer <= (others => '0');
        master <= '0';
        first <= '0';
      elsif clkEn = '1' then
        
        -- Go to the next state and set the first cycle flag when continue is
        -- asserted.
        if continue = '1' then
          state <= state_next;
          first <= '1';
        else
          first <= '0';
        end if;
        
        -- Load the timer in the first cycle. Otherwise decrement it.
        if first = '1' then
          case timer_load is
            when TL_LOW  => timer <= time_low;
            when TL_HIGH => timer <= time_high;
            when TL_EDGE => timer <= X"0" & time_edge;
            when others  => timer <= X"000";
          end case;
        elsif timer_zero = '0' then
          timer <= std_logic_vector(unsigned(timer) - 1);
        end if;
        
        -- Handle the master/slave mode register.
        if master_release = '1' then
          master <= '0';
        elsif master_assert = '1' then
          master <= '1';
        end if;
        
      end if;
    end if;
  end process;
  
  -- Determine whether the timer has reached zero.
  timer_zero <= '1' when timer = X"000" else '0';
  
  -- Determine what the next state should be and drive the outputs.
  state_proc: process (
    state, bit_request, first, sda_read, scl_read, master
  ) is
  begin
    
    -- Set default values.
    bit_ack         <= '0';
    bit_read        <= '0';
    arb_lost        <= '0';
    sda_release     <= '0';
    sda_assert      <= '0';
    scl_release     <= '0';
    scl_assert      <= '0';
    state_next      <= state_type'succ(state);
    timer_load      <= TL_NONE;
    wait_scl_high   <= '0';
    wait_scl_low    <= '0';
    master_assert   <= '0';
    master_release  <= '0';
    
    -- Handle the states.
    case state is
      when S_IDLE =>
        case bit_request is
          when "001"  => state_next <= S_STA_A;
          when "010"  => state_next <= S_STO_A;
          when "011"  => state_next <= S_REPSTA_A;
          when "100"  => state_next <= S_BIT_A0;
          when "101"  => state_next <= S_BIT_A1;
          when "111"  => state_next <= S_BIT0_C;
          when others => state_next <= S_IDLE;
        end case;
        --------------------
        
      when S_REPSTA_A =>
        sda_release <= first;
        timer_load <= TL_EDGE;
        
      when S_REPSTA_B =>
        scl_release <= first;
        wait_scl_high <= '1';
      
      when S_REPSTA_C =>
        if sda_read = '0' then
          arb_lost <= first;
          master_release <= first;
        end if;
        timer_load <= TL_LOW;
      
      when S_STA_A =>
        sda_assert <= first;
        timer_load <= TL_LOW;
      
      when S_STA_B =>
        scl_assert <= first;
        timer_load <= TL_LOW;
        master_assert <= first;
        state_next <= S_ACK0;
        --------------------
        
      when S_STO_A =>
        sda_assert <= first;
        timer_load <= TL_EDGE;
      
      when S_STO_B =>
        scl_release <= first;
        wait_scl_high <= '1';
        
      when S_STO_C =>
        timer_load <= TL_LOW;
        
      when S_STO_D =>
        sda_release <= first;
        timer_load <= TL_LOW;
        master_release <= first;
        state_next <= S_ACK0;
        --------------------
        
      when S_BIT0_A =>
        sda_assert <= first;
        timer_load <= TL_EDGE;
      
      when S_BIT0_B =>
        scl_release <= first;
        wait_scl_high <= '1';
        
      when S_BIT0_C =>
        if master = '1' then
          timer_load <= TL_HIGH;
        else
          wait_scl_low <= '1';
        end if;
        
      when S_BIT0_D =>
        scl_assert <= first;
        if master = '1' then
          timer_load <= TL_LOW;
        end if;
      
      when S_ACK0 =>
        bit_ack <= '1';
        bit_read <= '0';
        state_next <= S_IDLE;
        --------------------
        
      when S_BIT1_A =>
        sda_release <= first;
        timer_load <= TL_EDGE;
        
      when S_BIT1_B =>
        scl_release <= first;
        wait_scl_high <= '1';
        
      when S_BIT1_C =>
        if sda_read = '0' then
          arb_lost <= first;
          master_release <= first;
          state_next <= S_BIT0_D;
          wait_scl_low <= '1';
        elsif master = '1' then
          timer_load <= TL_HIGH;
        else
          wait_scl_low <= '1';
        end if;
        
      when S_BIT1_D =>
        scl_assert <= first;
        if master = '1' then
          timer_load <= TL_LOW;
        end if;
      
      when S_ACK1 =>
        bit_ack <= '1';
        bit_read <= '1';
        state_next <= S_IDLE;
        --------------------
        
      when others =>
        state_next <= S_IDLE;
      
    end case;
    
  end process;
  
  -- Determine whether or not we can go to the next state.
  continue_proc: process (
    first, timer_zero, wait_scl_high, wait_scl_low, scl_read
  ) is
  begin
    if first = '1' then
      -- The timer has not been reloaded yet in the first cycle.
      continue <= '0';
    elsif timer_zero = '0' then
      -- Waiting for the timer to expire.
      continue <= '0';
    elsif wait_scl_high = '1' and scl_read = '0' then
      -- Waiting for SCL to be released by all devices.
      continue <= '0';
    elsif wait_scl_low = '1' and scl_read = '1' then
      -- Waiting for the master to assert SCL.
      continue <= '0';
    else
      -- Nothing stopping us from going to the next state.
      continue <= '1';
    end if;
  end process;
  
end Behavioral;

