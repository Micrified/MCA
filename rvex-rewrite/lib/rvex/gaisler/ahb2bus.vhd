-- r-VEX processor
-- Copyright (C) 2008-2015 by TU Delft.
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

-- Copyright (C) 2008-2015 by TU Delft.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library rvex;
use rvex.common_pkg.all;
use rvex.bus_pkg.all;

library grlib;
use grlib.amba.all;
use grlib.devices.all;
use grlib.stdlib.all;
use grlib.dma2ahb_package.all;

--=============================================================================
-- This entity provides a bridge from an AHB slave interface to an rvex bus.
-------------------------------------------------------------------------------
entity ahb2bus is
--=============================================================================
  generic (
    
    -- AHB slave index.
    AHB_INDEX                   : integer := 0;
    
    -- AHB address mapping information.
    AHB_ADDR                    : integer := 16#000#;
    AHB_MASK                    : integer := 16#FFF#;
    
    -- AHB device description.
    AHB_VENDOR_ID               : integer := VENDOR_TUDELFT;
    AHB_DEVICE_ID               : integer := 0;
    AHB_VERSION                 : integer := 0
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- AHB slave interface
    ---------------------------------------------------------------------------
    ahb2bridge                  : in  ahb_slv_in_type;
    bridge2ahb                  : out ahb_slv_out_type;
      
    ---------------------------------------------------------------------------
    -- rvex library master bus interface
    ---------------------------------------------------------------------------
    bridge2bus                  : out bus_mst2slv_type;
    bus2bridge                  : in  bus_slv2mst_type
    
  );
end ahb2bus;

--=============================================================================
architecture Behavioral of ahb2bus is
--=============================================================================
  
  -- AHB slave plug and play configuration.
  constant hconfig              : ahb_config_type := (
    0 => ahb_device_reg(
      AHB_VENDOR_ID,
      AHB_DEVICE_ID,
      0,
      AHB_VERSION,
      0
    ),
    4 => ahb_membar(
      AHB_ADDR,
      '0',
      '0',
      AHB_MASK
    ),
    others => zero32
  );
  
  -- Decoded bus request signals.
  signal address                : rvex_address_type;
  signal readEnable             : std_logic;
  signal readByteSel            : std_logic_vector(7 downto 0);
  signal writeEnable            : std_logic;
  signal writeMask              : rvex_mask_type;
  signal writeData              : rvex_data_type;
  
  -- This is high when the bus request signals above should be forwarded to the
  -- rvex bus.
  signal request                : std_logic;
  
  -- Read result signal, muxed such that byte and halfword reads are returned
  -- properly.
  signal readData               : rvex_data_type;
  
  -- AHB response signals.
  signal hready                 : std_logic;
  signal busError               : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Decode AHB address and control information
  -----------------------------------------------------------------------------
  control_addr_decode: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        address       <= (others => '0');
        readEnable    <= '0';
        readByteSel   <= (others => '0');
        writeEnable   <= '0';
        writeMask     <= (others => '0');
      elsif ahb2bridge.hready = '1' then
        
        -- Decode address.
        address       <= ahb2bridge.haddr(31 downto 2) & "00";
        
        -- Decode enable signals.
        if ahb2bridge.hsel(AHB_INDEX) = '1' and (
          ahb2bridge.htrans = HTRANS_NONSEQ or ahb2bridge.htrans = HTRANS_SEQ
        ) then
          readEnable  <= not ahb2bridge.hwrite;
          writeEnable <= ahb2bridge.hwrite;
        else
          readEnable  <= '0';
          writeEnable <= '0';
        end if;
        
        -- Decode mask and select signals.
        case ahb2bridge.hsize is
          
          -- Byte accesses.
          when HSIZE_BYTE =>
            case ahb2bridge.haddr(1 downto 0) is
              when "00"   => writeMask <= "1000"; readByteSel <= "11111111";
              when "01"   => writeMask <= "0100"; readByteSel <= "10101010";
              when "10"   => writeMask <= "0010"; readByteSel <= "01010101";
              when others => writeMask <= "0001"; readByteSel <= "00000000";
            end case;
            
          -- Halfword accesses.
          when HSIZE_HWORD =>
            case ahb2bridge.haddr(1 downto 1) is
              when "0"    => writeMask <= "1100"; readByteSel <= "11101110";
              when others => writeMask <= "0011"; readByteSel <= "01000100";
            end case;
            
          -- Word accesses.
          when others =>     writeMask <= "1111"; readByteSel <= "11100100";
          
        end case;
        
      end if;
    end if;
  end process;
  
  -- Read the write data combinatorially, as it is part of the second AHB
  -- transfer phase.
  writeData <= ahbreadword(ahb2bridge.hwdata);
  
  -----------------------------------------------------------------------------
  -- Bus translation state machine
  -----------------------------------------------------------------------------
  fsm_block: block is
    
    -- State machine state variable.
    type fsm_state is (S_AWAIT_REQUEST, S_AWAIT_RESPONSE, S_ERROR);
    signal state                : fsm_state;
    signal state_next           : fsm_state;
    
  begin
    
    -- Instantiate the FSM state register.
    fsm_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          state <= S_AWAIT_REQUEST;
        else
          state <= state_next;
        end if;
      end if;
    end process;
    
    -- Decode state signals.
    process (
      state, readEnable, writeEnable, bus2bridge.ack, bus2bridge.fault
    ) is
    begin
      
      -- Set default states.
      request     <= '1';
      hready      <= '1';
      busError    <= '0';
      state_next  <= state;
      
      case state is
        
        -- Wait for a request from the AHB bus. When we get one, force hready
        -- low combinatorially; the readEnable/writeEnable signals are already
        -- aligned to the bus response.
        when S_AWAIT_REQUEST =>
          if readEnable = '1' or writeEnable = '1' then
            hready <= '0';
            state_next <= S_AWAIT_RESPONSE;
          end if;
          
        -- Wait for a response from the rvex bus. Keep hready low while we
        -- wait. When we get a positive response, assert hready and return to
        -- the request state. If we get a negative response, we need to drive
        -- a two-cycle bus error response. In the first of those two cycles,
        -- hready should still be low. The second cycle is handled by S_ERROR.
        when S_AWAIT_RESPONSE =>
          if bus2bridge.ack = '1' then
            request <= '0';
            if bus2bridge.fault = '1' then
              busError <= '1';
              hready <= '0';
              state_next <= S_ERROR;
            else
              hready <= '1';
              state_next <= S_AWAIT_REQUEST;
            end if;
          else
            hready <= '0';
          end if;
          
        -- Handle the second cycle of the two-cycle bus error response. Here,
        -- hready should be high to indicate the end of the transfer.
        when S_ERROR =>
          request <= '0';
          busError <= '1';
          state_next <= S_AWAIT_REQUEST;
        
      end case;
    end process;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Drive AHB output signals
  -----------------------------------------------------------------------------
  -- Drive constant AHB output signals.
  bridge2ahb.hsplit   <= (others => '0');
  bridge2ahb.hirq     <= (others => '0');
  bridge2ahb.hconfig  <= hconfig;
  bridge2ahb.hindex   <= AHB_INDEX;
  
  -- Drive response signals.
  bridge2ahb.hready   <= hready;
  bridge2ahb.hresp    <= HRESP_ERROR when busError = '1' else HRESP_OKAY;
  
  -- Drive read data signal, taking byte and halfword reads into consideration.
  read_data_decode: process (bus2bridge.readData, readByteSel) is
    variable s        : integer;
    variable readData : rvex_data_type;
  begin
    readData := (others => '0');
    for d in 0 to 3 loop
      s := to_integer(unsigned(readByteSel(d*2+1 downto d*2)));
      readData(d*8+7 downto d*8) := bus2bridge.readData(s*8+7 downto s*8);
    end loop;
    bridge2ahb.hrdata <= ahbdrivedata(readData);
  end process;
  
  -----------------------------------------------------------------------------
  -- Drive rvex bus output signals
  -----------------------------------------------------------------------------
  rvex_bus_output: process (
    address, readEnable, writeEnable, writeMask, writeData, request
  ) is
  begin
    
    -- Drive bus signals.
    bridge2bus              <= BUS_MST2SLV_IDLE;
    bridge2bus.address      <= address;
    bridge2bus.readEnable   <= request and readEnable;
    bridge2bus.writeEnable  <= request and writeEnable;
    bridge2bus.writeMask    <= writeMask;
    bridge2bus.writeData    <= writeData;
    
  end process;
  
end Behavioral;

