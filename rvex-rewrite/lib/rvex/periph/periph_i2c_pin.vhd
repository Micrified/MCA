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
-- This is the I/O stage of the I2C peripheral. It primarily handles the
-- required glitch filter (min 50ns for fast-mode and fast-mode plus).
-------------------------------------------------------------------------------
entity periph_i2c_pin is
--=============================================================================
  generic (
    
    -- Clock frequency in kHz.
    CLK_KHZ                     : natural := 37500
    
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
    -- External pin
    ---------------------------------------------------------------------------
    -- Non-inverted pin input.
    pin_in                      : in  std_logic;
    
    -- Pin output enable. When high, the pin should be pulled low. When low,
    -- the driver should be turned off.
    pin_oen                     : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Input buffer status
    ---------------------------------------------------------------------------
    -- This signal is asserted for one cycle in the event of a rising edge on
    -- the pin.
    in_rise                     : out std_logic;
    
    -- This signal is asserted for one cycle in the event of a falling edge on
    -- the pin.
    in_fall                     : out std_logic;
    
    -- This signal returns the current (filtered) pin value.
    in_read                     : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Output driver control
    ---------------------------------------------------------------------------
    -- The pin is released (hi-Z) when this is signal high.
    out_release                 : in  std_logic;
    
    -- The pin is asserted (pulled low) when this signal is high.
    out_assert                  : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Output manual override
    ---------------------------------------------------------------------------
    -- Override enable signal. When high, pin_oen is set to ovr_oen.
    ovr_enable                  : in  std_logic;
    
    -- Override signal when ovr_oen is high.
    ovr_oen                     : in  std_logic
    
  );
end periph_i2c_pin;

--=============================================================================
architecture Behavioral of periph_i2c_pin is
--=============================================================================
  
  -- The filter must be 50ns minimum (1/50ns = 20000kHz).
  constant FILT_LEN : natural := CLK_KHZ / 20000;
  
  -- Input register in the IOBUF.
  signal pin_r      : std_logic;
  
  -- Second register, used to detect edges.
  signal pin_rr     : std_logic;
  
  -- Filter state. This is set to FILT_LEN when an edge is detected on the
  -- input and decremented downto zero otherwise. When it reaches zero, the
  -- filtered input register is updated.
  signal filter     : natural range 0 to FILT_LEN + 1;
  
  -- Filtered input register.
  signal in_read_i  : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Handle the input stage.
  input_proc: process (clk) is
  begin
    if rising_edge(clk) then
      pin_r <= pin_in;
      if reset = '1' then
        pin_rr <= '1';
        in_read_i <= '1';
        in_rise <= '0';
        in_fall <= '0';
      elsif clkEn = '1' then
        pin_rr <= pin_r;
        in_rise <= '0';
        in_fall <= '0';
        if pin_r /= pin_rr then
          filter <= FILT_LEN;
        elsif filter > 1 then
          filter <= filter - 1;
        else
          in_read_i <= pin_rr;
          in_rise <= pin_rr;
          in_fall <= not pin_rr;
        end if;
      end if;
    end if;
  end process;
  
  -- Forward the filtered input register value.
  in_read <= in_read_i;
  
  -- Handle the output stage.
  output_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        pin_oen_r <= '0';
      elsif clkEn = '1' then
        if out_release = '1' then
          pin_oen_r <= '0';
        elsif out_assert = '1' then
          pin_oen_r <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Forward the output enable signal.
  pin_oen <= pin_oen_r when ovr_enable = '0' else ovr_oen;
  
end Behavioral;

