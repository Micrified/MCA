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
-- Synchronization state machine for clock domain crossings.
-------------------------------------------------------------------------------
entity utils_sync is
--=============================================================================
  generic (
    
    -- Number of delay cycles in the synchronization system.
    NUM_STAGES                  : positive := 2
    
  );
  port (
    
    -- Active high asynchronous reset input for the synchronization logic. This
    -- must be released a couple cycles before the master starts sending
    -- requests, or it can be left disconnected.
    reset                       : in  std_logic := '0';
    
    -- Clock input, registers are rising edge triggered.
    a_clk                       : in  std_logic;
    b_clk                       : in  std_logic;
    
    -- Active high global clock enable input.
    a_clkEn                     : in  std_logic := '1';
    b_clkEn                     : in  std_logic := '1';
    
    -- This is high when the associated domain is in control of the cross-clock
    -- data signals (external to this unit): the signals from the other side
    -- are stable and the signals from this side may be modified. After reset,
    -- domain A is in control.
    a_inControl                 : out std_logic;
    b_inControl                 : out std_logic;
    
    -- When the associated side is in control and is done processing, it should
    -- assert the release signal for one clk-enabled cycle.
    a_release                   : in  std_logic;
    b_release                   : in  std_logic
    
  );
end utils_sync;

--=============================================================================
architecture Behavioral of utils_sync is
--=============================================================================
  
  -- Lock state machine states.
  subtype state_t is std_logic_vector(1 downto 0);
  constant WAIT_0               : state_t := "00";
  constant CONTROL_0            : state_t := "01";
  constant WAIT_1               : state_t := "10";
  constant CONTROL_1            : state_t := "11";
  signal a_state                : state_t := CONTROL_0;
  signal b_state                : state_t := WAIT_0;
  
  -- Synchronization shift registers.
  subtype sync_t is std_logic_vector(NUM_STAGES-1 downto 0);
  signal a_sync                 : sync_t;
  signal b_sync                 : sync_t;
  
begin
  
  -- Clock domain A.
  a_regs: process (reset, a_clk) is
  begin
    if reset = '1' then
      a_state <= CONTROL_0;
      a_sync <= (others => '0');
    elsif rising_edge(a_clk) then
      if a_clkEn = '1' then
        
        -- FSM.
        if a_state(0) = '0' then
          
          -- Waiting for the other sync signal.
          if a_sync(0) = a_state(1) then
            a_state(0) <= not a_state(0);
          end if;
          
        else
          
          -- In control, waiting to be released.
          if a_release = '1' then
            a_state(0) <= not a_state(0);
            a_state(1) <= not a_state(1);
          end if;
          
        end if;
        
        -- Sync shift register.
        a_sync <= b_state(1 downto 1) & a_sync(NUM_STAGES-1 downto 1);
        
      end if;
    end if;
  end process;
  
  -- Forward the in-control bit of the state.
  a_inControl <= a_state(0);
  
  -- Clock domain B.
  b_regs: process (reset, b_clk) is
  begin
    if reset = '1' then
      b_state <= WAIT_0;
      b_sync <= (others => '0');
    elsif rising_edge(b_clk) then
      if b_clkEn = '1' then
        
        -- FSM.
        if b_state(0) = '0' then
          
          -- Waiting for the other sync signal.
          if b_sync(0) = not b_state(1) then
            b_state(0) <= not b_state(0);
          end if;
          
        else
          
          -- In control, waiting to be released.
          if b_release = '1' then
            b_state(0) <= not b_state(0);
            b_state(1) <= not b_state(1);
          end if;
          
        end if;
        
        -- Sync shift register.
        b_sync <= a_state(1 downto 1) & b_sync(NUM_STAGES-1 downto 1);
        
      end if;
    end if;
  end process;
  
  -- Forward the in-control bit of the state.
  b_inControl <= b_state(0);
  
end Behavioral;

