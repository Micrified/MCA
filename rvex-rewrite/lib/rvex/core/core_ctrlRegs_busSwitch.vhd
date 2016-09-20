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
use rvex.core_intIface_pkg.all;

--=============================================================================
-- This entity generates a configurable switch from one master memory bus to
-- up to four slave busses, based on configurable address ranges. The switch
-- assumes 1-cycle delay for all slaves.
-------------------------------------------------------------------------------
entity core_ctrlRegs_busSwitch is
--=============================================================================
  generic (
    
    -- Number of slave busses.
    NUM_SLAVES                  : positive;
    
    -- Address range definitions. Addresses from 0 to BOUNDARIES(1)-1 go to
    -- slave 0, addresses from BOUNDARIES(i) to BOUNDARIES(i+1)-1 go to slave
    -- i, and the range from BOUNDARIES(N-1) to 0xFFFFFFFF go to slave N-1.
    BOUNDARIES                  : rvex_address_array;
    
    -- Mask for the address comparisons. Only bits which are set in this
    -- constant are taken into consideration.
    BOUND_MASK                  : rvex_address_type
    
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
    
    ---------------------------------------------------------------------------
    -- Master bus
    ---------------------------------------------------------------------------
    mstr2sw_addr                : in  rvex_address_type;
    mstr2sw_writeEnable         : in  std_logic;
    mstr2sw_writeMask           : in  rvex_mask_type;
    mstr2sw_writeData           : in  rvex_data_type;
    mstr2sw_readEnable          : in  std_logic;
    sw2mstr_readData            : out rvex_data_type;
    
    -- When high, writing is disabled. Also, read data is properly buffered to
    -- ensure that it is still valid when a core when the core unstalls after
    -- having been stalled in the middle of a read.
    mstr2sw_stall               : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Slave busses
    ---------------------------------------------------------------------------
    sw2slave_addr               : out rvex_address_array(0 to NUM_SLAVES-1);
    sw2slave_writeEnable        : out std_logic_vector(0 to NUM_SLAVES-1);
    sw2slave_writeMask          : out rvex_mask_array(0 to NUM_SLAVES-1);
    sw2slave_writeData          : out rvex_data_array(0 to NUM_SLAVES-1);
    sw2slave_readEnable         : out std_logic_vector(0 to NUM_SLAVES-1);
    slave2sw_readData           : in  rvex_data_array(0 to NUM_SLAVES-1)
    
  );
end core_ctrlRegs_busSwitch;

--=============================================================================
architecture Behavioral of core_ctrlRegs_busSwitch is
--=============================================================================
  
  -- Width of the selection field in bits.
  constant SEL_WIDTH            : natural := integer(ceil(log2(real(NUM_SLAVES))));
  
  -- Select signal, synchronized with the command from the master.
  signal sel                    : std_logic_vector(SEL_WIDTH-1 downto 0);
  
  -- Select signal, synchronized with the read data reply from the slave.
  signal sel_r                  : std_logic_vector(SEL_WIDTH-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Select between slave busses
  -----------------------------------------------------------------------------
  -- Select which slave bus should be accessed based on the incoming address
  -- and configuration.
  select_proc: process (mstr2sw_addr) is
    variable maskedAddr : rvex_address_type;
  begin
    
    -- Apply the mask to the incoming address.
    maskedAddr := mstr2sw_addr and BOUND_MASK;
    
    -- Perform range checking.
    sel <= (others => '0');
    for i in 1 to NUM_SLAVES-1 loop
      if vect2unsigned(maskedAddr) >= vect2unsigned(BOUNDARIES(i)) then
        sel <= uint2vect(i, SEL_WIDTH);
      end if;
    end loop;
    
  end process;
  
  -- Delay the select signal by one cycle to align it to the read data.
  select_reg: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        sel_r <= (others => '0');
      elsif clkEn = '1' then
        sel_r <= sel;
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Drive slave bus command signals
  -----------------------------------------------------------------------------
  slave_bus_command_connect: for slave in 0 to NUM_SLAVES-1 generate
    
    -- Forward address, write mask and write data to all slaves.
    sw2slave_addr(slave)         <= mstr2sw_addr;
    sw2slave_writeData(slave)    <= mstr2sw_writeData;
    sw2slave_writeMask(slave)    <= mstr2sw_writeMask;
    
    -- Forward read enable and write enable only to the selected slave.
    sw2slave_writeEnable(slave)
      <= (mstr2sw_writeEnable and not mstr2sw_stall) when vect2uint(sel) = slave else '0';
    
    sw2slave_readEnable(slave)
      <= (mstr2sw_readEnable and not mstr2sw_stall) when vect2uint(sel) = slave else '0';
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Drive master bus read data signal
  -----------------------------------------------------------------------------
  read_data_block: block is
    
    -- Stall signal, delayed by one cycle to match up with the read result.
    signal stall_reg            : std_logic;
    
    -- Combinatorial and registered read data signals.
    signal readData_comb        : rvex_data_type;
    signal readData_reg         : rvex_data_type;
  begin
    
    -- Mux between the slave busses.
    readData_comb
      <= (others => RVEX_UNDEF) when vect2uint(sel_r) >= NUM_SLAVES
      else slave2sw_readData(vect2uint(sel_r));
    
    -- Generate the stall and readData registers.
    read_data_regs: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          stall_reg <= '0';
          readData_reg <= (others => '0');
        elsif clkEn = '1' then
          stall_reg <= mstr2sw_stall;
          if stall_reg = '0' then
            readData_reg <= readData_comb;
          end if;
        end if;
      end if;
    end process;
    
    -- Select the combinatorial or registered read data signal depending on
    -- which is valid.
    sw2mstr_readData <= readData_comb when stall_reg = '0' else readData_reg;
    
  end block;
  
end Behavioral;

