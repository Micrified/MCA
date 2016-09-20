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
-- This is part of the utils_uart entity. It handles UART transmission.
-------------------------------------------------------------------------------
entity utils_uart_tx is
--=============================================================================
  port (
    
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Clock enable signal which should be high for one cycle eight times per
    -- UART bit time.
    clkEnBaud8                  : in  std_logic;
    
    -- Transmit output.
    tx                          : out std_logic;
    
    -- Data input. When start is high while clkEnBaud8 is high and busy is low,
    -- the UART will begin to transmit data. data should remain valid while
    -- busy is high.
    data                        : in  std_logic_vector(7 downto 0);
    start                       : in  std_logic;
    busy                        : out std_logic
    
  );
end utils_uart_tx;

--=============================================================================
architecture Behavioral of utils_uart_tx is
--=============================================================================
  
  -- Bit (phase) counter. This counter is decremented every clkEnBaud8 cycle,
  -- thus every group of 8 contiguous values marks one bit. The following
  -- encoding is used:
  --  0000000 = idle (busy low)
  --  0000--- = stop
  --  0001--- = data bit 7
  --  0010--- = data bit 6
  --  0011--- = data bit 5
  --  0100--- = data bit 4
  --  0101--- = data bit 3
  --  0110--- = data bit 2
  --  0111--- = data bit 1
  --  1000--- = data bit 0
  --  1001--- = start
  signal counter                : unsigned(6 downto 0);
  
  -- Local signal for the busy output.
  signal busy_s                 : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Instantiate the counter logic.
  counter_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        counter <= (others => '0');
      elsif clkEnBaud8 = '1' then
        if busy_s = '1' then
          counter <= counter - 1;
        elsif start = '1' then
          counter <= "1001111";
        end if;
      end if;
    end if;
  end process;
  
  -- Generate the busy output.
  busy_s <= '0' when counter = "0000000" else '1';
  busy <= busy_s;
  
  -- Drive the output. Use a register without reset and clkEn so it can be
  -- absorbed into the output buffer.
  tx_output_proc: process (clk) is
  begin
    if rising_edge(clk) then
      case counter(6 downto 3) is
        when "0000" => tx <= '1';
        when "0001" => tx <= data(7);
        when "0010" => tx <= data(6);
        when "0011" => tx <= data(5);
        when "0100" => tx <= data(4);
        when "0101" => tx <= data(3);
        when "0110" => tx <= data(2);
        when "0111" => tx <= data(1);
        when "1000" => tx <= data(0);
        when "1001" => tx <= '0';
        when others => tx <= '1';
      end case;
    end if;
  end process;
  
end Behavioral;

