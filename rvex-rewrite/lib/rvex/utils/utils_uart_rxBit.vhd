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
use rvex.utils_pkg.all;

--=============================================================================
-- This is part of the utils_uart entity. It handles bit synchronization on the
-- RX side, strobing a signal whenever a bit has been received. It requires
-- clkEnBaud8 to be high 8 times per UART bit time.
-------------------------------------------------------------------------------
entity utils_uart_rxBit is
--=============================================================================
  port (
    
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Clock enable signal which should be high for one cycle eight times per
    -- UART bit time.
    clkEnBaud8                  : in  std_logic;
    
    -- Receive input.
    rx                          : in  std_logic;
    
    -- Received bit output. When strobe is high, data is valid and contains
    -- the latest received bit.
    data                        : out std_logic;
    strobe                      : out std_logic
    
  );
end utils_uart_rxBit;

--=============================================================================
architecture Behavioral of utils_uart_rxBit is
--=============================================================================
  
  -- Represents a majority voting lookup table for 3 input bits.
  constant MAJORITY_VOTE        : std_logic_vector(7 downto 0) := "11101000";
  
  -- Shift register containing the state of the rx pin for the last seven
  -- cycles.
  signal rxShiftReg             : std_logic_vector(5 downto 0);
  
  -- This signal goes high half a bit time after a rising or falling edge of
  -- the rx signal that was not a spike on the line.
  signal sync                   : std_logic;
  
  -- Bit time counter. This overflows exactly once every bit time, in the same
  -- phase where the bit would toggle.
  signal count                  : unsigned(2 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  --
  -- The following is a timing diagram of the synchronization system.
  --
  --        |                                                                 |
  --  clkEn |___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|_|
  --        |      _______________________________                            |
  --     rx |_____/                               \___________________________|
  --        |        _______________________________                          |
  --  sh(0) |_______/                               \_________________________|
  --        |                    _______________________________              |
  --  sh(3) |___________________/                               \_____________|
  --        |                    ___                             ___          |
  --   sync |___________________/   \___________________________/   \_________|
  --        |                                                                 |
  --  count |-----------U-----------|=4=|=5=|=6=|=7=|=0=|=1=|=2=|=3=|=4=|=5=|=|
  --        |                                                                 |
  --
  -- Majority voting is done when the bit counter reaches 7, based on the
  -- value at the following times within the bit.
  --
  --        |                                                                 |
  --  clkEn |___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|_|
  --        |                    _______________________________              |
  --  sh(3) |___________________/                ###            \_____________|
  --        |                        _______________________________          |
  --  sh(4) |_______________________/            ###                \_________|
  --        |                            _______________________________      |
  --  sh(5) |___________________________/        ###                    \_____|
  --        |                                    ___                          |
  -- sample |___________________________________/   \_________________________|
  --        |                                        ___                      |
  -- strobe |_______________________________________/   \_____________________|
  --        |                                                                 |
  --
  
  -- Generate the shift register and sync signal.
  shift_reg_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rxShiftReg <= (others => '1');
        sync <= '0';
      elsif clkEnBaud8 = '1' then
        
        -- Shift in the latest value.
        rxShiftReg <= rxShiftReg(4 downto 0) & rx;
        
        -- Detect edges when the signal has been stable for half a bit time.
        -- Send a sync pulse to the bit phase counter to synchronize it to
        -- halfway the bit transmission when an edge occurs.
        if ((rxShiftReg(2 downto 0) & rx = "1111") and (rxShiftReg(3) = '0'))   -- Rising edge.
          or ((rxShiftReg(2 downto 0) & rx = "0000") and (rxShiftReg(3) = '1')) -- Falling edge.
        then
          sync <= '1';
        else
          sync <= '0';
        end if;
        
      end if;
    end if;
  end process;
  
  -- Generate the bit phase counter and output signals.
  bit_phase: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        count <= (others => '0');
        data <= '0';
        strobe <= '0';
      elsif clkEnBaud8 = '1' then
        if sync = '1' then
          
          -- A sync pulse occurs in the middle of a bit, so set the counter
          -- to half its overflow value.
          count <= "100";
          
        else
          
          -- Increment the counter.
          count <= count + 1;
          
        end if;
        
        -- When the counter is at the end of a bit time, use a 5:1 majority
        -- vote on the values in the shift register to determine what the value
        -- of the bit was.
        if count = "111" then
          data <= MAJORITY_VOTE(vect2uint(rxShiftReg(5 downto 3)));
          strobe <= '1';
        else
          data <= '0';
          strobe <= '0';
        end if;
        
      end if;
    end if;
  end process;
  
end Behavioral;

