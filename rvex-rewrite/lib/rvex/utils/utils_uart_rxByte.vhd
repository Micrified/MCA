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
-- This is part of the utils_uart entity. It handles byte synchronization for
-- an 8N1 UART bitstream.
-------------------------------------------------------------------------------
entity utils_uart_rxByte is
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
    
    -- Received byte output. When strobe is high, data and frameError are
    -- valid. Data contains the byte received, and frameError is set when the
    -- stop bit is not high as expected.
    data                        : out std_logic_vector(7 downto 0);
    frameError                  : out std_logic;
    strobe                      : out std_logic;
    
    -- When the line has been idle for a certain amount of time, this signal
    -- will go high. It may be used to signal a buffer flush.
    charTimeout                 : out std_logic
    
  );
end utils_uart_rxByte;

--=============================================================================
architecture Behavioral of utils_uart_rxByte is
--=============================================================================
  
  -- Bitstream from the bit synchronization unit. When strobe is high, data
  -- contains the received bit.
  signal bitData                : std_logic;
  signal bitStrobe              : std_logic;
  
  -- Bit counter. 0 is idle or the start bit, 1 is data bit 0, 8 is data bit 7,
  -- 9 is the stop bit.
  signal bitCount               : unsigned(3 downto 0);
  
  -- Character timeout timer. This will be incremented by bitStrobe while
  -- bitCount is zero and be reset when bitCount is nonzero (note that
  -- bitStrobe will keep running at the local baud rate generator speed even
  -- when the line is idle).
  signal timeoutCounter         : unsigned(2 downto 0);
  
  -- Shift register containing the 9 last received bits, such that it contains
  -- the received data in 7..0 and the stop bit in 8 when bitCount rolls over.
  signal shiftReg               : std_logic_vector(8 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  --        |                                                                 |
  -- bitStr |___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|___|_|
  --        |_______     _______                         _____________________|
  -- bitDat |       \_S_/ 0   1 \_2___3___4___5___6___7_/ P                   |
  --        |                                                                 |
  --  count |=====0=====|=1=|=2=|=3=|=4=|=5=|=6=|=7=|=8=|=9=|========0========|
  --        |___________________________________________     _______          |
  --  sh(0) |                                           \_S_/#0#  1 \_2___3___|
  --        |___________________________________     _______                  |
  --  sh(2) |                                   \_S_/ 0   1 \#2#__3___4___5___|
  --        |___________     _______                         _________________|
  --  sh(8) |           \_S_/ 0   1 \_2___3___4___5___6___7_/#P#              |
  --        |                                                ___              |
  -- strobe |_______________________________________________/   \_____________|
  --        |                                                                 |
  --        |                                                                 |
  
  -- Instantiate the bit synchronization/receiver unit.
  rx_bit_inst: entity rvex.utils_uart_rxBit
    port map (
      reset                     => reset,
      clk                       => clk,
      clkEnBaud8                => clkEnBaud8,
      rx                        => rx,
      data                      => bitData,
      strobe                    => bitStrobe
    );
  
  -- Instantiate the bit counter, shift register and strobe signal generation.
  fsm_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        bitCount <= (others => '0');
        shiftReg <= (others => '1');
        timeoutCounter <= (others => '1');
        charTimeout <= '1';
      elsif clkEnBaud8 = '1' then
        
        -- Only update the counter and shift register when we get a new bit.
        if bitStrobe = '1' then
          
          -- Generate the bit counter.
          case bitCount is
            when "0000" => bitCount <= "000" & not bitData;
            when "1001" => bitCount <= "0000";
            when others => bitCount <= bitCount + 1;
          end case;
          
          -- Generate the shift register.
          shiftReg <= bitData & shiftReg(8 downto 1);
          
          -- Generate the character timeout signal.
          if bitCount /= "0000" then
            timeoutCounter <= "000";
            charTimeout <= '0';
          elsif timeoutCounter = "111" then
            charTimeout <= '1';
          else
            timeoutCounter <= timeoutCounter + 1;
            charTimeout <= '0';
          end if;
          
        end if;
        
        -- Strobe is high the bit time after count is 9.
        if bitCount = "1001" and bitStrobe = '1' then
          strobe <= '1';
        else
          strobe <= '0';
        end if;
        
      end if;
    end if;
  end process;
  
  -- Tie the outputs to the shift register such that they are valid while
  -- strobe is high.
  data        <= shiftReg(7 downto 0);
  frameError  <= not shiftReg(8);
  
end Behavioral;

