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
use rvex.utils_pkg.all;
use rvex.core_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_pipeline_pkg.all;
use rvex.core_ctrlRegs_pkg.all;
use rvex.core_trap_pkg.all;

--=============================================================================
-- This entity switches between the data memory and the control registers
-- based on address.
-------------------------------------------------------------------------------
entity core_dmemSwitch is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type
    
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
    
    -- Active high stall input.
    stall                       : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Pipelane interface
    ---------------------------------------------------------------------------
    -- Data memory address, shared between read and write command.
    memu2dmsw_addr              : in  rvex_address_array(S_MEM to S_MEM);
    
    -- Data memory write command.
    memu2dmsw_writeData         : in  rvex_data_array(S_MEM to S_MEM);
    memu2dmsw_writeMask         : in  rvex_mask_array(S_MEM to S_MEM);
    memu2dmsw_writeEnable       : in  std_logic_vector(S_MEM to S_MEM);
    
    -- Data memory read command and result.
    memu2dmsw_readEnable        : in  std_logic_vector(S_MEM to S_MEM);
    dmsw2memu_readData          : out rvex_data_array(S_MEM+L_MEM to S_MEM+L_MEM);
    
    -- Exception input from data memory.
    dmsw2pl_exception           : out trap_info_array(S_MEM+L_MEM to S_MEM+L_MEM);
    
    ---------------------------------------------------------------------------
    -- Data memory interface
    ---------------------------------------------------------------------------
    -- Data memory address, shared between read and write command.
    dmsw2dmem_addr              : out rvex_address_array(S_MEM to S_MEM);
    
    -- Data memory write command.
    dmsw2dmem_writeData         : out rvex_data_array(S_MEM to S_MEM);
    dmsw2dmem_writeMask         : out rvex_mask_array(S_MEM to S_MEM);
    dmsw2dmem_writeEnable       : out std_logic_vector(S_MEM to S_MEM);
    
    -- Data memory read command and result.
    dmsw2dmem_readEnable        : out std_logic_vector(S_MEM to S_MEM);
    dmem2dmsw_readData          : in  rvex_data_array(S_MEM+L_MEM to S_MEM+L_MEM);
    
    -- Exception input from data memory.
    dmem2dmsw_exception         : in  trap_info_array(S_MEM+L_MEM to S_MEM+L_MEM);
    
    ---------------------------------------------------------------------------
    -- Control register interface
    ---------------------------------------------------------------------------
    -- Data memory address, shared between read and write command.
    dmsw2creg_addr              : out rvex_address_array(S_MEM to S_MEM);
    
    -- Data memory write command.
    dmsw2creg_writeData         : out rvex_data_array(S_MEM to S_MEM);
    dmsw2creg_writeMask         : out rvex_mask_array(S_MEM to S_MEM);
    dmsw2creg_writeEnable       : out std_logic_vector(S_MEM to S_MEM);
    
    -- Data memory read command and result. Note that the latency is fixed to
    -- one cycle for the control register read data.
    dmsw2creg_readEnable        : out std_logic_vector(S_MEM to S_MEM);
    creg2dmsw_readData          : in  rvex_data_array(S_MEM+1 to S_MEM+1)
    
  );
end core_dmemSwitch;

--=============================================================================
architecture Behavioral of core_dmemSwitch is
--=============================================================================
  
  -- Select signal. When low, the data memory bus is selected. When high, the
  -- control register bus is selected.
  signal sel                    : std_logic_vector(S_MEM to S_MEM+L_MEM);
  
  -- Control register data delay line, for the case where L_MEM > 1.
  signal cregReadData           : rvex_data_array(S_MEM+1 to S_MEM+L_MEM);
  
  -- Requested address delay line, used for the trap argument in case the data
  -- memory returns a fault signal.
  signal addr                   : rvex_address_array(S_MEM to S_MEM+L_MEM);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Check configuration
  -----------------------------------------------------------------------------
  assert L_MEM >= 1
    report "Data memory latency must be at least 1, to match control register "
         & "access latency."
    severity failure;
  
  assert vect2unsigned(CFG.cregStartAddress(CRG_SIZE_BLOG2-1 downto 0)) = 0
    report "Control register start address must be aligned to a "
         & integer'image(2**CRG_SIZE_BLOG2) & " byte boundary boundary."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Select between data memory and control registers
  -----------------------------------------------------------------------------
  -- Select control registers when the MSBs of the address matches the control
  -- register block selected in the core configuration.
  sel(S_MEM) <= '1'
    when memu2dmsw_addr(S_MEM)(rvex_address_type'high downto CRG_SIZE_BLOG2)
       = CFG.cregStartAddress(rvex_address_type'high downto CRG_SIZE_BLOG2)
    else '0';
  
  -----------------------------------------------------------------------------
  -- Drive memory bus and control register bus command signals
  -----------------------------------------------------------------------------
  -- Memory bus command should be issued when sel is low.
  dmsw2dmem_addr(S_MEM)         <= memu2dmsw_addr(S_MEM);
  dmsw2dmem_writeData(S_MEM)    <= memu2dmsw_writeData(S_MEM);
  dmsw2dmem_writeMask(S_MEM)    <= memu2dmsw_writeMask(S_MEM);
  dmsw2dmem_writeEnable(S_MEM)  <= memu2dmsw_writeEnable(S_MEM) and not sel(S_MEM);
  dmsw2dmem_readEnable(S_MEM)   <= memu2dmsw_readEnable(S_MEM) and not sel(S_MEM);
  
  -- Control register bus command should be issued when sel is high.
  dmsw2creg_addr(S_MEM)         <= memu2dmsw_addr(S_MEM);
  dmsw2creg_writeData(S_MEM)    <= memu2dmsw_writeData(S_MEM);
  dmsw2creg_writeMask(S_MEM)    <= memu2dmsw_writeMask(S_MEM);
  dmsw2creg_writeEnable(S_MEM)  <= memu2dmsw_writeEnable(S_MEM) and sel(S_MEM);
  dmsw2creg_readEnable(S_MEM)   <= memu2dmsw_readEnable(S_MEM) and sel(S_MEM);
  
  -----------------------------------------------------------------------------
  -- Delay select and control register read data signals
  -----------------------------------------------------------------------------
  -- ... to align them with the memory read data.
  
  -- Copy the read data from the control registers and the requested address
  -- into the first stage of their respective shift registers.
  cregReadData(S_MEM+1) <= creg2dmsw_readData(S_MEM+1);
  addr(S_MEM)           <= memu2dmsw_addr(S_MEM);
  
  -- Instantiate the shift registers.
  align_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        
        sel(S_MEM+1 to S_MEM+L_MEM)
          <= (others => '0');
        
        if L_MEM > 1 then
          cregReadData(S_MEM+2 to S_MEM+L_MEM)
            <= (others => (others => '0'));
        end if;
        
        addr(S_MEM+1 to S_MEM+L_MEM)
          <= (others => (others => '0'));
        
      elsif clkEn = '1' and stall = '0' then
        
        sel(S_MEM+1 to S_MEM+L_MEM)
          <= sel(S_MEM to S_MEM+L_MEM-1);
        
        if L_MEM > 1 then
          cregReadData(S_MEM+2 to S_MEM+L_MEM)
            <= cregReadData(S_MEM+1 to S_MEM+L_MEM-1);
        end if;
        
        addr(S_MEM+1 to S_MEM+L_MEM)
          <= addr(S_MEM to S_MEM+L_MEM-1);
        
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Drive bus access result signals
  -----------------------------------------------------------------------------
  dmsw2memu_readData(S_MEM+L_MEM)
    <= cregReadData(S_MEM+L_MEM) when sel(S_MEM+L_MEM) = '1'
    else dmem2dmsw_readData(S_MEM+L_MEM);
  
  dmsw2pl_exception(S_MEM+L_MEM) <= (
    active => dmem2dmsw_exception(S_MEM+L_MEM).active and not sel(S_MEM+L_MEM),
    cause  => dmem2dmsw_exception(S_MEM+L_MEM).cause,
    arg    => addr(S_MEM+L_MEM)
  );
  
end Behavioral;

