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

--=============================================================================
-- This is a raw UART block with baud rate generator, optional receiver and
-- optional transmitter.
-------------------------------------------------------------------------------
entity utils_uart is
--=============================================================================
  generic (
    
    -- Input clock frequency.
    F_CLK                       : real;
    
    -- Desired baud rate.
    F_BAUD                      : real := 115200.0;
    
    -- These flags can be used to disable the TX or RX stage. When disabled,
    -- associated I/O signals are unconnected.
    ENABLE_TX                   : boolean := true;
    ENABLE_RX                   : boolean := true
    
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
    -- External interface
    ---------------------------------------------------------------------------
    -- RX and TX pin for the UART.
    rx                          : in  std_logic := '0';
    tx                          : out std_logic;
    
    ---------------------------------------------------------------------------
    -- RX logic internal interface
    ---------------------------------------------------------------------------
    -- When data is received, rx_strobe is pulled high for one cycle while
    -- rx_data contains the received data and rx_frameError is valid. rx_data
    -- and rx_frameError are undefined while rx_strobe is low. rx_frameError
    -- being set means that the stop bit was not correctly received.
    rx_data                     : out std_logic_vector(7 downto 0);
    rx_frameError               : out std_logic;
    rx_strobe                   : out std_logic;
    
    -- When the line has been idle for a certain amount of time, this signal
    -- will go high. It may be used to signal a buffer flush.
    rx_charTimeout              : out std_logic;
    
    ---------------------------------------------------------------------------
    -- TX logic internal interface
    ---------------------------------------------------------------------------
    -- Data to transmit and strobe flag. When strobe is high and busy is low,
    -- the data in tx_data will be buffered and transmitted.
    tx_data                     : in  std_logic_vector(7 downto 0) := X"00";
    tx_strobe                   : in  std_logic := '0';
    
    -- Active high busy flag from the UART. While this is high, strobes will
    -- be ignored.
    tx_busy                     : out std_logic
    
  );
end utils_uart;

--=============================================================================
architecture Behavioral of utils_uart is
--=============================================================================
  
  -- Clock enable signal for UART logic. This is high for one cycle eight times
  -- for every UART bit time.
  signal clkEnBaud8             : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Generate the frequency generator
  -----------------------------------------------------------------------------
  baud_gen_inst: entity rvex.utils_fracDiv
    generic map (
      F_CLK                     => F_CLK,
      F_DESIRED                 => F_BAUD * 8.0
    )
    port map (
      reset                     => reset,
      clk                       => clk,
      clkEn_in                  => clkEn,
      clkEn_out                 => clkEnBaud8
    );
  
  -----------------------------------------------------------------------------
  -- Generate the receiver
  -----------------------------------------------------------------------------
  rx_gen: if ENABLE_RX generate
    signal rx_strobe_s  : std_logic;
  begin
    
    -- Instantiate the byte synchronization unit.
    rx_byte_inst: entity rvex.utils_uart_rxByte
      port map (
        reset                   => reset,
        clk                     => clk,
        clkEnBaud8              => clkEnBaud8,
        rx                      => rx,
        data                    => rx_data,
        frameError              => rx_frameError,
        strobe                  => rx_strobe_s,
        charTimeout             => rx_charTimeout
      );
    
    -- Gate the strobe signal with the clkEnBaud8 signal.
    rx_strobe <= rx_strobe_s and clkEnBaud8;
    
  end generate;
  
  -- Tie RX outputs to 0 when the RX part of the UART is not enabled.
  no_rx_gen: if not ENABLE_RX generate
    rx_data <= (others => '0');
    rx_frameError <= '0';
    rx_strobe <= '0';
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate the transmitter
  -----------------------------------------------------------------------------
  tx_gen: if ENABLE_TX generate
    signal tx_data_s            : std_logic_vector(7 downto 0);
    signal tx_start_s           : std_logic;
    signal tx_busy_s            : std_logic;
  begin
    
    -- Synchronize the incoming request with the clkEnBaud8 signal.
    process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
        elsif clkEn = '1' then
          if tx_strobe = '1' and tx_start_s = '0' and tx_busy_s = '0' then
            tx_data_s <= tx_data;
            tx_start_s <= '1';
          elsif clkEnBaud8 = '1' then
            tx_start_s <= '0';
          end if;
        end if;
      end if;
    end process;
    
    -- Instantiate the byte synchronization unit.
    tx_inst: entity rvex.utils_uart_tx
      port map (
        reset                   => reset,
        clk                     => clk,
        clkEnBaud8              => clkEnBaud8,
        tx                      => tx,
        data                    => tx_data_s,
        start                   => tx_start_s,
        busy                    => tx_busy_s
      );
    
    -- Generate the combined busy signal.
    tx_busy <= tx_start_s or tx_busy_s;
    
  end generate;
  
  -- Tie TX outputs to a reasonable state if the TX part of the UART is not
  -- enabled.
  no_tx_gen: if not ENABLE_TX generate
    tx <= '1';
    tx_busy <= '1';
  end generate;
  
end Behavioral;

