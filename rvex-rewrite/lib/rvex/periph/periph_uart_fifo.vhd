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
use rvex.bus_pkg.all;

--=============================================================================
-- This unit represents a 16-byte deep, 8-bit wide FIFO buffer for use in the
-- UART peripheral.
-------------------------------------------------------------------------------
entity periph_uart_fifo is
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
    -- FIFO interface
    ---------------------------------------------------------------------------
    -- When pushStrobe is high, pushData will be pushed into the buffer. If the
    -- buffer is full, the data will be ignored, and the overflow strobe signal
    -- will go high for one cycle.
    pushData                    : in  std_logic_vector(7 downto 0);
    pushStrobe                  : in  std_logic;
    
    -- When popStrobe is high, popData will be updated to contain the next
    -- byte in the FIFO from the next cycle onwards. If popStrobe is asserted
    -- while the buffer is empty, underflow will be asserted for one cycle.
    popData                     : out std_logic_vector(7 downto 0);
    popStrobe                   : in  std_logic;
    
    -- The number of bytes currently in the buffer.
    count                       : out std_logic_vector(4 downto 0);
    
    -- The overflow and underflow signals will go high for one cycle when a
    -- push to a full buffer or a pop from an empty buffer is attempted,
    -- respectively.
    overflow                    : out std_logic;
    underflow                   : out std_logic
    
  );
end periph_uart_fifo;

--=============================================================================
architecture Behavioral of periph_uart_fifo is
--=============================================================================
  
  -- RAM backing the FIFO. This is intended to be instantiated as distributed
  -- memory on Xilinx FPGAs.
  subtype ram_entry_type is std_logic_vector(7 downto 0);
  type ram_type is array (natural range <>) of ram_entry_type;
  signal ram                    : ram_type(0 to 15);
  
  -- Read and write pointers.
  signal writePtr               : unsigned(3 downto 0);
  signal readPtr                : unsigned(3 downto 0);
  
  -- Maintains a count of the number of bytes in the FIFO.
  signal count_s                : unsigned(4 downto 0);
  
  -- Empty and full signals for the FIFO.
  signal empty                  : std_logic;
  signal full                   : std_logic;
  
  -- Actual push and pop signals, blocked when the buffer is full and empty
  -- respectively.
  signal push                   : std_logic;
  signal pop                    : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Generate combinatorial state signals.
  count     <= std_logic_vector(count_s);
  full      <= count_s(4);
  push      <= pushStrobe and not full;
  overflow  <= pushStrobe and full;
  empty     <= '1' when count_s = "00000" else '0';
  pop       <= popStrobe and not empty;
  underflow <= popStrobe and empty;
  
  -- Read/write pointer and byte count logic.
  pointer_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        writePtr <= (others => '0');
        readPtr <= (others => '0');
        count_s <= (others => '0');
      elsif clkEn = '1' then
        if push = '1' and pop = '1' then
          writePtr <= writePtr + 1;
          readPtr <= readPtr + 1;
        elsif push = '1' then
          writePtr <= writePtr + 1;
          count_s <= count_s + 1;
        elsif pop = '1' then
          readPtr <= readPtr + 1;
          count_s <= count_s - 1;
        end if;
      end if;
    end if;
  end process;
  
  -- Instantiate memory.
  memory_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if (clkEn and push) = '1' then
        ram(to_integer(writePtr)) <= pushData;
      end if;
      if (clkEn and pop) = '1' then
        popData <= ram(to_integer(readPtr));
      end if;
    end if;
  end process;
  
end Behavioral;
