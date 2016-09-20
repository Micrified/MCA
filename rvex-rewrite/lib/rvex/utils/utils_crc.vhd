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
-- This module computes an N-bit CRC over N bits per cycle.
-------------------------------------------------------------------------------
entity utils_crc is
--=============================================================================
  generic (
    
    -- Size of the CRC in bits.
    CRC_ORDER                   : natural := 8;
    
    -- Polynomial in MSB-first representation.
    POLYNOMIAL                  : natural := 16#07#
    
    -- The default polynomial is CRC-8-CCITT.
    
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
    -- CRC interface
    ---------------------------------------------------------------------------
    -- Data to update the CRC with when update is high.
    data                        : in  std_logic_vector(CRC_ORDER-1 downto 0);
    
    -- When high, the CRC is updated with data.
    update                      : in  std_logic;
    
    -- When high, the CRC is reset to 0.
    clear                       : in  std_logic;
    
    -- Current CRC.
    crc                         : out std_logic_vector(CRC_ORDER-1 downto 0);
    
    -- This is high when the current CRC equals 0.
    correct                     : out std_logic
    
  );
end utils_crc;

--=============================================================================
architecture Behavioral of utils_crc is
--=============================================================================
  
  -- Current CRC register.
  signal currentCRC             : std_logic_vector(CRC_ORDER-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Generate CRC computation logic and register.
  crc_reg: process (clk) is
    variable crc_v  : std_logic_vector(CRC_ORDER-1 downto 0);
    variable b      : std_logic;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        currentCRC <= (others => '0');
      elsif clkEn = '1' then
        if clear = '1' then
          currentCRC <= (others => '0');
        elsif update = '1' then
          crc_v := currentCRC;
          for i in 7 downto 0 loop
            b := crc_v(CRC_ORDER-1);
            crc_v := crc_v(CRC_ORDER-2 downto 0) & "0";
            if data(i) = '1' then
              b := not b;
            end if;
            if b = '1' then
              crc_v := crc_v xor uint2vect(POLYNOMIAL, CRC_ORDER);
            end if;
          end loop;
          currentCRC <= crc_v;
        end if;
      end if;
    end if;
  end process;
  
  -- Connect output signals.
  crc <= currentCRC;
  correct <= '1' when vect2unsigned(currentCRC) = 0 else '0';
  
end Behavioral;

