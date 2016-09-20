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
use rvex.core_trap_pkg.all;
use rvex.core_opcode_pkg.all;
use rvex.core_opcodeMemory_pkg.all;

--=============================================================================
-- This entity contains the optional memory unit for a pipelane.
-------------------------------------------------------------------------------
entity core_memu is
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
    
    -- Active high stall input for the pipeline.
    stall                       : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Pipelane interface
    ---------------------------------------------------------------------------
    -- Instruction valid bit. Invalid instructions should not commit anything,
    -- so they should not write to the memory.
    pl2memu_valid               : in  std_logic_vector(S_MEM to S_MEM);
    
    -- Opcode.
    pl2memu_opcode              : in  rvex_opcode_array(S_MEM to S_MEM);
    
    -- 32-bit operands.
    pl2memu_opAddr              : in  rvex_address_array(S_MEM to S_MEM);
    pl2memu_opData              : in  rvex_data_array(S_MEM to S_MEM);
    
    -- Misaligned access trap output.
    memu2pl_trap                : out trap_info_array(S_MEM to S_MEM);
    
    -- 32-bit output.
    memu2pl_result              : out rvex_data_array(S_MEM+L_MEM to S_MEM+L_MEM);
    
    ---------------------------------------------------------------------------
    -- Trace interface
    ---------------------------------------------------------------------------
    -- Whether a memory operation is being performed.
    memu2pl_trace_enable        : out std_logic_vector(S_MEM to S_MEM);
    
    -- The address of the memory operation.
    memu2pl_trace_addr          : out rvex_address_array(S_MEM to S_MEM);
    
    -- The write mask for the memory operation, or all zeros if the operation
    -- is a read.
    memu2pl_trace_writeMask     : out rvex_mask_array(S_MEM to S_MEM);
    
    -- The data written to the memory, masked by writeMask.
    memu2pl_trace_writeData     : out rvex_data_array(S_MEM to S_MEM);
  
    ---------------------------------------------------------------------------
    -- Memory interface
    ---------------------------------------------------------------------------
    -- Data memory address, shared between read and write command.
    memu2dmsw_addr              : out rvex_address_array(S_MEM to S_MEM);
    
    -- Data memory write command.
    memu2dmsw_writeData         : out rvex_data_array(S_MEM to S_MEM);
    memu2dmsw_writeMask         : out rvex_mask_array(S_MEM to S_MEM);
    memu2dmsw_writeEnable       : out std_logic_vector(S_MEM to S_MEM);
    
    -- Data memory read command and result.
    memu2dmsw_readEnable        : out std_logic_vector(S_MEM to S_MEM);
    dmsw2memu_readData          : in  rvex_data_array(S_MEM+L_MEM to S_MEM+L_MEM)
    
  );
end core_memu;

--=============================================================================
architecture Behavioral of core_memu is
--=============================================================================
  
  -- Memory unit control signals decoded from the opcode.
  signal ctrl                   : memoryCtrlSignals_array(S_MEM to S_MEM);
  
  -- This signal goes high when a misaligned memory access is attempted.
  signal misalignedAccess       : std_logic_vector(S_MEM to S_MEM);
  
  -- The data which is to be written to the memory and its byte mask.
  signal writeMask              : rvex_mask_array(S_MEM to S_MEM);
  signal writeData              : rvex_data_array(S_MEM to S_MEM);
  
  -- Pipeline stage type for controlling the read logic.
  type mem_stage_type is record
    
    -- Access size, in log2(byteCount).
    accessSizeBLog2             : std_logic_vector(1 downto 0);
    
    -- Controls sign/zero extension for halfword and byte oriented accesses.
    unsignedOp                  : std_logic;
    
    -- The two LSB of the address for halfword and byte oriented accesses.
    addrLSB                     : std_logic_vector(1 downto 0);
    
  end record;
  type mem_stage_array is array (natural range <>) of mem_stage_type;
  
  -- Pipeline registers for the read logic control signals.
  signal readCtrl               : mem_stage_array(S_MEM to S_MEM+L_MEM);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Command logic (S_MEM)
  -----------------------------------------------------------------------------
  -- Decode control signals.
  ctrl(S_MEM) <= OPCODE_TABLE(vect2uint(pl2memu_opcode(S_MEM))).memoryCtrl;
  
  -- Forward the address directly to the memory.
  memu2dmsw_addr(S_MEM) <= pl2memu_opAddr(S_MEM);
  
  -- Setup writeData and writeMask according to the access size and LSBs of the
  -- address.
  det_mask_and_alignment: process (pl2memu_opAddr, pl2memu_opData, ctrl) is
  begin
    case ctrl(S_MEM).accessSizeBLog2 is
      
      when ACCESS_SIZE_BYTE =>
        
        -- Replicate the byte to write to all four positions.
        writeData(S_MEM)( 7 downto  0) <= pl2memu_opData(S_MEM)(7 downto 0);
        writeData(S_MEM)(15 downto  8) <= pl2memu_opData(S_MEM)(7 downto 0);
        writeData(S_MEM)(23 downto 16) <= pl2memu_opData(S_MEM)(7 downto 0);
        writeData(S_MEM)(31 downto 24) <= pl2memu_opData(S_MEM)(7 downto 0);
        
        -- Setup write mask.
        case pl2memu_opAddr(S_MEM)(1 downto 0) is
          when "00"   => writeMask(S_MEM) <= "1000";
          when "01"   => writeMask(S_MEM) <= "0100";
          when "10"   => writeMask(S_MEM) <= "0010";
          when others => writeMask(S_MEM) <= "0001";
        end case;
        
        -- Byte accesses have no alignment constraints.
        misalignedAccess(S_MEM) <= '0';
        
      when ACCESS_SIZE_HALFWORD =>
        
        -- Replicate the halfword to write to both positions.
        writeData(S_MEM)(15 downto  0) <= pl2memu_opData(S_MEM)(15 downto 0);
        writeData(S_MEM)(31 downto 16) <= pl2memu_opData(S_MEM)(15 downto 0);
        
        -- Setup write mask.
        case pl2memu_opAddr(S_MEM)(1 downto 1) is
          when "0"    => writeMask(S_MEM) <= "1100";
          when others => writeMask(S_MEM) <= "0011";
        end case;
        
        -- Halfword accesses need to be aligned to 16-bit boundaries.
        misalignedAccess(S_MEM) <= pl2memu_opAddr(S_MEM)(0);
        
      when others =>
        
        -- Setup the write data.
        writeData(S_MEM) <= pl2memu_opData(S_MEM);
        
        -- Setup write mask.
        writeMask(S_MEM) <= "1111";
        
        -- Word accesses need to be aligned to 32-bit boundaries.
        misalignedAccess(S_MEM) <= pl2memu_opAddr(S_MEM)(0) or pl2memu_opAddr(S_MEM)(1);
        
    end case;
  end process;
  
  -- Forward the address to the trace system.
  memu2pl_trace_addr(S_MEM) <= pl2memu_opAddr(S_MEM);
  
  -- Setup write enable and read enable based on the control signals and
  -- alignment detection.
  memu2dmsw_readEnable(S_MEM)
    <= ctrl(S_MEM).readEnable
    and pl2memu_valid(S_MEM)
    and not misalignedAccess(S_MEM);
    
  memu2dmsw_writeEnable(S_MEM)
    <= ctrl(S_MEM).writeEnable
    and pl2memu_valid(S_MEM)
    and not misalignedAccess(S_MEM);
  
  memu2pl_trace_enable(S_MEM)
    <= (ctrl(S_MEM).readEnable or ctrl(S_MEM).writeEnable)
    and pl2memu_valid(S_MEM)
    and not misalignedAccess(S_MEM);
  
  -- Forward the write data signals.
  memu2dmsw_writeData(S_MEM) <= writeData(S_MEM);
  memu2pl_trace_writeData(S_MEM) <= writeData(S_MEM);
  
  -- Forward the write mask signals.
  memu2dmsw_writeMask(S_MEM) <= writeMask(S_MEM);
  memu2pl_trace_writeMask(S_MEM)
    <= writeMask(S_MEM) 
    when ctrl(S_MEM).writeEnable = '1'
    else "0000";
  
  -- Setup the trap output to the pipeline. We shouldn't care about the valid
  -- signal here, because the valid signal is pulled low when the trap is
  -- activated, causing a race condition. Instead, the validity check is done
  -- in the pipeline process, before the valid signal is updated.
  memu2pl_trap(S_MEM) <= (
    active => misalignedAccess(S_MEM) and (ctrl(S_MEM).readEnable or ctrl(S_MEM).writeEnable),
    cause  => rvex_trap(RVEX_TRAP_MISALIGNED_ACCESS),
    arg    => pl2memu_opAddr(S_MEM)
  );
  
  -- Load the necessary data for the read stage into the first stage of the
  -- shift register.
  readCtrl(S_MEM) <= (
    accessSizeBLog2 => ctrl(S_MEM).accessSizeBLog2,
    unsignedOp      => ctrl(S_MEM).unsignedOp,
    addrLSB         => pl2memu_opAddr(S_MEM)(1 downto 0)
  );
  
  -----------------------------------------------------------------------------
  -- Read logic (S_MEM + L_MEM)
  -----------------------------------------------------------------------------
  -- Delay the read control signals appropriately.
  delay_read_ctrl: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        readCtrl(S_MEM+1 to S_MEM+L_MEM) <= (others => (
          accessSizeBLog2 => ACCESS_SIZE_WORD,
          unsignedOp      => '0',
          addrLSB         => (others => '0')
        ));
      elsif clkEn = '1' and stall = '0' then
        readCtrl(S_MEM+1 to S_MEM+L_MEM) <= readCtrl(S_MEM to S_MEM+L_MEM-1);
      end if;
    end if;
  end process;
  
  -- Post-process the read result by selecting the appropriate byte, halfword
  -- or the full word and sign/zero extending it.
  read_post_processing: process (dmsw2memu_readData, readCtrl(S_MEM+L_MEM)) is
    variable byte               : std_logic_vector(7 downto 0);
    variable halfword           : std_logic_vector(15 downto 0);
  begin
    case readCtrl(S_MEM+L_MEM).accessSizeBLog2 is
      
      when ACCESS_SIZE_BYTE =>
        
        -- Select the appropriate byte.
        case readCtrl(S_MEM+L_MEM).addrLSB is
          when "00"   => byte := dmsw2memu_readData(S_MEM+L_MEM)(31 downto 24);
          when "01"   => byte := dmsw2memu_readData(S_MEM+L_MEM)(23 downto 16);
          when "10"   => byte := dmsw2memu_readData(S_MEM+L_MEM)(15 downto  8);
          when others => byte := dmsw2memu_readData(S_MEM+L_MEM)( 7 downto  0);
        end case;
        
        -- Forward it sign or zero extended.
        memu2pl_result(S_MEM+L_MEM)(7 downto 0)
          <= byte;
        
        memu2pl_result(S_MEM+L_MEM)(31 downto 8)
          <= (others => byte(7) and not readCtrl(S_MEM+L_MEM).unsignedOp);
        
      when ACCESS_SIZE_HALFWORD =>
        
        -- Select the appropriate halfword.
        case readCtrl(S_MEM+L_MEM).addrLSB(1 downto 1) is
          when "0"    => halfword := dmsw2memu_readData(S_MEM+L_MEM)(31 downto 16);
          when others => halfword := dmsw2memu_readData(S_MEM+L_MEM)(15 downto  0);
        end case;
        
        -- Forward it sign or zero extended.
        memu2pl_result(S_MEM+L_MEM)(15 downto 0)
          <= halfword;
        
        memu2pl_result(S_MEM+L_MEM)(31 downto 16)
          <= (others => halfword(15) and not readCtrl(S_MEM+L_MEM).unsignedOp);
        
      when others =>
        
        -- Forward the result directly for full-word accesses.
        memu2pl_result(S_MEM+L_MEM) <= dmsw2memu_readData(S_MEM+L_MEM);
        
    end case;
  end process;
  
end Behavioral;

