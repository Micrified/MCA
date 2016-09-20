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
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.bus_pkg.all;

--=============================================================================
-- This is is part of the debug section of the UART peripheral. It handles
-- debug packets by initiating the requested bus transfers.
--
-------------------------------------------------------------------------------
-- Packet format
-------------------------------------------------------------------------------
-- Each packet (request and reply) starts with a command byte with the
-- following format.
-- 
-- |-7-|-6-|-5-|-4-|-3-|-2-|-1-|-0-|
-- |    Command    |   Sequence    |
-- |---|---|---|---|---|---|---|---|
-- 
-- The sequence number is not used by the packet handler, and is simply copied
-- into the reply packet. The PC may use this in order to be able to send more
-- than one request before receiving a reply; using the sequence number it will
-- be able to identify which commands (if any) need to be resent.
-- 
-- The command field determines how the device should handle the packet. has
-- the following encoding. This field is also copied into the reply packet
-- unchanged.
-- 
--   0000 => reserved for version information
--   0001 => reserved
--   0010 => reserved
--   0011 => reserved
--   0100 => reserved
--   0101 => reserved
--   0110 => reserved
--   0111 => reserved
--   1000 => reserved
--   1001 => reserved
--   1010 => set bulk write page
--   1011 => bulk write
--   1100 => bulk read
--   1101 => prepare volatile bus op
--   1110 => perform volatile bus op
--   1111 => reserved (might require transmission of escape character for
--           command byte)
-- 
-- The function of the remainder of the bytes depends on the command code, as
-- follows.
-- 
-- Packet 0000..1001 and 1111:
--   Payload from computer is ignored, no payload is sent in the reply.
-- 
-- Packet 1010 - set bulk write page:
--   Payload from computer should be 3 bytes, containing bits 31 downto 8 of
--   the address in big endian notation. The Bits 11 downto 8 are essentially
--   ignored, because they are overridden by bulk write commands.
-- 
-- Packet 1011 - bulk write:
--   Payload from the computer should be 5-29 bytes. The first byte sets the
--   address: bits 31 downto 12 are unchanged, whereas bits 11 downto 0 are set
--   to the byte value * 28. The remainder of the payload is interpreted as 
--   words which are to be written to the memory, starting at the initial
--   address. This means that with 146 packets with payload size 29 and 1
--   packet with payload size 9, a 4kb page can be written, with potentially
--   out-of-order packets due to packet loss. The fault flag from the bus is
--   ignored though, and due to retransmission, it is possible that data is
--   written to the bus multiple times. A bulk write cannot cross a 4kb
--   boundary.
-- 
-- Packet 1100 - bulk read:
--   Payload from the computer should be 5 bytes. The first four bytes should
--   specify the initial address in big-endian order. The fifth byte should 
--   be set to what the LSB of the address will be when the bulk read should
--   stop. This must be at most the LSB of the initial address + 28 and at
--   least LSB + 4. Note that both start and non-inclusive end address should
--   be aligned to four bytes.
-- 
-- Packet 1101 - prepare volatile bus operation:
--   Payload from the computer should be 9 bytes. The first four bytes should
--   specify the address to operate on, the next four bytes should specify the
--   write data as it will be written to the bus, and the final byte specifies
--   (from MSB to LSB) the four write mask flags, the read/write (0 for read,
--   1 for write) and three pad bits which are reserved and should be zero.
--   All this command does is store these values in a register and set a valid
--   flag.
-- 
-- Packet 1110 - execute volatile bus operation:
--   No payload is required. When this command is executed while the valid flag
--   set by packet 1101 is still set, the valid flag is cleared, the bus
--   operation is performed, and the holding registers are overwritten with the
--   bus result (read data and fault flag). Regardless of the initial state of
--   the valid flag, this command will return the contents of the holding
--   registers containing the read data (first 4 bytes) and the fault flag
--   (sent in 1 byte as 0 or 1, the remainder of the bits are reserved).
--
-- To perform a volatile bus operation, one would first send packet 1101 until
-- the packet is successfully acknowledged, after which packet 1110 is sent
-- until that packet is successfully acknowledged. When this completes, it is
-- guaranteed that the bus operation is performed exactly once. If the retry
-- count is exceeded for the ack for packet 1101 it is guaranteed that no
-- operation has been performed yet. Only if the connection is interrrupted
-- after packet 1110 has already been sent will the state of the system be
-- unknown to the computer.
-- 
-------------------------------------------------------------------------------
entity periph_uart_packetHandler is
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
    -- Interface with packet control
    ---------------------------------------------------------------------------
    -- Received packet buffer interface. When pop is high, the next byte in
    -- the buffer is selected. If no more bytes are available, empty is
    -- asserted high instead.
    pkctrl2pkhan_rxData         : in  std_logic_vector(7 downto 0);
    pkhan2pkctrl_rxPop          : out std_logic;
    pkctrl2pkhan_rxEmpty        : in  std_logic;
    
    -- When high, the next packet is requested.
    pkctrl2pkhan_rxSwap         : out std_logic;
    
    -- When high, a packet has been received and is available in the buffer.
    pkhan2pkctrl_rxReady        : in  std_logic;
    
    -- Reply packet buffer interface. When push is high, data is pushed into
    -- the buffer, unless the buffer is full (in which was full will have been
    -- asserted high.
    pkhan2pkctrl_txData         : out std_logic_vector(7 downto 0);
    pkhan2pkctrl_txPush         : out std_logic;
    pkctrl2pkhan_txFull         : in  std_logic;
    
    -- When high, the transmit buffer is reset/cleared.
    pkctrl2pkhan_txReset        : out std_logic;
    
    -- When high, the packet currently in the transmit buffer will be
    -- transmitted.
    pkctrl2pkhan_txSwap         : out std_logic;
    
    -- When high, the transmit buffer is ready for writing.
    pkhan2pkctrl_txReady        : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Bus interface
    ---------------------------------------------------------------------------
    -- This is the bus which is controlled by the debug packets.
    pkhan2dbg_bus               : out bus_mst2slv_type;
    dbg2pkhan_bus               : in  bus_slv2mst_type
    
  );
end periph_uart_packetHandler;

--=============================================================================
architecture Behavioral of periph_uart_packetHandler is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Command code constants
  -----------------------------------------------------------------------------
  constant COMCODE_SET_PAGE         : std_logic_vector(3 downto 0) := "1010";
  constant COMCODE_BULK_WRITE       : std_logic_vector(3 downto 0) := "1011";
  constant COMCODE_BULK_READ        : std_logic_vector(3 downto 0) := "1100";
  constant COMCODE_VOLATILE_PREPARE : std_logic_vector(3 downto 0) := "1101";
  constant COMCODE_VOLATILE_EXECUTE : std_logic_vector(3 downto 0) := "1110";
  
  -----------------------------------------------------------------------------
  -- Datapath control signals
  -----------------------------------------------------------------------------
  -- These control signals are driven by the FSM based on the state.
  
  -- Address register operations.
  type addressOp_type is (
    ADDR_OP_NOP,                -- No operation
    ADDR_OP_WRITE_0,            -- addr(31..24) = rxbuf
    ADDR_OP_WRITE_1,            -- addr(23..16) = rxbuf
    ADDR_OP_WRITE_2,            -- addr(15..8) = rxbuf
    ADDR_OP_WRITE_3,            -- addr(7..0) = rxbuf
    ADDR_OP_STOP_3,             -- stopAddr(7..0) = rxbuf
    ADDR_OP_AUTO_INC,           -- addr(11..0) = align4(addr(11..0) + 4)
    ADDR_OP_LOAD_MULT_7         -- addr(11..0) = rxbuf * 28
  );
  signal addressOp              : addressOp_type;
  
  -- Write data and mask register operations.
  type writeDataOp_type is (
    WDAT_OP_NOP,                -- No operation
    WDAT_OP_WRITE_0,            -- writeData(31..24) = rxbuf; writeMask(3) = 0
    WDAT_OP_WRITE_1,            -- writeData(23..16) = rxbuf; writeMask(2) = 0
    WDAT_OP_WRITE_2,            -- writeData(15..8) = rxbuf; writeMask(1) = 0
    WDAT_OP_WRITE_3,            -- writeData(7..0) = rxbuf; writeMask(0) = 0
    WDAT_OP_LOAD_MASK           -- writeMask(3..0) = rxbuf(7..0)
  );
  signal writeDataOp            : writeDataOp_type;
  
  -- Write/read enable and busRequestValid register operations. When
  -- transferComplete is set, all these operations are overridden to clearing
  -- all the flags.
  type enableOp_type is (
    ENABLE_OP_NOP,              -- No operation
    ENABLE_OP_WRITE,            -- Set write enable register
    ENABLE_OP_READ,             -- Set read enable register
    ENABLE_OP_QUEUE             -- writeEnable = rxBuf(3); readEnable = not rxBuf(3); busRequestValid = '1'
  );
  signal enableOp               : enableOp_type;
  
  -- Combinatorial bus operation. When transferComplete is set, this is
  -- overridden to BUS_OP_NOP.
  type busOp_type is (
    BUS_OP_NOP,                 -- No operation
    BUS_OP_EXECUTE              -- Execute the queued bus operation
  );
  signal busOp                  : busOp_type;
  
  -- Transmit packet buffer push operation.
  type txBufOp_type is (
    TXBUF_OP_NOP,               -- No operation
    TXBUF_OP_ECHO,              -- Push rxbuf into txbuf
    TXBUF_OP_PUSH_READ_0,       -- Push readData(31..24) into txbuf
    TXBUF_OP_PUSH_READ_1,       -- Push readData(23..16) into txbuf
    TXBUF_OP_PUSH_READ_2,       -- Push readData(15..8) into txbuf
    TXBUF_OP_PUSH_READ_3,       -- Push readData(7..0) into txbuf
    TXBUF_OP_PUSH_FLAGS         -- Push "0000000" & fault into txbuf
  );
  signal txBufOp                : txBufOp_type;
  
  -- Receive packet buffer pop operation.
  type rxBufOp_type is (
    RXBUF_OP_NOP,               -- No operation
    RXBUF_OP_POP                -- Pop byte from receive buffer
  );
  signal rxBufOp                : rxBufOp_type;
  
  -- Packet operation.
  type packetOp_type is (
    PACKET_OP_NOP,              -- No operation
    PACKET_OP_NEXT              -- Send the packet currently in the transmit buffer and request a new packet
  );
  signal packetOp               : packetOp_type;
  
  -- Command code operation.
  type commandCodeOp_type is (
    COMCODE_OP_NOP,             -- No operation; forward registered code
    COMCODE_OP_STORE            -- comCode = rxBuf(7..4)
  );
  signal commandCodeOp          : commandCodeOp_type;
  
  -----------------------------------------------------------------------------
  -- Datapath status signals
  -----------------------------------------------------------------------------
  -- These signals are generated by the datapath block for the FSM.
  
  -- Command code, valid only when the first byte is presented by the packet
  -- receive buffer.
  signal commandCode            : std_logic_vector(3 downto 0);
  
  -- Set when the packet receive buffer is empty.
  signal rxEmpty                : std_logic;
  
  -- Set when a bulk read should stop (i.e. when the stop address has been
  -- reached).
  signal bulkReadStop           : std_logic;
  
  -- Set when both the packet receive and transmit buffers are ready (this is
  -- only cleared while either buffer is swapping).
  signal packetReady            : std_logic;
  
  -- Set when a bus operation is queued by a "prepare volatile" command,
  -- cleared when the prepared operation has already been performed.
  signal busOpQueued            : std_logic;
  
  -- Set when the bus operation requested through 
  signal busOpComplete          : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Datapath
  -----------------------------------------------------------------------------
  datapath_block: block is
    
    -- Command code register.
    signal commandCode_r        : std_logic_vector(3 downto 0);
    
    -- Bus request and reply registers.
    signal busRequest_r         : bus_mst2slv_type;
    signal busResult_r          : bus_slv2mst_type;
    
    -- Relevant part of the address which is used to detect when a bulk read
    -- should stop.
    signal stopAddress_r        : std_logic_vector(4 downto 2);
    
    -- Volatile bus request flag. Set by the prepare command, cleared when a
    -- bus transfer completes.
    signal busRequestValid_r    : std_logic;
    
  begin
    
    -- Instantiate the registers.
    datapath_regs: process (clk) is
      
      -- Address adder inputs and output.
      variable addressAddOp1    : std_logic_vector(10 downto 0);
      variable addressAddOp2    : std_logic_vector(10 downto 0);
      variable addressAddResult : std_logic_vector(10 downto 0);
      
    begin
      if rising_edge(clk) then
        if reset = '1' then
          commandCode_r <= (others => '0');
          busRequest_r <= BUS_MST2SLV_IDLE;
          busResult_r <= BUS_SLV2MST_IDLE;
          stopAddress_r <= (others => '0');
          busRequestValid_r <= '0';
        elsif clkEn = '1' then
          
          -- Handle command code register
          -- ----------------------------
          
          -- Store the command code when requested.
          case commandCodeOp is
            when COMCODE_OP_NOP   => null;
            when COMCODE_OP_STORE => commandCode_r <= pkctrl2pkhan_rxData(7 downto 4);
          end case;
          
          
          -- Handle bus address register
          -- ---------------------------
          
          -- Prepare the operands for the addition.
          if addressOp = ADDR_OP_LOAD_MULT_7 then
            addressAddOp1 := pkctrl2pkhan_rxData & "001";     -- rxbuf*8 + 1
            addressAddOp2 := "111" & not pkctrl2pkhan_rxData; -- ~rxbuf = -1 - rxbuf
            -- Result
            --  = op1 + op2
            --  = (rxbuf*8 + 1) + (-1 - rxbuf)
            --  = rxbuf*8 - rxbuf
            --  = rxbuf*7
          else
            addressAddOp1 := "0" & busRequest_r.address(11 downto 2);
            addressAddOp2 := "00000000001";
            -- Result = addr(11..2) + 1
          end if;
          
          -- Perform the addition.
          addressAddResult := std_logic_vector(
            vect2unsigned(addressAddOp1) + vect2unsigned(addressAddOp2)
          );
          
          -- Determine the next value for the address register.
          case addressOp is
            when ADDR_OP_NOP      => null;
            when ADDR_OP_WRITE_0  => busRequest_r.address(31 downto 24) <= pkctrl2pkhan_rxData;
            when ADDR_OP_WRITE_1  => busRequest_r.address(23 downto 16) <= pkctrl2pkhan_rxData;
            when ADDR_OP_WRITE_2  => busRequest_r.address(15 downto 8) <= pkctrl2pkhan_rxData;
            when ADDR_OP_WRITE_3  => busRequest_r.address(7 downto 0) <= pkctrl2pkhan_rxData;
            when ADDR_OP_STOP_3   => stopAddress_r(4 downto 2) <= pkctrl2pkhan_rxData(4 downto 2);
            when others           => busRequest_r.address(11 downto 0) <= addressAddResult(9 downto 0) & "00";
          end case;
          
          
          -- Handle write data operation
          -- ---------------------------
          
          -- Determine the next value for the write data register.
          case writeDataOp is
            when WDAT_OP_WRITE_0  => busRequest_r.writeData(31 downto 24) <= pkctrl2pkhan_rxData;
            when WDAT_OP_WRITE_1  => busRequest_r.writeData(23 downto 16) <= pkctrl2pkhan_rxData; 
            when WDAT_OP_WRITE_2  => busRequest_r.writeData(15 downto 8) <= pkctrl2pkhan_rxData;
            when WDAT_OP_WRITE_3  => busRequest_r.writeData(7 downto 0) <= pkctrl2pkhan_rxData;
            when others           => null;
          end case;
          
          -- Determine the next value for the write mask register.
          case writeDataOp is
            when WDAT_OP_WRITE_0  => busRequest_r.writeMask(3) <= '1';
            when WDAT_OP_WRITE_1  => busRequest_r.writeMask(2) <= '1';
            when WDAT_OP_WRITE_2  => busRequest_r.writeMask(1) <= '1';
            when WDAT_OP_WRITE_3  => busRequest_r.writeMask(0) <= '1';
            when WDAT_OP_LOAD_MASK=> busRequest_r.writeMask <= pkctrl2pkhan_rxData(7 downto 4);
            when others           => null;
          end case;
          
          -- Override the write mask to zero when the bus transfer is complete.
          if busOpComplete = '1' then
            busRequest_r.writeMask <= "0000";
          end if;
          
          
          -- Handle enable operation
          -- -----------------------
          
          -- Determine the next value for the flags.
          case enableOp is
            when ENABLE_OP_NOP =>
              null;
              
            when ENABLE_OP_WRITE =>
              busRequest_r.writeEnable <= '1';
              busRequest_r.readEnable <= '0';
              
            when ENABLE_OP_READ =>
              busRequest_r.writeEnable <= '0';
              busRequest_r.readEnable <= '1';
              
            when ENABLE_OP_QUEUE  => 
              busRequest_r.writeEnable <= pkctrl2pkhan_rxData(3);
              busRequest_r.readEnable <= not pkctrl2pkhan_rxData(3);
              busRequestValid_r <= '1';
              
          end case;
          
          -- Override the flags to zero when the bus transfer is complete.
          if busOpComplete = '1' then
            busRequest_r.writeEnable <= '0';
            busRequest_r.readEnable <= '0';
            busRequestValid_r <= '0';
          end if;
          
          
          -- Handle read results
          -- -------------------
          
          -- Copy the bus result into the registers when the bus transfer
          -- completes.
          if busOpComplete = '1' then
            busResult_r <= dbg2pkhan_bus;
          end if;
          
        end if;
      end if;
    end process;
    
    
    -- Drive external output signals
    -- -----------------------------
    
    -- Determine the bus request output.
    bus_request_proc: process (busOp, busOpComplete, busRequest_r) is
      variable gate               : std_logic;
    begin
      
      -- Determine whether we should execute the bus request.
      case busOp is
        when BUS_OP_NOP     => gate := '0';
        when BUS_OP_EXECUTE => gate := not busOpComplete;
      end case;
      
      -- Gate the bus registers.
      pkhan2dbg_bus <= bus_gate(busRequest_r, gate);
      
    end process;
    
    -- Determine the next operation for the transmit buffer.
    tx_buf_push_proc: process (txBufOp, pkctrl2pkhan_rxData, busResult_r) is
    begin
      
      -- Set defaults for the output signals.
      pkhan2pkctrl_txData   <= pkctrl2pkhan_rxData;
      pkhan2pkctrl_txPush   <= '1';
      pkctrl2pkhan_txReset  <= '0';
      
      -- Override with the correct requests where necessary.
      case txBufOp is
        when TXBUF_OP_NOP         => pkhan2pkctrl_txPush <= '0';
        when TXBUF_OP_ECHO        => pkhan2pkctrl_txData <= pkctrl2pkhan_rxData;
        when TXBUF_OP_PUSH_READ_0 => pkhan2pkctrl_txData <= busResult_r.readData(31 downto 24);
        when TXBUF_OP_PUSH_READ_1 => pkhan2pkctrl_txData <= busResult_r.readData(23 downto 16);
        when TXBUF_OP_PUSH_READ_2 => pkhan2pkctrl_txData <= busResult_r.readData(15 downto 8);
        when TXBUF_OP_PUSH_READ_3 => pkhan2pkctrl_txData <= busResult_r.readData(7 downto 0);
        when TXBUF_OP_PUSH_FLAGS  => pkhan2pkctrl_txData <= "0000000" & busResult_r.fault;
      end case;
      
    end process;
    
    -- Determine the next operation for the receive buffer.
    pkhan2pkctrl_rxPop <= '1' when rxBufOp = RXBUF_OP_POP else '0';
    
    -- Swap the packet buffers when requested.
    pkctrl2pkhan_txSwap <= '1' when packetOp = PACKET_OP_NEXT else '0';
    pkctrl2pkhan_rxSwap <= '1' when packetOp = PACKET_OP_NEXT else '0';
    
    
    -- Drive status signals
    -- --------------------
    
    -- Drive the commandCode signal.
    commandCode
      <= pkctrl2pkhan_rxData(7 downto 4) when commandCodeOp = COMCODE_OP_STORE
      else commandCode_r;
    
    -- Drive local packet receive buffer empty signal.
    rxEmpty <= pkctrl2pkhan_rxEmpty;
    
    -- Drive bulk read stop signal high when the significant part of the
    -- current address matches the stop address.
    bulkReadStop
      <= '1' when stopAddress_r = busRequest_r.address(stopAddress_r'range)
      else '0';
    
    -- Drive the packetReady signal.
    packetReady <= pkhan2pkctrl_rxReady and pkhan2pkctrl_txReady;
    
    -- Drive the bus op queued signal.
    busOpQueued <= busRequestValid_r;
    
    -- The busOpComplete signal is simply the ack signal from the bus.
    busOpComplete <= dbg2pkhan_bus.ack;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Packet handler state machine
  -----------------------------------------------------------------------------
  packet_handler_fsm: block is
    
    -- FSM state.
    type state_type is (
      
      -- Waits for the packet buffers to become ready.
      STATE_WAIT,
      
      -- Decodes the command byte and pushes it into the transmit buffer.
      STATE_DECODE,
      
      -- Sets the address register.
      STATE_SET_ADDRESS_0, STATE_SET_ADDRESS_1,
      STATE_SET_ADDRESS_2, STATE_SET_ADDRESS_3,
      
      -- Sets the stop address for reads.
      STATE_SET_STOP_ADDRESS,
      
      -- Sets the address based on page index for bulk writes.
      STATE_SET_PAGE_INDEX,
      
      -- Sets the write data register.
      STATE_SET_WRITE_DATA_0, STATE_SET_WRITE_DATA_1,
      STATE_SET_WRITE_DATA_2, STATE_SET_WRITE_DATA_3,
      
      -- Sets the bus request flags for a volatile bus operation.
      STATE_SET_VOLATILE_FLAGS,
      
      -- Performs the prepared bus operation.
      STATE_BUS_OP,
      
      -- Determines what to do after a bus operation.
      STATE_BUS_OP_COMPLETE,
      
      -- These states push the read data into the TX buffer.
      STATE_PUSH_READ_DATA_0, STATE_PUSH_READ_DATA_1,
      STATE_PUSH_READ_DATA_2, STATE_PUSH_READ_DATA_3,
      
      -- This state pushes the bus result flags into the TX buffer.
      STATE_PUSH_RESULT_FLAGS
      
    );
    signal state                : state_type;
    signal state_next           : state_type;
    
  begin
    
    -- Instantiate the state register for the FSM.
    fsm_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          state <= STATE_WAIT;
        elsif clkEn = '1' then
          state <= state_next;
        end if;
      end if;
    end process;
    
    -- Combinatorial logic for the FSM.
    fsm_comb: process (
      commandCode, rxEmpty, bulkReadStop, packetReady, busOpQueued,
      busOpComplete, state
    ) is
    begin
      
      -- Load default values.
      addressOp     <= ADDR_OP_NOP;
      writeDataOp   <= WDAT_OP_NOP;
      enableOp      <= ENABLE_OP_NOP;
      busOp         <= BUS_OP_NOP;
      txBufOp       <= TXBUF_OP_NOP;
      rxBufOp       <= RXBUF_OP_NOP;
      packetOp      <= PACKET_OP_NOP;
      commandCodeOp <= COMCODE_OP_NOP;
      state_next    <= state;
      
      -- Act based upon the state.
      case state is
        
        -----------------------------------------------------------------------
        when STATE_WAIT => 
          
          -- Wait for the packet buffers to be ready.
          if packetReady = '1' then
            state_next <= STATE_DECODE;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_DECODE =>
          
          -- Copy the command/sequence byte into the transmit buffer.
          txBufOp <= TXBUF_OP_ECHO;
          rxBufOp <= RXBUF_OP_POP;
          
          -- Store the command code.
          commandCodeOp <= COMCODE_OP_STORE;
          
          -- Determine the next state.
          case commandCode is
            
            when COMCODE_SET_PAGE =>
              state_next <= STATE_SET_ADDRESS_0;
              
            when COMCODE_BULK_WRITE =>
              state_next <= STATE_SET_PAGE_INDEX;
              
            when COMCODE_BULK_READ =>
              state_next <= STATE_SET_ADDRESS_0;
              
            when COMCODE_VOLATILE_PREPARE =>
              state_next <= STATE_SET_ADDRESS_0;
              
            when COMCODE_VOLATILE_EXECUTE =>
              if busOpQueued = '1' then
                state_next <= STATE_BUS_OP;
              else
                state_next <= STATE_PUSH_READ_DATA_0;
              end if;
              
            when others =>
              
              -- Handle reserved commands by sending an empty reply packet.
              packetOp <= PACKET_OP_NEXT;
              state_next <= STATE_WAIT;
              
          end case;
          
        -----------------------------------------------------------------------
        when STATE_SET_ADDRESS_0 =>
          addressOp <= ADDR_OP_WRITE_0;
          rxBufOp <= RXBUF_OP_POP;
          state_next <= STATE_SET_ADDRESS_1;
          
        -----------------------------------------------------------------------
        when STATE_SET_ADDRESS_1 =>
          addressOp <= ADDR_OP_WRITE_1;
          rxBufOp <= RXBUF_OP_POP;
          state_next <= STATE_SET_ADDRESS_2;
          
        -----------------------------------------------------------------------
        when STATE_SET_ADDRESS_2 =>
          addressOp <= ADDR_OP_WRITE_2;
          rxBufOp <= RXBUF_OP_POP;
          
          -- We're done if this was a set page command, otherwise continue.
          if commandCode = COMCODE_SET_PAGE then
            packetOp <= PACKET_OP_NEXT;
            state_next <= STATE_WAIT;
          else
            state_next <= STATE_SET_ADDRESS_3;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_SET_ADDRESS_3 =>
          addressOp <= ADDR_OP_WRITE_3;
          rxBufOp <= RXBUF_OP_POP;
          
          -- If we're preparing a volatile bus operation, continue by storing
          -- the write data. Otherwise we're doing a bulk read, so continue by
          -- storing the stop address byte.
          if commandCode = COMCODE_VOLATILE_PREPARE then
            state_next <= STATE_SET_WRITE_DATA_0;
          else
            state_next <= STATE_SET_STOP_ADDRESS;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_SET_STOP_ADDRESS =>
          addressOp <= ADDR_OP_STOP_3;
          rxBufOp <= RXBUF_OP_POP;
          
          -- We only ever get to this state in the bulk read command, so
          -- it's time to execute the first read now.
          enableOp <= ENABLE_OP_READ;
          state_next <= STATE_BUS_OP;
          
        -----------------------------------------------------------------------
        when STATE_SET_PAGE_INDEX =>
          addressOp <= ADDR_OP_LOAD_MULT_7;
          rxBufOp <= RXBUF_OP_POP;
          
          -- We only ever get to this state in the bulk write command, in which
          -- case we continue by setting up the write data.
          state_next <= STATE_SET_WRITE_DATA_0;
          
        -----------------------------------------------------------------------
        when STATE_SET_WRITE_DATA_0 =>
          writeDataOp <= WDAT_OP_WRITE_0;
          rxBufOp <= RXBUF_OP_POP;
          state_next <= STATE_SET_WRITE_DATA_1;
          
        -----------------------------------------------------------------------
        when STATE_SET_WRITE_DATA_1 =>
          writeDataOp <= WDAT_OP_WRITE_1;
          rxBufOp <= RXBUF_OP_POP;
          state_next <= STATE_SET_WRITE_DATA_2;
          
        -----------------------------------------------------------------------
        when STATE_SET_WRITE_DATA_2 =>
          writeDataOp <= WDAT_OP_WRITE_2;
          rxBufOp <= RXBUF_OP_POP;
          state_next <= STATE_SET_WRITE_DATA_3;
          
        -----------------------------------------------------------------------
        when STATE_SET_WRITE_DATA_3 =>
          writeDataOp <= WDAT_OP_WRITE_3;
          rxBufOp <= RXBUF_OP_POP;
          
          -- We can only get here while executing bulk write or prepare
          -- volatile commands. In the first case, perform the write now.
          -- Otherwise, set the flags for the volatile operation.
          if commandCode = COMCODE_BULK_WRITE then
            enableOp <= ENABLE_OP_WRITE;
            state_next <= STATE_BUS_OP;
          else
            state_next <= STATE_SET_VOLATILE_FLAGS;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_SET_VOLATILE_FLAGS =>
          writeDataOp <= WDAT_OP_LOAD_MASK;
          enableOp <= ENABLE_OP_QUEUE;
          rxBufOp <= RXBUF_OP_POP;
          
          -- We can only get here while preparing a volatile bus operation, in
          -- which case we're done.
          packetOp <= PACKET_OP_NEXT;
          state_next <= STATE_WAIT;
          
        -----------------------------------------------------------------------
        when STATE_BUS_OP =>
          busOp <= BUS_OP_EXECUTE;
          if busOpComplete = '1' then
            state_next <= STATE_BUS_OP_COMPLETE;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_BUS_OP_COMPLETE =>
          
          -- We should auto-increment the address after any bus operation. The
          -- only case where we don't need to do this is after completing a
          -- volatile bus operation, in which case it doesn't matter if we do
          -- it or not.
          addressOp <= ADDR_OP_AUTO_INC;
          
          -- If this was a bulk write, finish the command if there is no more
          -- data in the packet, or auto increment and return to write data
          -- setup. Otherwise, we're executing a bulk read or volatile bus
          -- operation command, in which case we should push the read result
          -- into the transmit buffer next.
          if commandCode = COMCODE_BULK_WRITE then
            if rxEmpty = '1' then
              packetOp <= PACKET_OP_NEXT;
              state_next <= STATE_WAIT;
            else
              state_next <= STATE_SET_WRITE_DATA_0;
            end if;
          else
            state_next <= STATE_PUSH_READ_DATA_0;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_PUSH_READ_DATA_0 =>
          txBufOp <= TXBUF_OP_PUSH_READ_0;
          state_next <= STATE_PUSH_READ_DATA_1;
          
        -----------------------------------------------------------------------
        when STATE_PUSH_READ_DATA_1 =>
          txBufOp <= TXBUF_OP_PUSH_READ_1;
          state_next <= STATE_PUSH_READ_DATA_2;
          
        -----------------------------------------------------------------------
        when STATE_PUSH_READ_DATA_2 =>
          txBufOp <= TXBUF_OP_PUSH_READ_2;
          state_next <= STATE_PUSH_READ_DATA_3;
          
        -----------------------------------------------------------------------
        when STATE_PUSH_READ_DATA_3 =>
          txBufOp <= TXBUF_OP_PUSH_READ_3;
          
          -- If this was a bulk read, finish the packet when we're done or
          -- perform the next read. Otherwise, this was a volatile bus
          -- operation and we should push the flags as well.
          if commandCode = COMCODE_BULK_READ then
            if bulkReadStop = '1' then
              packetOp <= PACKET_OP_NEXT;
              state_next <= STATE_WAIT;
            else
              enableOp <= ENABLE_OP_READ;
              state_next <= STATE_BUS_OP;
            end if;
          else
            state_next <= STATE_PUSH_RESULT_FLAGS;
          end if;
          
        -----------------------------------------------------------------------
        when STATE_PUSH_RESULT_FLAGS =>
          txBufOp <= TXBUF_OP_PUSH_FLAGS;
          
          -- We only get here when we're performing an execute volatile bus 
          -- command operation, in which case we're done.
          packetOp <= PACKET_OP_NEXT;
          state_next <= STATE_WAIT;
          
      end case;
      
    end process;
    
  end block;
  
end Behavioral;

