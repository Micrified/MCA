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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library grlib;
use grlib.amba.all;
use grlib.devices.all;

library gaisler;
use gaisler.spi.all;

library techmap;
use techmap.gencomp.all;

library rvex;
use rvex.common_pkg.all;
use rvex.simUtils_pkg.all;
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;

--=============================================================================
-- This testbench may be used to test the bus2ahb interface. A dummy, but
-- reasonably complete AHB system is modeled, with devices with and without
-- wait states and a device which sends a split reply. The AHB system also
-- includes an ahb2bus interface with a memory attached to it and an ahb_snoop
-- unit, allowing them to be tested as well.
-------------------------------------------------------------------------------
entity bus2ahb_tb is
end bus2ahb_tb;
architecture Behavioral of bus2ahb_tb is
--=============================================================================
  
  -- Syscon signals.
  signal clk        : std_logic;
  signal reset      : std_logic;
  signal reset_n    : std_logic;
  
  -- AHB master signals.
  signal bridge2ahb : ahb_mst_out_type;
  signal ahb2bridge : ahb_mst_in_type;
  
  -- rvex bus signals.
  signal bus2bridge : bus_mst2slv_type;
  signal bridge2bus : bus_slv2mst_type;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  --===========================================================================
  -- Syscon signals
  --===========================================================================
  -- Generate clock signal.
  clk_proc: process is
  begin
    clk <= '1';
    wait for 5 ns;
    clk <= '0';
    wait for 5 ns;
  end process;
  
  -- Generate reset signals.
  reset_proc: process is
  begin
    reset <= '1';
    reset_n <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    reset <= '0';
    reset_n <= '1';
    wait;
  end process;
  
  --===========================================================================
  -- Dummy AHB/APB bus system
  --===========================================================================
  ahb_block: block is
    
    -- AHB bus signals.
    signal msti       : ahb_mst_in_type;
    signal msto       : ahb_mst_out_vector;
    signal slvi       : ahb_slv_in_type;
    signal slvo       : ahb_slv_out_vector;
    
  begin
  
    -- Instantiate AHB controller.
    ahb_ctrl_inst: entity grlib.ahbctrl
      generic map (
        defmast     => 1,
        split       => 1,
        rrobin      => 1
      )
      port map (
        rst         => reset_n,
        clk         => clk,
        msti        => msti,
        msto        => msto,
        slvi        => slvi,
        slvo        => slvo
      );
    
    -----------------------------------------------------------------------------
    -- Instantiate an AHB RAM device to test accesses without wait states at
    -- address 0x0-------.
    -----------------------------------------------------------------------------
    ahb_ram_inst: entity gaisler.ahbram
      generic map (
        hindex      => 0,
        haddr       => 16#000#,
        hmask       => 16#F00#,
        tech        => inferred,
        kbytes      => 1
      )
      port map (
        rst         => reset_n,
        clk         => clk,
        ahbsi       => slvi,
        ahbso       => slvo(0)
      );
    
    -- Connect AHB master under test.
    ahb2bridge <= msti;
    msto(0) <= bridge2ahb;
    
    -- Connect unused masters.
    other_masters: process is
    begin
      msto(NAHBMST-1 downto 1) <= (others => ahbm_none);
      
      -- Make master 1 request continuously to test arbitration somewhat.
      msto(1).hbusreq <= '1';
      
      wait;
    end process;
    
    -- Connect unused slaves.
    slvo(NAHBSLV-1 downto 4) <= (others => ahbs_none);
    
    -----------------------------------------------------------------------------
    -- Instantiate an APB bridge at address 0x800-----, to which we attach a
    -- dummy device which will always return the one's complement of the word
    -- address of the read operation when read. Because this is an APB device,
    -- wait states will be introduced. The device can be accessed at 0x8000----.
    -----------------------------------------------------------------------------
    dummy_apb_block: block is
      
      -- APB signals.
      signal apbi     : apb_slv_in_type;
      signal apbo     : apb_slv_out_vector;
      
      -- Dummy APB device configuration.
      constant pconfig : apb_config_type := (
        0 => ahb_device_reg(VENDOR_TUDELFT, 0, 0, 0, 0),
        1 => apb_iobar(16#000#, 16#F00#)
      );
      
    begin
      
      -- Instantiate APB bridge.
      dummy_apb_ctrl_inst: entity grlib.apbctrl
        generic map (
          hindex    => 1,
          haddr     => 16#800#,
          hmask     => 16#FFF#
        )
        port map (
          rst       => reset_n,
          clk       => clk,
          ahbi      => slvi,
          ahbo      => slvo(1),
          apbi      => apbi,
          apbo      => apbo
        );
      
      -- Generate some kind of read data. We're using the one's complement of the
      -- address for testing here.
      dummy_apb_device_proc: process (clk) is
      begin
        if rising_edge(clk) then
          if reset = '1' then
            apbo(0).prdata <= (others => '0');
          else
            apbo(0).prdata <= not apbi.paddr;
          end if;
        end if;
      end process;
      
      -- Connect the remainder of the APB output signals.
      apbo(0).pirq    <= (others => '0');
      apbo(0).pconfig <= pconfig;
      apbo(0).pindex  <= 0;
      
      -- Connect unused APB slave outputs.
      apbo(1 to NAPBSLV-1) <= (others => apb_none);
      
    end block; -- dummy APB
    
    -----------------------------------------------------------------------------
    -- Connect a SPI memory controller with a basic SPI memory chip model to the
    -- bus as well. This module supports SPLIT transfers. The flash memory is
    -- mapped to address 0x1-------, the control registers are mapped to address
    -- 0x9-------. The SPI memory model returns the one's complement of the LSB
    -- of the byte address.
    -----------------------------------------------------------------------------
    spim_block: block is
      
      -- SPI memory control I/O signals.
      signal spii   : spimctrl_in_type;
      signal spio   : spimctrl_out_type;
      
      -- Resolved SPI bus signals.
      signal miso   : std_logic;
      signal mosi   : std_logic;
      signal sck    : std_logic;
      signal ss     : std_logic;
      
    begin
      
      -- Instantiate the SPI memory controller.
      spim_ctrl_inst: entity gaisler.spimctrl
        generic map (
          hindex    => 2,
          hirq      => 2,
          faddr     => 16#100#,
          fmask     => 16#f00#,
          ioaddr    => 16#900#,
          iomask    => 16#f00#,
          spliten   => 1
        )
        port map (
          rstn      => reset_n,
          clk       => clk,
          ahbsi     => slvi,
          ahbso     => slvo(2),
          spii      => spii,
          spio      => spio
        );
      
      -- Connect SPI memory controller I/O.
      mosi      <= spio.mosi when spio.mosioen = '0' else 'Z';
      sck       <= spio.sck;
      ss        <= spio.csn;
      spii.miso <= miso;
      spii.mosi <= mosi;
      spii.cd   <= '1';
      
      -- Model the SPI memory connected to the memory controller so it actually
      -- does something.
      spi_mem_model: process is
        
        -- Byte type for SPI transfers.
        subtype byte_type is std_logic_vector(7 downto 0);
        
        -- Waits for and accepts an SPI byte transfer. Breaks immediately when SS
        -- is released by the master. Expects to be called at the falling edge of
        -- SS or SCK.
        procedure transfer(
          rdat  : out byte_type;
          wdat  : in byte_type := "ZZZZZZZZ"
        ) is
        begin
          for i in 7 downto 0 loop
            miso <= wdat(i);
            wait until rising_edge(sck);
            if ss = '1' then
              return;
            end if;
            rdat(i) := mosi;
            wait until falling_edge(sck);
            if ss = '1' then
              return;
            end if;
          end loop;
        end transfer;
        
        -- SPI command code.
        variable command  : byte_type;
        
        -- LSB of the requested address.
        variable address  : std_logic_vector(23 downto 0);
        
        -- Dummy byte.
        variable dummy    : byte_type;
        
      begin
        
        -- Loop so we can easily use "exit when".
        loop
          
          -- SPI bus idle state.
          miso <= 'Z';
          
          -- Wait for a command.
          wait until ss = '0' and sck = '0';
          transfer(command); exit when ss = '1';
          
          -- Handle the command.
          case command is
            
            -- Handle FAST-READ command with 3 address bytes.
            when X"0B" => 
              transfer(address(23 downto 16)); exit when ss = '1';
              transfer(address(15 downto  8)); exit when ss = '1';
              transfer(address( 7 downto  0)); exit when ss = '1';
              transfer(dummy);                 exit when ss = '1';
              loop
                transfer(dummy, not address(7 downto 0)); exit when ss = '1';
                report
                  "SPI: returned " & rvs_hex(not address(7 downto 0)) &
                  " for address " & rvs_hex(address)
                  severity note;
                address := std_logic_vector(unsigned(address) + 1);
              end loop;
              
            -- Unknown command.
            when others =>
              report
                "Unknown SPI memory command " & rvs_hex(command) & "."
                severity error;
              wait until ss = '1';
            
          end case;
          
        end loop;
      end process;
      
    end block; -- SPIM
    
    -----------------------------------------------------------------------------
    -- Connect an rvex bus bridge with some memory attached to it to address
    -- 0xA-------. A bus mux is placed in between such that accesses outside
    -- 0xA0------ return bus errors.
    -----------------------------------------------------------------------------
    rvex_bus_bridge_block: block is
      
      -- Address map for the bus demuxer.
      constant ADDR_MAP         : addrRangeAndMapping_array(0 downto 0) := (
        0 => addrRangeAndMap(match => "----0000------------------------")
      );
      
      -- Bridge to mux demuxer.
      signal bridge2demux       : bus_mst2slv_type;
      signal demux2bridge       : bus_slv2mst_type;
      
      -- Demuxer to memory block bus.
      signal demux2mem          : bus_mst2slv_type;
      signal mem2demux          : bus_slv2mst_type;
      
    begin
      
      -- Instantiate the bus bridge.
      rvex_bus_bridge_inst: entity rvex.ahb2bus
        generic map (
          AHB_INDEX             => 3,
          AHB_ADDR              => 16#A00#,
          AHB_MASK              => 16#F00#
        )
        port map (
          reset                 => reset,
          clk                   => clk,
          ahb2bridge            => slvi,
          bridge2ahb            => slvo(3),
          bridge2bus            => bridge2demux,
          bus2bridge            => demux2bridge
        );
      
      -- Instantiate a bus demuxer so we can get bus errors.
      rvex_bus_demux_inst: entity rvex.bus_demux
        generic map (
          ADDRESS_MAP           => ADDR_MAP
        )
        port map (
          reset                 => reset,
          clk                   => clk,
          clkEn                 => '1',
          mst2demux             => bridge2demux,
          demux2mst             => demux2bridge,
          demux2slv(0)          => demux2mem,
          slv2demux(0)          => mem2demux
        );
      
      -- Instantiate the memory.
      rvex_bus_memory_inst: entity rvex.bus_ramBlock_singlePort
        generic map (
          DEPTH_LOG2B           => 12
        )
        port map (
          reset                 => reset,
          clk                   => clk,
          clkEn                 => '1',
          mst2mem_port          => demux2mem,
          mem2mst_port          => mem2demux
        );
      
    end block; -- rvex bus bridge
    
    -----------------------------------------------------------------------------
    -- Instantiate an AHB bus snooper to test it.
    -----------------------------------------------------------------------------
    ahb_snoop_block: block is
      
      -- Number of masters to monitor.
      constant NUM_CACHE_BLOCKS : natural := 4;
      
      -- Invalidation status signals.
      signal invalAddr          : rvex_address_type;
      signal invalSource        : std_logic_vector(NUM_CACHE_BLOCKS-1 downto 0);
      signal invalEnable        : std_logic;
      
    begin
      
      -- Instantiate the bus snooper.
      ahb_snoop_inst: entity rvex.ahb_snoop
        generic map (
          FIRST_MASTER          => 0,
          NUM_CACHE_BLOCKS      => NUM_CACHE_BLOCKS
        )
        port map (
          reset                 => reset,
          clk                   => clk,
          ahbsi                 => slvi,
          invalAddr             => invalAddr,
          invalSource           => invalSource,
          invalEnable           => invalEnable
        );
      
      -- Report bus accesses to the simulation output.
      ahb_snoop_report_proc: process (clk) is
        variable index    : integer;
      begin
        if rising_edge(clk) and reset = '0' and invalEnable = '1' then
          index := -1;
          for i in 0 to NUM_CACHE_BLOCKS - 1 loop
            if invalSource(i) = '1' then
              if index = -1 then
                index := i;
              else
                report
                  "Bus snooper: invalSource has more than one signal active " &
                  "while it should be one-hot."
                  severity error;
                index := -1;
                exit;
              end if;
            end if;
          end loop;
          if index /= -1 then
            report
              "Bus snooper: block " & integer'image(index) &
              " invalidated address " & rvs_hex(invalAddr) & "."
              severity note;
          end if;
        end if;
      end process;
      
    end block;
    
  end block; -- AHB
  
  --===========================================================================
  -- Unit under test and stimuli
  --===========================================================================
  -- Connect bus2ahb unit under test.
  uut: entity rvex.bus2ahb
    port map (
      reset       => reset,
      clk         => clk,
      bus2bridge  => bus2bridge,
      bridge2bus  => bridge2bus,
      bridge2ahb  => bridge2ahb,
      ahb2bridge  => ahb2bridge
    );
  
  -- Generate rvex bus requests.
  uut_stim: process is
    
    -- Generates idle cycles for the bus.
    procedure bus_idle(
      count : natural := 1
    ) is
    begin
      bus2bridge <= BUS_MST2SLV_IDLE;
      for i in 1 to count loop
        
        -- Bus latches on the rising edge.
        wait until rising_edge(clk);
        
        -- Wait for the falling edge to let the simulation stabilize before
        -- reading the bus result state.
        wait until falling_edge(clk);
        
        -- Make sure the bus result is idle as well, as it should be.
        if bridge2bus.ack = '1' and bridge2bus.busy = '0' then
          report
            "Illegal ack on rvex bus while request idle."
            severity error;
        end if;
        if bridge2bus.ack = '0' and bridge2bus.busy = '1' then
          report
            "Illegal busy on rvex bus while request idle."
            severity error;
        end if;
        if bridge2bus.ack = '1' and bridge2bus.busy = '1' then
          report
            "Illegal response on rvex bus."
            severity error;
        end if;
        
      end loop;
    end bus_idle;
    
    -- Waits for the bus to acknowledge a request.
    procedure bus_waitForResult is
    begin
      loop
        
        -- Bus latches on the rising edge.
        wait until rising_edge(clk);
        
        -- Wait a bit longer to let the simulation stabilize before reading
        -- the bus result state.
        wait for 5 ps;
        
        -- The bus must return either busy or ack here.
        if bridge2bus.ack = '0' and bridge2bus.busy = '0' then
          report
            "Illegal idle response on rvex bus while requesting."
            severity error;
        end if;
        if bridge2bus.ack = '1' and bridge2bus.busy = '1' then
          report
            "Illegal response on rvex bus."
            severity error;
        end if;
        
        -- Return when we've received an ack.
        if bridge2bus.ack = '1' then
          return;
        end if;
        
      end loop;
    end bus_waitForResult;
    
    -- Reads from the specified address.
    procedure bus_read(
      addr  : rvex_address_type;
      flags : bus_flags_type := BUS_FLAGS_DEFAULT
    ) is
    begin
      
      -- Setup the bus request.
      bus2bridge <= BUS_MST2SLV_IDLE;
      bus2bridge.address <= addr;
      bus2bridge.readEnable <= '1';
      bus2bridge.flags <= flags;
      
      -- Wait for the bus result.
      bus_waitForResult;
      
      -- Report the result.
      if bridge2bus.fault = '1' then
        report
          "Bus fault " & rvs_hex(bridge2bus.readData) &
          " while reading from address " & rvs_hex(addr) & "."
          severity note;
      else
        report
          "Read " & rvs_hex(bridge2bus.readData) &
          " from address " & rvs_hex(addr) & "."
          severity note;
      end if;
      
    end bus_read;
    
    -- Writes to the specified address.
    procedure bus_write(
      addr  : rvex_address_type;
      data  : rvex_data_type;
      mask  : rvex_mask_type := "1111";
      flags : bus_flags_type := BUS_FLAGS_DEFAULT
    ) is
    begin
      
      -- Setup the bus request.
      bus2bridge <= BUS_MST2SLV_IDLE;
      bus2bridge.address <= addr;
      bus2bridge.writeData <= data;
      bus2bridge.writeMask <= mask;
      bus2bridge.writeEnable <= '1';
      bus2bridge.flags <= flags;
      
      -- Wait for the bus result.
      bus_waitForResult;
      
      -- Report the result.
      if bridge2bus.fault = '1' then
        report
          "Bus fault " & rvs_hex(bridge2bus.readData) &
          " while writing " & rvs_hex(data) & " (mask " & rvs_bin(mask) & ")" &
          " to address " & rvs_hex(addr) & "."
          severity note;
      else
        report
          "Written " & rvs_hex(data) & " (mask " & rvs_bin(mask) & ")" &
          " from address " & rvs_hex(addr) & "."
          severity note;
      end if;
      
    end bus_write;
    
  begin
    
    -- Wait for the reset state to clear.
    bus2bridge <= BUS_MST2SLV_IDLE;
    wait until rising_edge(clk) and reset = '0';
    wait until rising_edge(clk) and reset = '0';
    
    -- Make some bus requests.
    bus_read(X"80000000");
    bus_read(X"80000004");
    bus_read(X"10000000");
    bus_read(X"80000008");
    bus_read(X"8000000C");
    bus_read(X"A0000000");
    bus_write(X"00000000", X"DEADBEEF");
    bus_write(X"00000004", X"11111111", "1000");
    bus_write(X"00000004", X"22222222", "0100");
    bus_write(X"00000004", X"33333333", "0010");
    bus_write(X"00000004", X"44444444", "0001");
    bus_read(X"00000000", bus_flags_gen(burstEnable => '1', burstStart => '1'));
    bus_read(X"00000004", bus_flags_gen(burstEnable => '1', burstStart => '0'));
    bus_write(X"A0000000", X"DEADBEEF");
    bus_write(X"A0000004", X"11111111", "1000");
    bus_write(X"A0000004", X"22222222", "0100");
    bus_write(X"A0000004", X"33333333", "0010");
    bus_write(X"A0000004", X"44444444", "0001");
    bus_write(X"A0000008", X"55665566", "1100");
    bus_write(X"A0000008", X"77887788", "0011");
    bus_write(X"A1000000", X"DEADBEEF");
    bus_read(X"A0000000", bus_flags_gen(burstEnable => '1', burstStart => '1'));
    bus_read(X"A0000004", bus_flags_gen(burstEnable => '1', burstStart => '0'));
    bus_read(X"A0000008", bus_flags_gen(burstEnable => '1', burstStart => '0'));
    bus_read(X"A1000000");
    
    -- Idle forever.
    loop
      bus_idle(1);
    end loop;
    
  end process;
  
end Behavioral;

