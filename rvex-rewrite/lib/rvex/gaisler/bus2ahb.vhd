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
-- This entity provides a bridge from a master bus interface as used in the
-- rvex library and a AHB master. Note that it uses an undocumented entity from
-- grlib which might be subject to changes in future grlib versions.
-------------------------------------------------------------------------------
entity bus2ahb is
--=============================================================================
  generic (
    
    -- AHB master index.
    AHB_MASTER_INDEX            : integer := 0;
    
    -- AHB device description.
    AHB_VENDOR_ID               : integer := VENDOR_TUDELFT;
    AHB_DEVICE_ID               : integer := 0;
    AHB_VERSION                 : integer := 0;
    
    -- rvex bus fault code used to indicate that an AHB bus error occured.
    BUS_ERROR_CODE              : rvex_address_type := (others => '0');
    
    -- rvex bus fault code used to indicate that an invalid rvex bus request
    -- was issued.
    REQ_ERROR_CODE              : rvex_address_type := (others => '0');
    
    -- Protection control bits to use.
    HPROT                       : std_logic_vector(3 downto 0) := "0011"
    
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
    -- rvex library slave bus interface
    ---------------------------------------------------------------------------
    bus2bridge                  : in  bus_mst2slv_type;
    bridge2bus                  : out bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- AHB master interface
    ---------------------------------------------------------------------------
    bridge2ahb                  : out ahb_mst_out_type;
    ahb2bridge                  : in  ahb_mst_in_type
    
  );
end bus2ahb;

--=============================================================================
architecture Behavioral of bus2ahb is
--=============================================================================
  
  -- AHB master plug and play configuration.
  constant hconfig              : ahb_config_type := (
    0 => ahb_device_reg(
      AHB_VENDOR_ID,
      AHB_DEVICE_ID,
      0,
      AHB_VERSION,
      0
    ),
    others => (others => '0')
  );
  
  -- Decoded rvex bus request signals for the AHB bus.
  signal ahbReq_enable          : std_logic;
  signal ahbReq_address         : std_logic_vector(31 downto 0);
  signal ahbReq_size            : std_logic_vector(2 downto 0);
  signal ahbReq_hprot           : std_logic_vector(3 downto 0);
  signal ahbReq_writeEnable     : std_logic;
  signal ahbReq_writeData       : std_logic_vector(AHBDW-1 downto 0);
  signal ahbReq_error           : std_logic;
  
  -- These signals are used to force insertion of a BUSY or IDLE transfer.
  -- forceIdle always forces an IDLE transfer, forceWait forces an IDLE or BUSY
  -- transfer depending on the burst flag.
  signal ahb_forceIdle          : std_logic;
  signal ahb_forceWait          : std_logic;
  
  -- This signal is set when the address for this transfer immediately follows 
  -- the address of the previous transfer per the AMBA burst specification for
  -- undefined burst lengths.
  signal ahb_sequential         : std_logic;
  
  -- Decoded AHB bus response signals for the rvex bus.
  signal busRes_ack             : std_logic;
  signal busRes_readData        : std_logic_vector(AHBDW-1 downto 0);
  signal busRes_error           : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Decode the rvex bus request
  -----------------------------------------------------------------------------
  -- Convert the bus request into the format expected by the AHB master.
  bus_request_proc: process (bus2bridge) is
    variable size               : std_logic_vector(1 downto 0);
    variable index              : std_logic_vector(1 downto 0);
  begin
    
    -- Set default request values.
    ahbReq_enable       <= '0';
    ahbReq_address      <= bus2bridge.address;
    ahbReq_size         <= HSIZE_WORD;
    ahbReq_hprot        <= HPROT;
    ahbReq_writeEnable  <= '0';
    ahbReq_writeData    <= ahbdrivedata(bus2bridge.writeData);
    ahbReq_error        <= '0';
    
    -- Handle reads.
    if bus2bridge.readEnable = '1' then
      ahbReq_enable <= '1';
      ahbReq_address(1 downto 0) <= "00";
    end if;
    
    -- Handle writes.
    if bus2bridge.writeEnable = '1' then
      ahbReq_enable <= '1';
      ahbReq_writeEnable <= '1';
      case bus2bridge.writeMask is
        
        -- Handle byte writes.
        when "1000" =>
          ahbReq_size <= HSIZE_BYTE;
          ahbReq_address(1 downto 0) <= "00";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(31 downto 24));
          
        when "0100" =>
          ahbReq_size <= HSIZE_BYTE;
          ahbReq_address(1 downto 0) <= "01";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(23 downto 16));
          
        when "0010" =>
          ahbReq_size <= HSIZE_BYTE;
          ahbReq_address(1 downto 0) <= "10";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(15 downto 8));
          
        when "0001" =>
          ahbReq_size <= HSIZE_BYTE;
          ahbReq_address(1 downto 0) <= "11";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(7 downto 0));
        
        -- Handle halfword writes.
        when "1100" =>
          ahbReq_size <= HSIZE_HWORD;
          ahbReq_address(1 downto 0) <= "00";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(31 downto 16));
          
        when "0011" =>
          ahbReq_size <= HSIZE_HWORD;
          ahbReq_address(1 downto 0) <= "10";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(15 downto 0));
          
        -- Handle word writes.
        when "1111" =>
          ahbReq_size <= HSIZE_WORD;
          ahbReq_address(1 downto 0) <= "00";
          ahbReq_writeData <= ahbdrivedata(bus2bridge.writeData(31 downto 0));
          
        -- Handle illegal accesses.
        when others =>
          ahbReq_enable <= '0';
          ahbReq_error <= '1';
          
      end case;
    end if;
    
    -- Read and write at the same time is illegal.
    if bus2bridge.readEnable = '1' and bus2bridge.writeEnable = '1' then
      ahbReq_enable <= '0';
      ahbReq_error <= '1';
    end if;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Drive the AHB master output signals
  -----------------------------------------------------------------------------
  -- Drive unused and/or constant AHB signals.
  bridge2ahb.hirq     <= (others => '0');
  bridge2ahb.hconfig  <= hconfig;
  bridge2ahb.hindex   <= AHB_MASTER_INDEX;
  
  -- Bus access request phase signals.
  bridge2ahb.hbusreq  <= ahbReq_enable;
  bridge2ahb.hlock    <= ahbReq_enable and bus2bridge.flags.lock;
  
  -- Drive AHB transfer type.
  bridge2ahb.htrans   <= HTRANS_IDLE    when ahbReq_enable = '0' or ahb_forceIdle = '1'
                    else HTRANS_BUSY    when (ahb_forceWait = '1' and bus2bridge.flags.burstEnable = '1')
                    else HTRANS_IDLE    when ahb_forceWait = '1'
                    else HTRANS_SEQ     when (ahb_sequential = '1' and bus2bridge.flags.burstEnable = '1')
                    else HTRANS_NONSEQ;
  
  -- Drive AHB burst type.
  bridge2ahb.hburst   <= HBURST_INCR when bus2bridge.flags.burstEnable = '1'
                    else HBURST_SINGLE;
  
  -- Drive the decoded AHB request signals from the rvex bus which are valid in
  -- the AHB address/control phase.
  bridge2ahb.haddr    <= ahbReq_address;
  bridge2ahb.hsize    <= ahbReq_size;
  bridge2ahb.hwrite   <= ahbReq_writeEnable;
  bridge2ahb.hprot    <= ahbReq_hprot;
    
  -- Drive write data. This needs to be delayed by one AHB bus phase, because
  -- write data is part of the first phase (request) in the rvex bus but part
  -- of the second phase (data) in AHB.
  ahb_wdata_reg: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        bridge2ahb.hwdata <= (others => '0');
      elsif ahb2bridge.hready = '1' then
        bridge2ahb.hwdata <= ahbReq_writeData;
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Handle AHB timing
  -----------------------------------------------------------------------------
  ahb_timing_block: block is
    
    -- These signals are asserted high when we have control over the bus
    -- address, control or data signals.
    signal addrCtrlPhase        : std_logic;
    signal dataPhase            : std_logic;
    
    -- AHB request enable signal delayed to align with the data phase.
    signal ahbReq_enable_dat    : std_logic;
    
    -- This is set when we're performing the first transfer since we had to
    -- stop requesting things for some reason.
    signal firstTransfer        : std_logic;
    
  begin
    
    -- Generate AHB control registers.
    ahb_regs: process (clk) is
      variable requesting : std_logic;
    begin
      if rising_edge(clk) then
        if reset = '1' then
          addrCtrlPhase     <= '0';
          dataPhase         <= '0';
          ahbReq_enable_dat <= '0';
          ahb_forceIdle     <= '0';
          firstTransfer     <= '1';
        else
          
          -- Determine whether we're requesting something right now.
          requesting := ahbReq_enable
                        and not ahb_forceIdle
                        and not ahb_forceWait;
          
          -- Update phasing signals.
          if ahb2bridge.hready = '1' then
            addrCtrlPhase     <= ahb2bridge.hgrant(AHB_MASTER_INDEX);
            dataPhase         <= addrCtrlPhase;
            ahbReq_enable_dat <= addrCtrlPhase and requesting;
          end if;
          
          -- Force an IDLE transfer following a SPLIT or RETRY bus response.
          if ahb2bridge.hready = '0' and (
            ahb2bridge.hresp = HRESP_SPLIT or ahb2bridge.hresp = HRESP_RETRY
          ) then
            ahb_forceIdle <= '1';
          end if;
          
          -- Force an IDLE transfer when we don't have access to the control
          -- signals.
          if ahb2bridge.hready = '1' then
            ahb_forceIdle <= not ahb2bridge.hgrant(AHB_MASTER_INDEX);
          end if;
          
          -- Determine whether this is the first transfer since we had to delay
          -- for some reason.
          if ahb2bridge.hready = '1' then
            if ahbReq_enable = '0' or ahb_forceIdle = '1' then
              firstTransfer <= '1';
            else
              firstTransfer <= '0';
            end if;
          end if;
          
        end if;
      end if;
    end process;
    
    -- Force a BUSY or IDLE transfer when we're waiting in the data phase. We
    -- need to do this, because the rvex bus does not provide information about
    -- the next transfer until data is available.
    ahb_forceWait   <= ahbReq_enable_dat and not busRes_ack;
    
    -- Determine whether this is a sequential/burst access.
    ahb_sequential  <= (not firstTransfer) and (not bus2bridge.flags.burstStart);
    
    -- Drive internal read data signal.
    busRes_readData <= ahb2bridge.hrdata;
    
    -- Drive bus transfer complete signal.
    busRes_ack      <= ahbReq_enable_dat and ahb2bridge.hready when (
                         ahb2bridge.hresp = HRESP_OKAY
                         or ahb2bridge.hresp = HRESP_ERROR
                       ) else '0';
    
    -- Drive bus transfer error signal.
    busRes_error    <= '1' when ahb2bridge.hresp = HRESP_ERROR else '0';
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Drive the rvex bus output signals
  -----------------------------------------------------------------------------
  rvex_bus_output_block: block is
    
    -- Whether the rvex bus was requesting something in the previous cycle.
    signal requesting_r         : std_logic;
    
    -- Delayed bus request error signal to align it with the bus result.
    signal ahbReq_error_r       : std_logic;
    
  begin
    
    -- Generate registers for the bus request active and error signals.
    bus_req_regs: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          requesting_r <= '0';
          ahbReq_error_r <= '0';
        else
          requesting_r <= bus2bridge.readEnable or bus2bridge.writeEnable;
          ahbReq_error_r <= ahbReq_error;
        end if;
      end if;
    end process;
    
    -- Drive the bus result signal.
    bus_res_proc: process (
      ahbReq_error_r, busRes_error, busRes_readData,
      requesting_r, busRes_ack
    ) is
    begin
      
      -- Drive with idle response by default.
      bridge2bus <= BUS_SLV2MST_IDLE;
      
      -- Drive read data/fault code.
      if ahbReq_error_r = '1' then
        bridge2bus.readData <= REQ_ERROR_CODE;
      elsif busRes_error = '1' then
        bridge2bus.readData <= BUS_ERROR_CODE;
      else
        bridge2bus.readData <= ahbreadword(busRes_readData);
      end if;
      
      -- Drive fault signal.
      bridge2bus.fault <= ahbReq_error_r or busRes_error;
      
      -- Drive busy and acknowledge signals.
      bridge2bus.busy <= requesting_r and not busRes_ack;
      bridge2bus.ack  <= requesting_r and busRes_ack;
    
    end process;
    
  end block;
  
end Behavioral;

