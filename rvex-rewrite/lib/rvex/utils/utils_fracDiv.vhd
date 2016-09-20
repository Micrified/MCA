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

--=============================================================================
-- This unit emulates clock division using clkEn signals, allowing fractional
-- frequency division, such that the average apparent frequency closely
-- approximates the desired frequency, even if the input frequency is not an
-- integer multiple of the desired frequency.
-------------------------------------------------------------------------------
entity utils_fracDiv is
--=============================================================================
  generic (
    
    -- Input clock frequency.
    F_CLK                       : real;
    
    -- Desired apparent frequency.
    F_DESIRED                   : real;
    
    -- Maximum error in output frequency, represented as a fraction of the
    -- desired frequency, in percent.
    MAX_DEVIATION               : real := 0.01;
    
    -- Maximum width of the accumulator generated.
    MAX_ACCUM_SIZE              : natural := 16
    
  );
  port (
    
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input (may be used for cascading these
    -- dividers).
    clkEn_in                    : in  std_logic;
    
    -- Output clock enable signal.
    clkEn_out                   : out std_logic
    
  );
end utils_fracDiv;

--=============================================================================
architecture Behavioral of utils_fracDiv is
--=============================================================================
  
  -- Record containing divisor and multiplicant, so they can be computed by the
  -- same function.
  type divMul_type is record
    div : natural;
    mul : natural;
  end record;
  
  -- Generates the divisor and multiplier.
  function genDivMul return divMul_type is
    variable div        : natural;
    variable actual     : real;
    variable dev        : real;
    variable bestDev    : real;
    variable bestDiv    : natural;
    variable bestMul    : natural;
  begin
    
    -- Throw an error if the user is trying to increase the clock frequency.
    assert F_CLK >= F_DESIRED
      report "Input clock frequency must be higher than the desired frequency."
      severity failure;
    
    -- Set the best deviation we've seen so far to something terrible to begin
    -- with.
    bestDev := F_DESIRED;
    
    -- The loop boundaries here are insane. We should never get there though,
    -- because of the "exit when" and return statements.
    for mul in 1 to 2**MAX_ACCUM_SIZE loop
      
      -- Compute the best divider for this multiplier.
      div := integer(round((real(mul) * F_CLK) / F_DESIRED));
      
      -- Stop searching if div is out of range.
      exit when div + mul >= 2**MAX_ACCUM_SIZE;
      
      -- Compute actual frequency using the integer divider and multiplier.
      actual := F_CLK * real(mul) / real(div);
      
      -- Compute the difference between the desired and actual frequency.
      dev := abs(F_DESIRED - actual);
      
      -- If the actual frequency is within acceptable margins, return the
      -- current divider and multiplier.
      if dev <= F_DESIRED * MAX_DEVIATION / 100.0 then
        
        -- Report the computed clock information.
        report "Found division and multiplier constants to achieve "
             & real'image(F_DESIRED) & ": mul=" & integer'image(mul) & ", div="
             & integer'image(div) & ", actual=" & real'image(actual) & "Hz, "
             & "deviation=" & real'image((dev / F_DESIRED) * 100.0) & "%."
          severity note;
        
        -- Return the computed clock information.
        return (div => div, mul => mul);
        
      end if;
      
      -- Remember the best match.
      if dev < bestDev then
        bestDev := dev;
        bestDiv := div;
        bestMul := div;
      end if;
      
    end loop;
    
    -- Compute best-match actual frequency.
    actual := F_CLK * real(bestMul) / real(bestDiv);
    
    -- Report that we couldn't find a clock division which is in specs.
    report "Could not find division and multiplier constants to achieve clock "
         & "within the specified margins. Best clock was " & real'image(actual)
         & " Hz (mul=" & integer'image(bestMul) & ";div=" & integer'image(bestDiv)
         & "), which deviates " & real'image((dev / F_DESIRED) * 100.0) & "% "
         & "from desired frequency " & real'image(F_DESIRED) & "."
      severity failure;
    
    return (div => 0, mul => 0);
  end genDivMul;
  
  -- Computed divider and multiplier.
  constant DIV_MUL              : divMul_type := genDivMul;
  
  -- Determine the size in bits of the accumulator.
  constant ACCUM_SIZE           : natural := integer(ceil(log2(real(DIV_MUL.div + DIV_MUL.mul))));
  
  -- Accumulator signal.
  signal accum                  : unsigned(ACCUM_SIZE-1 downto 0) := (others => '0');
  
  -- Internal clkEn signal, to be gated by the incoming clkEn signal.
  signal clkEn_s                : std_logic := '0';
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Generate the clkEn_s signal.
  clken_gen: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        accum <= (others => '0');
        clkEn_s <= '1';
      elsif clkEn_in = '1' then
        if accum >= DIV_MUL.div then
          accum <= accum - to_unsigned(DIV_MUL.div - DIV_MUL.mul, ACCUM_SIZE);
          clkEn_s <= '1';
        else
          accum <= accum + to_unsigned(DIV_MUL.mul, ACCUM_SIZE);
          clkEn_s <= '0';
        end if;
      end if;
    end if;
  end process;
  
  -- Gate the internal clkEn_s signal with the incoming clkEn signal to drive
  -- clkEn_out.
  clkEn_out <= clkEn_s and clkEn_in;
  
end Behavioral;

