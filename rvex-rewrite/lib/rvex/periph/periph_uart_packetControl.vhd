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
-- pragma translate_off
--use rvex.simUtils_pkg.all;
-- pragma translate_on

--=============================================================================
-- This is is part of the debug section of the UART peripheral. It buffers and
-- error-checks incoming debug packets and buffers and transmits outgoing
-- debug packets. In order to be able to error-check packets, this unit appends
-- an 8-bit CRC to every transmitted packet and checks and removes the CRC from
-- received packets. When a packet with an incorrect CRC is received, it is
-- discarded.
-------------------------------------------------------------------------------
entity periph_uart_packetControl is
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
    -- Interface with the packet handler
    ---------------------------------------------------------------------------
    -- Received packet buffer interface. When pop is high, the next byte in
    -- the buffer is selected. If no more bytes are available, empty is
    -- asserted high instead.
    pkctrl2pkhan_rxData         : out std_logic_vector(7 downto 0);
    pkhan2pkctrl_rxPop          : in  std_logic;
    pkctrl2pkhan_rxEmpty        : out std_logic;
    
    -- When high, the next packet is requested.
    pkctrl2pkhan_rxSwap         : in  std_logic;
    
    -- When high, a packet has been received and is available in the buffer.
    pkhan2pkctrl_rxReady        : out std_logic;
    
    -- Reply packet buffer interface. When push is high, data is pushed into
    -- the buffer, unless the buffer is full (in which was full will have been
    -- asserted high.
    pkhan2pkctrl_txData         : in  std_logic_vector(7 downto 0);
    pkhan2pkctrl_txPush         : in  std_logic;
    pkctrl2pkhan_txFull         : out std_logic;
    
    -- When high, the transmit buffer is reset/cleared.
    pkctrl2pkhan_txReset        : in  std_logic;
    
    -- When high, the packet currently in the transmit buffer will be
    -- transmitted.
    pkctrl2pkhan_txSwap         : in  std_logic;
    
    -- When high, the transmit buffer is ready for writing.
    pkhan2pkctrl_txReady        : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Interface with UART stream switch
    ---------------------------------------------------------------------------
    -- When rxStrobe is high, rxData and rxEndPacket are valid. When
    -- rxEndPacket is low, rxData contains a received byte. When rxEndPacket is
    -- high, rxData is invalid, but this rxStrobe marks the end of the packet
    -- which was being received.
    sw2pkctrl_rxData            : in  std_logic_vector(7 downto 0);
    sw2pkctrl_rxEndPacket       : in  std_logic;
    sw2pkctrl_rxStrobe          : in  std_logic;
    
    -- When txRequest is high, the UART switch should send txData. When
    -- txStartPacket is high as well, the UART switch should ensure that it is
    -- clear to the receiver that a new packet has started. When the UART
    -- switch services the request, txAck should be asserted high for one
    -- cycle.
    pkctrl2sw_txData            : out std_logic_vector(7 downto 0);
    pkctrl2sw_txStartPacket     : out std_logic;
    pkctrl2sw_txRequest         : out std_logic;
    sw2pkctrl_txAck             : in  std_logic
    
  );
end periph_uart_packetControl;

--=============================================================================
architecture Behavioral of periph_uart_packetControl is
--=============================================================================
  
  -- CRC polynomial to use for the packets, in MSB-first representation.
  constant CRC_POLYNOMIAL       : natural := 16#07#;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Receiver logic
  -----------------------------------------------------------------------------
  rx_block: block is
    
    -- TX buffer busy signal, inverted txReady signal.
    signal pkhan2pkctrl_rxBusy  : std_logic;
    
    -- This flag is cleared when a new packet is going to be received, and is
    -- set whenever a byte is received while the buffer was not ready.
    signal bufferError          : std_logic;
    
    -- Buffer error signals.
    signal bufferFull           : std_logic;
    signal bufferSwapping       : std_logic;
    
    -- This is set when the crc over the entire packet received so far equals
    -- zero.
    signal crcCorrect           : std_logic;
    
    -- This is set while bufferError is cleared and crcCorrect is set.
    signal packetValid          : std_logic;
    
    -- When completePacket is high for one cycle, the packet currently in the
    -- buffer is either forwarded to the packet handler or discarded, based on
    -- the packetValid signal. forwardPacket and discardPacket are simply the
    -- same signal, but appropriately gated by the packetValid signal.
    signal completePacket       : std_logic;
    signal forwardPacket        : std_logic;
    signal discardPacket        : std_logic;
    
    -- Strobe signal, only going high when the incoming strobe signal is high
    -- and endPacket is low.
    signal rxStrobeData         : std_logic;
    
  begin
    
    -- Instantiate the transmit packet buffer.
    rx_packet_buffer_inst: entity rvex.periph_uart_packetBuffer
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Buffer write interface.
        src2buf_data            => sw2pkctrl_rxData,
        src2buf_push            => rxStrobeData,
        bus2src_full            => bufferFull,
        src2buf_pop             => forwardPacket, -- The last byte is the CRC, which the packet handler doesn't need.
        src2buf_reset           => discardPacket,
        src2buf_swap            => forwardPacket,
        bus2src_swapping        => bufferSwapping,
        
        -- Buffer read interface.
        buf2sink_data           => pkctrl2pkhan_rxData,
        sink2buf_pop            => pkhan2pkctrl_rxPop,
        buf2sink_empty          => pkctrl2pkhan_rxEmpty,
        sink2buf_swap           => pkctrl2pkhan_rxSwap,
        bus2sink_swapping       => pkhan2pkctrl_rxBusy
        
      );
    
    -- Invert the busy signal to get the ready signal.
    pkhan2pkctrl_rxReady <= not pkhan2pkctrl_rxBusy;
    
    -- CRC generator for the transmitted packets.
    rx_crc_inst: entity rvex.utils_crc
      generic map (
        CRC_ORDER               => 8,
        POLYNOMIAL              => CRC_POLYNOMIAL
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- CRC interface.
        data                    => sw2pkctrl_rxData,
        update                  => rxStrobeData,
        clear                   => completePacket,
        crc                     => open,
        correct                 => crcCorrect
        
      );
    
--    -- pragma translate_off
--    process (clk) is
--    begin
--      if rising_edge(clk) then
--        if rxStrobeData = '1' then
--          dumpStdOut(
--            "                                                                  "
--            & "Debug command " & rvs_hex(sw2pkctrl_rxData)
--          );
--        end if;
--        if forwardPacket = '1' then
--          dumpStdOut(
--            "                                                                  "
--            & "Handling command."
--          );
--        end if;
--        if discardPacket = '1' then
--          dumpStdOut(
--            "                                                                  "
--            & "Discarding command."
--          );
--        end if;
--      end if;
--    end process;
--    -- pragma translate_on
    
    -- Instantiate the buffer error register.
    rx_buf_error_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          bufferError <= '0';
        elsif clkEn = '1' then
          if completePacket = '1' then
            bufferError <= '0';
          elsif (sw2pkctrl_rxStrobe = '1') and (bufferFull = '1' or bufferSwapping = '1') then
            bufferError <= '1';
          end if;
        end if;
      end if;
    end process;
    
    -- Determine whether the packet as we have received it so far is valid.
    packetValid <= crcCorrect and not bufferError;
    
    -- Whenever we get a received byte strobe while endPacket is high, we must
    -- either forward or discard the current packet.
    completePacket <= sw2pkctrl_rxStrobe and sw2pkctrl_rxEndPacket;
    
    -- Whenever we get a received byte strobe while endPacket is low, put it
    -- in the receive buffer.
    rxStrobeData <= sw2pkctrl_rxStrobe and not sw2pkctrl_rxEndPacket;
    
    -- Determine whether we should forward or discard.
    forwardPacket <= completePacket and packetValid; 
    discardPacket <= completePacket and not packetValid;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Transmitter logic
  -----------------------------------------------------------------------------
  tx_block: block is
    
    -- TX buffer busy signal, inverted txReady signal.
    signal pkhan2pkctrl_txBusy  : std_logic;
    
    -- FSM state. In COMMAND, the first byte from the packet buffer is sent.
    -- The remainder of the data bytes is sent in PAYLOAD. In CRC, the CRC of
    -- the packet is sent. Finally, in WAIT, the transmit buffer is swapped.
    type state_type is (STATE_WAIT, STATE_COMMAND, STATE_PAYLOAD);
    signal state                : state_type;
    signal state_next           : state_type;
    
    -- Data from the transmit buffer.
    signal bufData              : std_logic_vector(7 downto 0);
    
    -- When high, the transmit buffer pops a byte and the next byte is
    -- presented on bufData.
    signal bufPop               : std_logic;
    
    -- After popping, this signals that the buffer is empty.
    signal bufEmpty             : std_logic;
    
    -- CRC from the CRC generator.
    signal crc                  : std_logic_vector(7 downto 0);
    
    -- Pulling swap high requests a transmit buffer swap. swapping will be high
    -- while the swap is in progress (i.e., the buffer is waiting for new
    -- data).
    signal swap                 : std_logic;
    signal swapping             : std_logic;
    
  begin
    
    -- Instantiate the transmit packet buffer.
    tx_packet_buffer_inst: entity rvex.periph_uart_packetBuffer
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Buffer write interface.
        src2buf_data            => pkhan2pkctrl_txData,
        src2buf_push            => pkhan2pkctrl_txPush,
        bus2src_full            => pkctrl2pkhan_txFull,
        src2buf_pop             => '0',
        src2buf_reset           => pkctrl2pkhan_txReset,
        src2buf_swap            => pkctrl2pkhan_txSwap,
        bus2src_swapping        => pkhan2pkctrl_txBusy,
        
        -- Buffer read interface.
        buf2sink_data           => bufData,
        sink2buf_pop            => bufPop,
        buf2sink_empty          => bufEmpty,
        sink2buf_swap           => swap,
        bus2sink_swapping       => swapping
        
      );
    
    -- Invert the busy signal to get the ready signal.
    pkhan2pkctrl_txReady <= not pkhan2pkctrl_txBusy;
    
    -- CRC generator for the transmitted packets.
    tx_crc_inst: entity rvex.utils_crc
      generic map (
        CRC_ORDER               => 8,
        POLYNOMIAL              => CRC_POLYNOMIAL
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- CRC interface.
        data                    => bufData,
        update                  => bufPop,
        clear                   => swap,
        crc                     => crc,
        correct                 => open
        
      );
    
    -- Select the data to transmit.
    pkctrl2sw_txData <= bufData when bufEmpty = '0' else crc;
    
    -- Instantiate the state register.
    tx_fsm_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          state <= STATE_WAIT;
        elsif clkEn = '1' then
          state <= state_next;
        end if;
      end if;
    end process;
    
    -- Instantiate the combinatorial state logic.
    tx_fsm_comb: process (
      state, swapping, sw2pkctrl_txAck, bufEmpty
    ) is
    begin
      
      -- Set default values.
      state_next <= state;
      pkctrl2sw_txStartPacket <= '0';
      pkctrl2sw_txRequest <= '0';
      bufPop <= '0';
      swap <= '0';
      
      -- Handle the state.
      case state is
        
        when STATE_WAIT =>
          if swapping = '0' then
            state_next <= STATE_COMMAND;
          end if;
          
        when STATE_COMMAND =>
          
          -- Request transfer of the first byte in the packet.
          pkctrl2sw_txStartPacket <= '1';
          pkctrl2sw_txRequest <= '1';
          
          if sw2pkctrl_txAck = '1' then
            if bufEmpty = '0' then
              
              -- Go to the next byte.
              bufPop <= '1';
              state_next <= STATE_PAYLOAD;
              
            else
              
              -- Swap the buffer.
              swap <= '1';
              state_next <= STATE_WAIT;
              
            end if;
          end if;
          
        when STATE_PAYLOAD =>
          
          -- Request transfer of the next byte in the packet.
          pkctrl2sw_txRequest <= '1';
        
          if sw2pkctrl_txAck = '1' then
            if bufEmpty = '0' then
              
              -- Go to the next byte.
              bufPop <= '1';
              
            else
              
              -- Swap the buffer.
              swap <= '1';
              state_next <= STATE_WAIT;
              
            end if;
          end if;
          
      end case;
      
    end process;
    
  end block;
  
end Behavioral;

