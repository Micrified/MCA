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
-- pragma translate_off
use rvex.simUtils_pkg.all;
-- pragma translate_on

-- pragma translate_off
library std;
use std.textio.all;
-- pragma translate_on

--=============================================================================
-- This unit interfaces between a slave bus interface and a UART. It contains
-- a 16-byte FIFO for receive and transmit data, and an appropriate interrupt
-- interface, similar to the legacy 16550 UART IC.
-------------------------------------------------------------------------------
entity periph_uart_busIface is
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
    -- Slave bus
    ---------------------------------------------------------------------------
    -- The UART has three available registers, mapped at the following
    -- addresses.
    --
    -- Address                                 Name
    -- =====================================   ====
    -- 0b--------_--------_--------_----0000   data
    -- 0b--------_--------_--------_----0100   stat
    -- 0b--------_--------_--------_----1000   ctrl
    --
    -- All registers are 8 bit. They have the following fields.
    --
    --            |--7--|--6--|--5--|--4--|--3--|--2--|--1--|--0--|
    --   data (r) |                      RXD                      |
    --            |-----|-----|-----|-----|-----|-----|-----|-----|
    --   data (w) |                      TXD                      |
    --            |-----|-----|-----|-----|-----|-----|-----|-----|
    --   stat (r) |  -  |  -  | ROV | CTI |RXDR | TOV |TXDR |TXDE |
    --            |-----|-----|-----|-----|-----|-----|-----|-----|
    --   stat (w) |  -  |  -  |ROVC |CTIC |  -  |TOVC |  -  |  -  |
    --            |-----|-----|-----|-----|-----|-----|-----|-----|
    -- ctrl (r/w) |   RXTL    |ROVE |CTIE |RXDRE|TOVE |TXDRE|TXDEE|
    --            |-----|-----|-----|-----|-----|-----|-----|-----|
    --
    --   RXD - RX data. When read, the topmost byte is popped off of the
    --         receive buffer and is returned. When the buffer is empty, the
    --         returned value is undefined.
    -- 
    --   TXD - TX data. When written, the written byte is pushed onto the
    --         transmit buffer if room is available. If the buffer is full, the
    --         byte is discarded.
    --
    --  TXDE - TX data register empty. When this flag is set, the transmit FIFO
    -- TXDEE   is empty. When TXDEE is set, an interrupt is requested when this
    --         is the case.
    -- 
    --  TXDR - TX data register ready. When this flag is set, the transmit FIFO
    -- TXDRE   is not full and thus ready for new data. When TXDRE is set, an
    --         interrupt is requested when this is the case.
    -- 
    --   TOV - This flag is set when the application wrote to TXD while the
    --  TOVC   buffer was full. Writing a 1 to TOVC clears this flag. When TOVE
    --  TOVE   is set, an interrupt is requested when TOV is high.
    -- 
    --  RXDR - RX data ready. This flag is set when there are at least as much
    -- RXDRE   characters in the receive buffer as specified by RXTL. When
    --         RXDRE is set, an interrupt is requested when this is the case.
    -- 
    --   CTI - Character timeout interrupt. This flag is set when the receive
    --  CTIC   FIFO is nonempty while the UART RX line has been idle for at
    --  CTIE   least one character time.  The flag is cleared by writing a 1 to
    --         CTIC. When CTIE is set, an interrupt is requested when CTI is
    --         high. It may be used in conjunction with RXDR and RXTL to
    --         correctly finish reading incoming data packets which are not a
    --         multiple of the value specified by RXTL.
    -- 
    --   ROV - This flag is set when an incoming byte is discarded because the
    --  ROVC   receive buffer is full. Writing a 1 to ROVC clears this flag.
    --  ROVE   When TOVE is set, an interrupt is requested when ROV is high.
    --
    --  RXTL - RX trigger level. This controls when RXDR is set. The following
    --         encoding is used.
    --           00 => At least 1 character is present in the RX FIFO.
    --           01 => At least 4 characters are present in the RX FIFO.
    --           10 => At least 8 characters are present in the RX FIFO.
    --           11 => At least 14 characters are present in the RX FIFO.
    -- 
    -- NOTE: all of the above registers operate on the UART bytestream as made
    -- visible to the application, which is NOT the actual raw UART stream.
    -- Characters sent by the application may be escaped to allow unique
    -- control characters to be sent over the UART, and debug packets are
    -- injected into the stream as well. All this is done transparently
    -- however; the receiver performs the inverse operation.
    
    -- Slave bus port.
    bus2uart                    : in  bus_mst2slv_type;
    uart2bus                    : out bus_slv2mst_type;
    
    -- Active high interrupt request output.
    irq                         : out std_logic;
    
    ---------------------------------------------------------------------------
    -- UART data inferface
    ---------------------------------------------------------------------------
    -- Received data and strobe signal. When strobe is high, rxData is valid
    -- and should be put in the FIFO.
    rxData                      : in  std_logic_vector(7 downto 0);
    rxStrobe                    : in  std_logic;
    
    -- When the line has been idle for a certain amount of time, this signal
    -- will go high. It may be used to signal a buffer flush.
    rxTimeout                   : in  std_logic;
    
    -- Transmit data and strobe output. When txBusy is low, txSrobe may be
    -- brought high for one cycle, in which txData must be valid, in order to
    -- transmit a byte.
    txData                      : out std_logic_vector(7 downto 0);
    txStrobe                    : out std_logic;
    txBusy                      : in  std_logic
    
  );
end periph_uart_busIface;

--=============================================================================
architecture Behavioral of periph_uart_busIface is
--=============================================================================
  
  -- Bus-side FIFO access port signals.
  signal txPushData             : std_logic_vector(7 downto 0);
  signal txPushStrobe           : std_logic;
  signal rxPopData              : std_logic_vector(7 downto 0);
  signal rxPopStrobe            : std_logic;
  
  -- FIFO states.
  signal txCount                : std_logic_vector(4 downto 0);
  signal rxCount                : std_logic_vector(4 downto 0);
  
  -- TX strobe signal.
  signal txStrobe_s             : std_logic;
  signal txStrobe_r             : std_logic;
  
  -- RX trigger level register.
  signal rxTriggerLevel         : std_logic_vector(1 downto 0);
  
  -- Interrupt bit IDs, flags and enable registers.
  constant TXDE_BIT             : natural := 0;
  constant TXDR_BIT             : natural := 1;
  constant TOV_BIT              : natural := 2;
  constant RXDR_BIT             : natural := 3;
  constant CTI_BIT              : natural := 4;
  constant ROV_BIT              : natural := 5;
  signal interruptFlags         : std_logic_vector(5 downto 0);
  signal interruptEnable        : std_logic_vector(5 downto 0);
  
  -- TX buffer overflow flag register signals.
  signal txOverflowSet          : std_logic;
  signal txOverflowClr          : std_logic;
  
  -- RX buffer overflow flag register signals.
  signal rxOverflowSet          : std_logic;
  signal rxOverflowClr          : std_logic;
  
  -- CTI flag register signals.
  signal ctiClr                 : std_logic;
  
  -- Part of the bus address which is used to select between registers, delayed
  -- by one cycle to match up with the read data.
  signal busReadMux             : std_logic_vector(3 downto 2);
  
  -- Bus acknowledge signal, which is simply (readEnable or writeEnable)
  -- delayed by one cycle.
  signal busAck                 : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Instantiate the RX FIFO.
  rx_fifo: entity rvex.periph_uart_fifo
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- FIFO interface.
      pushData                  => rxData,
      pushStrobe                => rxStrobe,
      popData                   => rxPopData,
      popStrobe                 => rxPopStrobe,
      count                     => rxCount,
      overflow                  => rxOverflowSet,
      underflow                 => open
      
    );
  
  -- Instantiate the TX FIFO.
  tx_fifo: entity rvex.periph_uart_fifo
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- FIFO interface.
      pushData                  => txPushData,
      pushStrobe                => txPushStrobe,
      popData                   => txData,
      popStrobe                 => txStrobe_s,
      count                     => txCount,
      overflow                  => txOverflowSet,
      underflow                 => open
      
    );
  
  -- Generate the TX strobe signal. When the UART becomes ready and there is
  -- data in the buffer, we first send the pop request, and then send the
  -- strobe to the UART the next cycle.
  txStrobe_s <= (not txBusy) and (not txStrobe_r) when txCount /= "00000" else '0';
  process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        txStrobe_r <= '0';
      elsif clkEn = '1' then
        txStrobe_r <= txStrobe_s;
      end if;
    end if;
  end process;
  txStrobe <= txStrobe_r;
  
  -- Generate the interrupt flag set-reset registers, for the interrupts flags
  -- which are not generated combinatorially.
  int_flag_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        interruptFlags(TOV_BIT) <= '0';
        interruptFlags(ROV_BIT) <= '0';
        interruptFlags(CTI_BIT) <= '0';
      elsif clkEn = '1' then
        if txOverflowSet = '1' then
          interruptFlags(TOV_BIT) <= '1';
        elsif txOverflowClr = '1' then
          interruptFlags(TOV_BIT) <= '0';
        end if;
        if rxOverflowSet = '1' then
          interruptFlags(ROV_BIT) <= '1';
        elsif rxOverflowClr = '1' then
          interruptFlags(ROV_BIT) <= '0';
        end if;
        if (rxTimeout = '1') and (rxCount /= "00000") then
          interruptFlags(CTI_BIT) <= '1';
        elsif ctiClr = '1' then
          interruptFlags(CTI_BIT) <= '0';
        end if;
      end if;
    end if;
  end process;
  
  -- Generate the combinatorial interrupt flags for the transmit FIFO.
  interruptFlags(TXDE_BIT) <= '1' when txCount = "00000" else '0';
  interruptFlags(TXDR_BIT) <= not txCount(4);
  
  -- Generate the combinatorial interrupt flag for the receive FIFO.
  rxdr_flag_proc: process (rxCount, rxTriggerLevel) is
    variable decodedLevel : unsigned(4 downto 0);
  begin
    case rxTriggerLevel is
      when "00"   => decodedLevel := "00001";
      when "01"   => decodedLevel := "00100";
      when "10"   => decodedLevel := "01000";
      when others => decodedLevel := "01110";
    end case;
    if unsigned(rxCount) >= decodedLevel then
      interruptFlags(RXDR_BIT) <= '1';
    else
      interruptFlags(RXDR_BIT) <= '0';
    end if;
  end process;
  
  -- Generate the IRQ signal.
  irq_gen: process (interruptFlags, interruptEnable) is
    variable irq_v  : std_logic;
  begin
    irq_v := '0';
    for i in interruptFlags'range loop
      irq_v := irq_v or (interruptFlags(i) and interruptEnable(i));
    end loop;
    irq <= irq_v;
  end process;
  
  -- Generate combinatorial signals based upon the bus request.
  txPushData
    <= bus2uart.writeData(31 downto 24);
  
  txPushStrobe
    <= bus2uart.writeEnable and bus2uart.writeMask(3)
    when bus2uart.address(3 downto 2) = "00" else '0';
  
  rxPopStrobe
    <= bus2uart.readEnable
    when bus2uart.address(3 downto 2) = "00" else '0';
  
  txOverflowClr
    <= bus2uart.writeEnable and bus2uart.writeMask(3)
    and bus2uart.writeData(24 + TOV_BIT)
    when bus2uart.address(3 downto 2) = "01" else '0';
  
  rxOverflowClr
    <= bus2uart.writeEnable and bus2uart.writeMask(3)
    and bus2uart.writeData(24 + ROV_BIT)
    when bus2uart.address(3 downto 2) = "01" else '0';
  
  ctiClr
    <= bus2uart.writeEnable and bus2uart.writeMask(3)
    and bus2uart.writeData(24 + CTI_BIT)
    when bus2uart.address(3 downto 2) = "01" else '0';
  
  -- Generate registers based upon the bus request.
  bus_req_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        busAck <= '0';
        busReadMux <= (others => '0');
        rxTriggerLevel <= (others => '0');
        interruptEnable <= (others => '0');
      elsif clkEn = '1' then
        busAck <= bus_requesting(bus2uart);
        busReadMux <= bus2uart.address(3 downto 2);
        if bus2uart.address(3 downto 2) = "10" then
          if bus2uart.writeEnable = '1' and bus2uart.writeMask(3) = '1' then
            rxTriggerLevel <= bus2uart.writeData(31 downto 30);
            interruptEnable <= bus2uart.writeData(29 downto 24);
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generate the bus reply signal.
  bus_reply_proc: process (
    busAck, busReadMux, rxPopData,
    rxTriggerLevel, interruptFlags, interruptEnable
  ) is
  begin
    uart2bus <= BUS_SLV2MST_IDLE;
    case busReadMux is
      when "00"   => uart2bus.readData <= rxPopData & X"000000";
      when "01"   => uart2bus.readData <= "00" & interruptFlags & X"000000";
      when "10"   => uart2bus.readData <= rxTriggerLevel & interruptEnable & X"000000";
      when others => uart2bus.readData <= X"00000000";
    end case;
    uart2bus.ack <= busAck;
  end process;
  
  -- Simulation only: dump things transmitted by the application to the
  -- simulation console.
  -- pragma translate_off
  sim_print: process is
    variable c  : character;
    variable l  : std.textio.line;
  begin
    l := null;
    loop
      wait until rising_edge(clk);
      if reset = '0' and clkEn = '1' and txPushStrobe = '1' then
        c := character'val(to_integer(unsigned(txPushData)));
        if c = LF then
          if l = null then
            dumpStdOut("Application UART: ");
          else
            dumpStdOut("Application UART: " & l.all);
            deallocate(l);
            l := null;
          end if;
        else
          write(l, c);
        end if;
      end if;
    end loop;
  end process;
  -- pragma translate_on
  
end Behavioral;
