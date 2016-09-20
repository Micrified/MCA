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
use rvex.core_pkg.all;
use rvex.core_intIface_pkg.all;

--=============================================================================
-- Testbench for the configuration control unit. It will attempt
-- reconfiguration to every runtime configuration which should be possible,
-- given a constant design time configuration. Conformance must be determined
-- manually from the simulation result for all design-time configurations.
-------------------------------------------------------------------------------
entity core_cfgCtrl_tb is
end core_cfgCtrl_tb;
--=============================================================================

--=============================================================================
architecture Behavioral of core_cfgCtrl_tb is
--=============================================================================
  
  -- rvex generic configuration.
  constant CFG                  : rvex_generic_config_type := rvex_cfg(
    numLanesLog2                => 3,
    numLaneGroupsLog2           => 2,
    numContextsLog2             => 2,
    genBundleSizeLog2           => 3,
    bundleAlignLog2             => 0,
    multiplierLanes             => 2#11111111#,
    memLaneRevIndex             => 1,
    branchLaneRevIndex          => 0,
    numBreakpoints              => 4,
    forwarding                  => 1,
    limmhFromNeighbor           => 1,
    limmhFromPreviousPair       => 1,
    reg63isLink                 => 0,
    cregStartAddress            => X"FFFFFF80",
    resetVectors                => (others => (others => '0'))
  );
  
  -- Signals from and to the configuration controller.
  signal reset                       : std_logic;
  signal clk                         : std_logic;
  signal clkEn                       : std_logic;
  signal cxreg2cfg_requestData       : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cfg_requestEnable     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal gbreg2cfg_requestData       : rvex_data_type;
  signal gbreg2cfg_requestEnable     : std_logic;
  signal cxreg2cfg_wakeupConfig      : rvex_data_type;
  signal cxreg2cfg_wakeupEnable      : std_logic;
  signal cfg2cxreg_wakeupAck         : std_logic;
  signal rctrl2cfg_irq_ct0           : std_logic;
  signal cfg2gbreg_busy              : std_logic;
  signal cfg2gbreg_error             : std_logic;
  signal cfg2gbreg_requesterID       : std_logic_vector(3 downto 0);
  signal cfg2cxplif_active           : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cfg2cxplif_requestReconfig  : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cfg_blockReconfig    : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal mem2cfg_blockReconfig       : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_configWord          : rvex_data_type;
  signal cfg2any_coupled             : std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_decouple            : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_numGroupsLog2       : rvex_2bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_context             : rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_active              : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cfg2any_lastGroupForCtxt    : rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
  signal cfg2any_laneIndex           : rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
  signal cfg2any_pcAddVal            : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Synchronization signal. This has a rising edge at every 10ns mark. It is
  -- used to align things to make them look nice in simulation.
  signal sync                        : std_logic := '0';
  
  -- Counts the number of valid configurations.
  signal validConfigs                : unsigned(31 downto 0);
  
--=============================================================================
begin
--=============================================================================
  
  -- Instantiate the configuration controller.
  uut: entity rvex.core_cfgCtrl
    generic map (
      CFG => CFG
    )
    port map (
      reset                       => reset,
      clk                         => clk,
      clkEn                       => clkEn,
      cxreg2cfg_requestData       => cxreg2cfg_requestData,
      cxreg2cfg_requestEnable     => cxreg2cfg_requestEnable,
      gbreg2cfg_requestData       => gbreg2cfg_requestData,
      gbreg2cfg_requestEnable     => gbreg2cfg_requestEnable,
      cxreg2cfg_wakeupConfig      => cxreg2cfg_wakeupConfig,
      cxreg2cfg_wakeupEnable      => cxreg2cfg_wakeupEnable,
      cfg2cxreg_wakeupAck         => cfg2cxreg_wakeupAck,
      rctrl2cfg_irq_ct0           => rctrl2cfg_irq_ct0,
      cfg2gbreg_busy              => cfg2gbreg_busy,
      cfg2gbreg_error             => cfg2gbreg_error,
      cfg2gbreg_requesterID       => cfg2gbreg_requesterID,
      cfg2cxplif_active           => cfg2cxplif_active,
      cfg2cxplif_requestReconfig  => cfg2cxplif_requestReconfig,
      cxplif2cfg_blockReconfig    => cxplif2cfg_blockReconfig,
      mem2cfg_blockReconfig       => mem2cfg_blockReconfig,
      cfg2any_configWord          => cfg2any_configWord,
      cfg2any_coupled             => cfg2any_coupled,
      cfg2any_decouple            => cfg2any_decouple,
      cfg2any_numGroupsLog2       => cfg2any_numGroupsLog2,
      cfg2any_context             => cfg2any_context,
      cfg2any_active              => cfg2any_active,
      cfg2any_lastGroupForCtxt    => cfg2any_lastGroupForCtxt,
      cfg2any_laneIndex           => cfg2any_laneIndex,
      cfg2any_pcAddVal            => cfg2any_pcAddVal
    );
  
  -- Drive the configuration block signals low, so reconfiguration is instant.
  cxplif2cfg_blockReconfig <= (others => '0');
  mem2cfg_blockReconfig <= (others => '0');
  
  -- Load default values into the requests from the contexts and the wakeup
  -- registers, we're not using them in this testbench.
  cxreg2cfg_requestData <= (others => (others => '0'));
  cxreg2cfg_requestEnable <= (others => '0');
  cxreg2cfg_wakeupConfig <= (others => '0');
  cxreg2cfg_wakeupEnable <= '0';
  rctrl2cfg_irq_ct0 <= '0';
  
  -- Generate sync signal.
  process is
  begin
    wait for 1 ps;
    sync <= '0';
    wait for 99999 ps;
    sync <= '1';
  end process;
  
  -- Generate other stimuli.
  process is
    type natural_array is array (natural range <>) of natural;
    variable contexts: natural_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    variable carry: boolean;
    variable word: rvex_data_type;
  begin
    
    -- Reset everything.
    validConfigs <= (others => '0');
    gbreg2cfg_requestData <= (others => '0');
    gbreg2cfg_requestEnable <= '0';
    reset <= '1';
    clkEn <= '1';
    clk <= '1';
    wait for 1 ps;
    clk <= '0';
    wait for 1 ps;
    clk <= '1';
    wait for 1 ps;
    clk <= '0';
    wait for 1 ps;
    reset <= '0';
    
    -- Start out with everything connected to context 0.
    contexts := (others => 0);
    
    -- Loop over all configurations possible for 4-way reconfiguration, barring
    -- reserved bits.
    loop
      
      -- Encode the configuration word.
      word := (others => '0');
      for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        if contexts(i) = 2**CFG.numContextsLog2 then
          
          -- Disable lane group.
          word(i*4+3) := '1';
          
        else
          
          -- Connect lane group to given context.
          word(i*4+CFG.numContextsLog2-1 downto i*4) :=
            std_logic_vector(to_unsigned(contexts(i), CFG.numContextsLog2));
          
        end if;
      end loop;
      
      -- Clock in the request.
      gbreg2cfg_requestEnable <= '1';
      gbreg2cfg_requestData <= word;
      wait for 1 ps;
      clk <= '1';
      wait for 1 ps;
      clk <= '0';
      gbreg2cfg_requestEnable <= '0';
      
      -- Send 10 clock pulses, after which reconfiguration should be complete.
      for i in 1 to 10 loop
        wait for 1 ps;
        clk <= '1';
        wait for 1 ps;
        clk <= '0';
      end loop;
      
      -- If the error bit is not set, this was considered to be a valid
      -- configuration. In that case, synchronize with the sync signal so the
      -- valid configuration words and their output can be easily seen.
      if cfg2gbreg_error = '0' then
        validConfigs <= validConfigs + 1;
        wait until rising_edge(sync);
      end if;
      
      -- Determine the next configuration to try.
      carry := true;
      for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        contexts(i) := contexts(i) + 1;
        if contexts(i) = 2**CFG.numContextsLog2+1 then
          contexts(i) := 0;
        else
          carry := false;
          exit;
        end if;
      end loop;
      exit when carry;
      
    end loop;
    
    -- Stop simulation.
    report "Done!" severity failure;
    wait;
    
  end process;
  
end Behavioral;

