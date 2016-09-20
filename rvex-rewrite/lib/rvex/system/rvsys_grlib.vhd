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
use rvex.utils_pkg.all;
-- pragma translate_off
use rvex.simUtils_pkg.all;
use rvex.simUtils_mem_pkg.all;
-- pragma translate_on
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;
use rvex.rvsys_grlib_pkg.all;

library grlib;
use grlib.amba.all;
use grlib.devices.all;

library gaisler;
use gaisler.leon3.all;

--=============================================================================
-- This entity is designed such that it can be used in place of the LEON3 core
-- from grlib. The only thing that this unit does in addition to
-- rvsys_grlib_rctrl is bridging from the r-VEX run control interface to the
-- LEON3 interrupt controller (irqmp) interface.
-------------------------------------------------------------------------------
entity rvsys_grlib is
--=============================================================================
  generic (
    
    -- Configuration vector.
    CFG                         : rvex_grlib_generic_config_type := rvex_grlib_cfg;
    
    -- Platform version tag. This is put in the global control registers of the
    -- processors.
    PLATFORM_TAG                : std_logic_vector(55 downto 0) := (others => '0');
    
    -- AHB master starting index. There will be as many AHB masters as there
    -- are lane groups in the core.
    AHB_MASTER_INDEX_START      : integer range 0 to NAHBMST-1 := 0;
    
    -- When true, memory accesses made by the rvex will be checked for
    -- consistency. When a memory access does not behave as if a basic
    -- unlimited sized memory were connected to the bus, a warning is
    -- reported.
    CHECK_MEM                   : boolean := false;
    
    -- S-record initialization file for the memory checking code.
    CHECK_MEM_FILE              : string := ""
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Clock input, registers are rising edge triggered.
    clki                        : in  std_ulogic;
    
    -- Active *low* synchronous reset input.
    rstn                        : in  std_ulogic;
    
    ---------------------------------------------------------------------------
    -- Processor interface
    ---------------------------------------------------------------------------
    -- AHB master interface. This is used for instruction and data access. Each
    -- lane group has its own AHB master.
    ahbmi                       : in  ahb_mst_in_type;
    ahbmo                       : out ahb_mst_out_vector_type(2**CFG.core.numLaneGroupsLog2-1 downto 0);
    
    -- AHB slave input for bus snooping.
    ahbsi                       : in  ahb_slv_in_type;
    
    -- Slave rvex bus, to be connected to an ahb2bus bridge up the hierarchy.
    -- Used to access debug control and status registers for the core, cache
    -- and any other support systems. Refer to rvsys_grlib_rctrl for the
    -- memory map.
    bus2dgb                     : in  bus_mst2slv_type;
    dbg2bus                     : out bus_slv2mst_type;
    
    -- Interrupt controller interface. This entity handles translation from the
    -- LEON3 interrupt controller to the rvex interrupt control signals. Note
    -- that each rvex context requires its own interrupt controller.
    irqi                        : in  irq_in_vector(0 to 2**CFG.core.numContextsLog2-1);
    irqo                        : out irq_out_vector(0 to 2**CFG.core.numContextsLog2-1);
    
    -- GPIO input that can be read from address 0x404 (word) or 0x407 (byte).
    gpio_dip                    : in std_logic_vector(7 downto 0) := (others => '0')
    
  );
end rvsys_grlib;

--=============================================================================
architecture Behavioral of rvsys_grlib is
--=============================================================================
  
  -- rvex interrupt/run control interface signals.
  signal rctrl2rv_irq           : std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
  signal rctrl2rv_irqID         : rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0);
  signal rv2rctrl_irqAck        : std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
  signal rctrl2rv_run           : std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
  signal rv2rctrl_idle          : std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
  signal rctrl2rv_reset         : std_logic_vector(2**CFG.core.numContextsLog2-1 downto 0);
  signal rctrl2rv_resetVect     : rvex_address_array(2**CFG.core.numContextsLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Instantiate r-VEX grlib system
  -----------------------------------------------------------------------------
  wrapped: entity rvex.rvsys_grlib_rctrl
    generic map (
      CFG                       => CFG,
      PLATFORM_TAG              => PLATFORM_TAG,
      AHB_MASTER_INDEX_START    => AHB_MASTER_INDEX_START,
      CHECK_MEM                 => CHECK_MEM,
      CHECK_MEM_FILE            => CHECK_MEM_FILE
    )
    port map (
      clki                      => clki,
      rstn                      => rstn,
      ahbmi                     => ahbmi,
      ahbmo                     => ahbmo,
      ahbsi                     => ahbsi,
      bus2dgb                   => bus2dgb,
      dbg2bus                   => dbg2bus,
      rctrl2rv_irq              => rctrl2rv_irq,
      rctrl2rv_irqID            => rctrl2rv_irqID,
      rv2rctrl_irqAck           => rv2rctrl_irqAck,
      rctrl2rv_run              => rctrl2rv_run,
      rv2rctrl_idle             => rv2rctrl_idle,
      rctrl2rv_reset            => rctrl2rv_reset,
      rctrl2rv_resetVect        => rctrl2rv_resetVect,
      gpio_dip                  => gpio_dip
    );
  
  -----------------------------------------------------------------------------
  -- Interrupt controller bridge
  -----------------------------------------------------------------------------
  irq_bridge_gen: for ctxt in 2**CFG.core.numContextsLog2-1 downto 0 generate
    
    -- Because the rvex does not have an interrupt level register, we always
    -- accept any incoming interrupt when the interrupt enable flag is set.
    -- This means interrupts can nest just fine, but it's all or nothing. Note
    -- that the other run control signals are also connected to the interrupt
    -- controller appropriately, except for the run signal. The default
    -- interrupt controller seems to have run hardwired such that only
    -- processor 0 is ever enabled, so it wouldn't make much sense to connect
    -- it.
    rctrl2rv_irq(ctxt)        <= '0' when irqi(ctxt).irl = "0000" else '1';
    rctrl2rv_irqID(ctxt)      <= X"0000000" & irqi(ctxt).irl;
    rctrl2rv_run(ctxt)        <= '1'; --irqi(ctxt).run;
    rctrl2rv_reset(ctxt)      <= irqi(ctxt).rst or irqi(ctxt).hrdrst;
    rctrl2rv_resetVect(ctxt)  <= irqi(ctxt).rstvec & X"000";
    irqo(ctxt).intack         <= rv2rctrl_irqAck(ctxt);
    irqo(ctxt).irl            <= irqi(ctxt).irl;
    irqo(ctxt).pwd            <= '0';
    irqo(ctxt).fpen           <= '0';
    irqo(ctxt).idle           <= rv2rctrl_idle(ctxt);
    
  end generate;
  
end Behavioral;

