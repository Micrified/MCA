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
use rvex.common_pkg.all;
use rvex.simUtils_pkg.all;
use rvex.bus_pkg.all;

--=============================================================================
-- This testbench is used for basic testing of the trace peripheral.
-------------------------------------------------------------------------------
entity trace_tb is
end trace_tb;
--=============================================================================

--=============================================================================
architecture Behavioral of trace_tb is
--=============================================================================
  
  -- Interface signals.
  signal reset                  : std_logic;
  signal clk                    : std_logic;
  signal clkEn                  : std_logic;
  signal bus2trace              : bus_mst2slv_type;
  signal trace2bus              : bus_slv2mst_type;
  signal rv2trace_push          : std_logic;
  signal rv2trace_data          : rvex_byte_type;
  signal trace2rv_busy          : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Instantiate the unit under test.
  uut: entity rvex.periph_trace
    generic map (
      DEPTH_LOG2B               => 6
    )
    port map (
      
      -- System control
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- Slave bus
      bus2trace                 => bus2trace,
      trace2bus                 => trace2bus,
      
      -- Trace bytestream input
      rv2trace_push             => rv2trace_push,
      rv2trace_data             => rv2trace_data,
      trace2rv_busy             => trace2rv_busy
      
    );
  
  -- Generate a clock.
  clk_proc: process is
  begin
    clk <= '1';
    wait for 5 ns;
    clk <= '0';
    wait for 5 ns;
  end process;
  
  -- Generate clock enable signal.
  clkEn <= '1';
  
  -- Generate reset signal.
  reset_proc: process is
  begin
    reset <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    reset <= '0';
    wait;
  end process;
  
  -- Generate trace data source.
  trace_proc: process is
  begin
    rv2trace_push <= '0';
    rv2trace_data <= X"00";
    wait until rising_edge(clk) and reset = '0';
    loop
      for i in 0 to 255 loop
        wait until rising_edge(clk) and trace2rv_busy = '0';
        rv2trace_push <= '1';
        rv2trace_data <= std_logic_vector(to_unsigned(i, 8));
        wait until rising_edge(clk) and trace2rv_busy = '0';
        rv2trace_push <= '0';
        rv2trace_data <= "UUUUUUUU";
      end loop;
    end loop;
  end process;
  
  -- Generate bus requests. Note: this does not generate requests properly;
  -- the request signals do not stay valid when busy goes high. The trace unit
  -- doesn't care; just don't think this is a proper implementation of a bus
  -- master.
  bus_proc: process is
    variable counter  : natural;
    variable prevAddr : rvex_address_type;
    variable prevEna  : std_logic;
  begin
    counter := 0;
    bus2trace <= BUS_MST2SLV_IDLE;
    wait until rising_edge(clk) and reset = '0';
    loop
      prevAddr := bus2trace.address;
      prevEna := bus2trace.readEnable;
      bus2trace.address <= std_logic_vector(to_unsigned(counter / 16, 30)) & "00";
      if (counter mod 16) = 0 then
        bus2trace.readEnable <= '1';
      else
        bus2trace.readEnable <= '0';
      end if;
      wait until rising_edge(clk) and trace2bus.busy = '0';
      if prevEna = '1' then
        dumpStdOut(
          "Read " & rvs_hex(trace2bus.readData, 8)
          & " (" & rvs_uint(trace2bus.readData) & ") from "
          & rvs_hex(prevAddr, 8)
        );
      end if;
      counter := counter + 1;
    end loop;
  end process;
  
end Behavioral;

