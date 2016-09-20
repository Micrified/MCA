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

--=============================================================================
-- This testbench instantiates and provides stimuli for utils_uart for manual
-- verification.
-------------------------------------------------------------------------------
entity utils_uart_tb is
end utils_uart_tb;
-------------------------------------------------------------------------------
architecture Behavioral of utils_uart_tb is
--=============================================================================
  
  type rxResult_type is record
    data                        : std_logic_vector(7 downto 0);
    error                       : std_logic;
    valid                       : std_logic;
  end record;
  
  signal result1                : rxResult_type;
  signal result2                : rxResult_type;
  signal result3                : rxResult_type;
  
  signal sim_result1            : rxResult_type;
  signal sim_result2            : rxResult_type;
  signal sim_result3            : rxResult_type;
  
  signal rx, tx                 : std_logic;
  
  signal clk                    : std_logic;
  signal reset                  : std_logic;
  signal tx_data                : std_logic_vector(7 downto 0);
  signal tx_strobe              : std_logic;
  signal tx_busy                : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Generate unit under test 1.
  uut1: entity rvex.utils_uart
    generic map (
      F_CLK                     => 10000000.0,
      F_BAUD                    => 115200.0,
      ENABLE_TX                 => true,
      ENABLE_RX                 => true
    )
    port map (
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      rx                        => rx,
      rx_data                   => result1.data,
      rx_frameError             => result1.error,
      rx_strobe                 => result1.valid,
      
      tx                        => tx,
      tx_data                   => tx_data,
      tx_strobe                 => tx_strobe,
      tx_busy                   => tx_busy
    );
  
  -- Generate unit under test 2. This is just a receiver listening to uut1,
  -- having a frequency mismatch.
  uut2: entity rvex.utils_uart
    generic map (
      F_CLK                     => 10000000.0,
      F_BAUD                    => 109785.6, -- Notice misalignment here; 4.7% lower frequency.
      ENABLE_TX                 => false,
      ENABLE_RX                 => true
    )
    port map (
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      rx                        => rx,
      rx_data                   => result2.data,
      rx_frameError             => result2.error,
      rx_strobe                 => result2.valid
    );
  
  -- Generate unit under test 3. Same as 2, but with a frequency mismatch in
  -- the other direction.
  uut3: entity rvex.utils_uart
    generic map (
      F_CLK                     => 10000000.0,
      F_BAUD                    => 120614.4, -- Notice misalignment here; 4.7% higher frequency.
      ENABLE_TX                 => false,
      ENABLE_RX                 => true
    )
    port map (
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      rx                        => rx,
      rx_data                   => result3.data,
      rx_frameError             => result3.error,
      rx_strobe                 => result3.valid
    );
  
  -- Delay the UART transmission line a bit.
  rx <= tx after 123456 ps;
  
  -- Generate result signals for simulation. We set the invalid signals to Z
  -- to make it easily visible when a UART is receiving something.
  process is
  begin
    sim_result1.data <= "ZZZZZZZZ";
    sim_result1.error <= 'Z';
    sim_result1.valid <= '1';
    loop
      wait until rising_edge(clk) and result1.valid = '1';
      sim_result1.data <= "ZZZZZZZZ";
      sim_result1.error <= 'Z';
      wait for 1 ns;
      sim_result1.data <= result1.data;
      sim_result1.error <= result1.error;
    end loop;
  end process;
  
  process is
  begin
    sim_result2.data <= "ZZZZZZZZ";
    sim_result2.error <= 'Z';
    sim_result2.valid <= '1';
    loop
      wait until rising_edge(clk) and result2.valid = '1';
      sim_result2.data <= "ZZZZZZZZ";
      sim_result2.error <= 'Z';
      wait for 1 ns;
      sim_result2.data <= result2.data;
      sim_result2.error <= result2.error;
    end loop;
  end process;
  
  process is
  begin
    sim_result3.data <= "ZZZZZZZZ";
    sim_result3.error <= 'Z';
    sim_result3.valid <= '1';
    loop
      wait until rising_edge(clk) and result3.valid = '1';
      sim_result3.data <= "ZZZZZZZZ";
      sim_result3.error <= 'Z';
      wait for 1 ns;
      sim_result3.data <= result3.data;
      sim_result3.error <= result3.error;
    end loop;
  end process;
  
  -- Generate clock.
  process is
  begin
    clk <= '1';
    wait for 50 ns;
    clk <= '0';
    wait for 50 ns;
  end process;
  
  -- Generate stimuli.
  process is
    procedure transmit(data: std_logic_vector) is
    begin
      wait until rising_edge(clk) and tx_busy = '0';
      tx_strobe <= '1';
      tx_data <= data;
      wait until rising_edge(clk);
      tx_strobe <= '0';
      tx_data <= (others => 'U');
    end transmit;
  begin
    reset <= '1';
    tx_strobe <= '0';
    tx_data <= (others => 'U');
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    reset <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    transmit(X"03");
    transmit(X"55");
    transmit(X"AA");
    transmit(X"FF");
    wait;
  end process;
  
end Behavioral;

