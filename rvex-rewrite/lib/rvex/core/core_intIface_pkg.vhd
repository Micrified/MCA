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

library rvex;
use rvex.common_pkg.all;
use rvex.core_pkg.all;
use rvex.core_pipeline_pkg.all;

--=============================================================================
-- This package contains type definitions and constants relevant only to the
-- core itself. This is used in virtually all entities used in the core, but
-- does not need to be imported by anything using the rvex cores.
-------------------------------------------------------------------------------
package core_intIface_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Common datatypes
  -----------------------------------------------------------------------------
  -- Size of the trap cause in bits.
  constant RVEX_TRAP_CAUSE_SIZE : natural := 8;
  
  -- Subtypes for some common datatypes used within the core. These are
  -- prefixed with rvex_ mostly for consistency with the basic types which are
  -- also used in the external interface.
  subtype rvex_opcode_type      is std_logic_vector(31 downto 24); -- Opcode portion of a syllable.
  subtype rvex_gpRegAddr_type   is std_logic_vector( 5 downto  0); -- General purpose register file address (excluding context).
  subtype rvex_brRegAddr_type   is std_logic_vector( 2 downto  0); -- Branch register file address (excluding context).
  subtype rvex_brRegData_type   is std_logic_vector( 7 downto  0); -- Branch register mask (excluding context), i.e., one bit per flag.
  subtype rvex_2bit_type        is std_logic_vector( 1 downto  0); -- Any 2-bit word, used for configuration control.
  subtype rvex_3bit_type        is std_logic_vector( 2 downto  0); -- Any 3-bit word, used for configuration control.
  subtype rvex_4bit_type        is std_logic_vector( 3 downto  0); -- Any 4-bit word, used for configuration control.
  subtype rvex_sylStatus_type   is std_logic_vector(15 downto  0); -- One status bit per syllable for the maximum supported lane count.
  subtype rvex_limmh_type       is std_logic_vector(31 downto  9); -- The part of a long immediate which is borrowed from another syllable.
  subtype rvex_trap_type        is std_logic_vector(RVEX_TRAP_CAUSE_SIZE-1 downto 0); -- Trap cause.
  
  -- Array types for the above subtypes.
  type rvex_opcode_array        is array (natural range <>) of rvex_opcode_type;
  type rvex_gpRegAddr_array     is array (natural range <>) of rvex_gpRegAddr_type;
  type rvex_brRegAddr_array     is array (natural range <>) of rvex_brRegAddr_type;
  type rvex_brRegData_array     is array (natural range <>) of rvex_brRegData_type;
  type rvex_2bit_array          is array (natural range <>) of rvex_2bit_type;
  type rvex_3bit_array          is array (natural range <>) of rvex_3bit_type;
  type rvex_4bit_array          is array (natural range <>) of rvex_4bit_type;
  type rvex_sylStatus_array     is array (natural range <>) of rvex_sylStatus_type;
  type rvex_limmh_array         is array (natural range <>) of rvex_limmh_type;
  type rvex_trap_array          is array (natural range <>) of rvex_trap_type;
  
  -----------------------------------------------------------------------------
  -- Constants which don't belong elsewhere
  -----------------------------------------------------------------------------
  -- When enabled, a list of strings will be generated pretty much each cycle
  -- with human-readable information about what the core is doing. Disabling
  -- this might save some computation time and thus speed up simulation.
  constant GEN_VHDL_SIM_INFO    : boolean := true;
  
  -- When false, a simulation-only model of the general purpose register file
  -- is used to speed up simulation and make it easier to see what the actual
  -- state of the memory is. When true, the synthesized general purpose
  -- register file is used for simulation.
  constant SIM_FULL_GPREG_FILE  : boolean := true;
  
  -- Throughout the rvex core, std_logic 'U' values are used to indicate values
  -- which are not valid yet. As these kinds of signals should never be used,
  -- this is not a problem for synthesis, and helps discover undefined things
  -- leaking into the datapaths somehow during simulation. This does however
  -- result in metavalue spam from numeric_std. If you would like to prevent
  -- this spam, or have some kind of synthesis tool which does not substitute
  -- 'U' with something real automatically, you can change the value used for
  -- undefined values to '0' here.
  constant RVEX_UNDEF           : std_logic := 'U';
  
  -----------------------------------------------------------------------------
  -- General purpose register file read/write ports
  -----------------------------------------------------------------------------
  -- These records describe the general purpose register file read and write
  -- ports, along with forwarding information. Unlike most other signals in the
  -- design, these need to be placed in records because we need array types for
  -- them and the size of the records themselves depends on pipeline
  -- configuration.
  
  -- General purpose register file read port.
  type pl2gpreg_readPort_type is record
    
    -- Read address for all stages which receive forwarding information.
    addr                        : rvex_gpRegAddr_array(S_RD to S_FW);
    
  end record;

  type gpreg2pl_readPort_type is record
    
    -- Forwarded read data for all stages which are forwarded to. Valid
    -- indicates whether the contents of data are meaningful; when valid is
    -- low, the value from the previous pipeline stage should be used.
    data                        : rvex_data_array(S_RD+L_RD to S_FW);
    valid                       : std_logic_vector(S_RD+L_RD to S_FW);
    
  end record;
  
  -- General purpose register file write port.
  type pl2gpreg_writePort_type is record
    
    -- Write address and data for all stages.
    addr                        : rvex_gpRegAddr_array(S_FIRST to S_WB+L_WB);
    data                        : rvex_data_array(S_FIRST to S_WB+L_WB);
    
    -- Whether the data in the WB stage should be committed to the register
    -- file.
    writeEnable                 : std_logic_vector(S_WB to S_WB);
    
    -- Whether the data in the associated stage should be forwarded to earlier
    -- stages. This has essentially the same meaning as writeEnable, although
    -- there are cases, for example when a trap occurs, where writeEnable needs
    -- to go low but forwardEnable is don't care. By making use of this don't
    -- care, the forwarding logic does not need to depend on trap information.
    -- It is very important that this is tied to zero for all stages before the
    -- first stage which actually computes something, because this determines
    -- how large the forwarding logic will become.
    forwardEnable               : std_logic_vector(S_FIRST to S_WB+L_WB);
    
  end record;
  
  -- Array types for the read and write ports.
  type pl2gpreg_readPort_array  is array (natural range <>) of pl2gpreg_readPort_type;
  type gpreg2pl_readPort_array  is array (natural range <>) of gpreg2pl_readPort_type;
  type pl2gpreg_writePort_array is array (natural range <>) of pl2gpreg_writePort_type;
  
  -----------------------------------------------------------------------------
  -- Branch and link register file read/write ports
  -----------------------------------------------------------------------------
  -- These records describe the branch and link register read and write ports
  -- along with forwarding information. Unlike most other signals in the
  -- design, these need to be placed in records because we need array types for
  -- them and the size of the records themselves depends on pipeline
  -- configuration.
  
  -- Branch/link register file read port.
  type cxreg2pl_readPort_type is record
    
    -- Forwarded read data for all stages which are forwarded to.
    brData                      : rvex_brRegData_array(S_SRD to S_SFW);
    linkData                    : rvex_address_array(S_SRD to S_SFW);
    
  end record;
  
  -- Branch/link register file write port.
  type pl2cxreg_writePort_type is record
    
    -- Write data for all registers and stages.
    brData                      : rvex_brRegData_array(S_FIRST to S_SWB);
    linkData                    : rvex_address_array(S_FIRST to S_SWB);
    
    -- Whether the data in the SWB stage should be committed to the register
    -- file.
    brWriteEnable               : rvex_brRegData_array(S_SWB to S_SWB);
    linkWriteEnable             : std_logic_vector(S_SWB to S_SWB);
    
    -- Whether the data in the associated stage should be forwarded to earlier
    -- stages. This has essentially the same meaning as writeEnable, although
    -- there are cases, for example when a trap occurs, where writeEnable needs
    -- to go low but forwardEnable is don't care. By making use of this don't
    -- care, the forwarding logic does not need to depend on trap information.
    -- It is very important that this is tied to zero for all stages before the
    -- first stage which actually computes something, because this determines
    -- how large the forwarding logic will become.
    brForwardEnable             : rvex_brRegData_array(S_FIRST to S_SWB);
    linkForwardEnable           : std_logic_vector(S_FIRST to S_SWB);
    
  end record;
  
  -- Array types for the read and write ports.
  type cxreg2pl_readPort_array  is array (natural range <>) of cxreg2pl_readPort_type;
  type pl2cxreg_writePort_array is array (natural range <>) of pl2cxreg_writePort_type;
  
  -----------------------------------------------------------------------------
  -- Breakpoint information record
  -----------------------------------------------------------------------------
  -- This record contains breakpoint information for the BRK unit.
  type cxreg2pl_breakpoint_info_type is record
    
    -- Breakpoint addresses. Depending on generic configuration, only a subset
    -- of these are used.
    addr                        : rvex_address_array(3 downto 0);
    
    -- Configuration for each breakpoint. The encoding is as follows:
    --  - 00 -> breakpoint disabled.
    --  - 01 -> instruction breakpoint.
    --  - 10 -> data write breakpoint.
    --  - 11 -> data access breakpoint.
    cfg                         : rvex_2bit_array(3 downto 0);
    
  end record;
  
  -- Array type for the above.
  type cxreg2pl_breakpoint_info_array is array (natural range <>) of cxreg2pl_breakpoint_info_type;
  
  -----------------------------------------------------------------------------
  -- Trace information records
  -----------------------------------------------------------------------------
  -- Raw trace information from pipelane to trace unit.
  type pl2trace_data_type is record
    
    -- Whether the instruction being represented was committed or not.
    valid                       : std_logic;
    
    -- Whether this is the last syllable in the bundle. This is not simply the
    -- stop bit from the raw syllables; it is processed by the stop bit routing
    -- in such a way that exactly one lane within a coupled group has this bit
    -- set.
    stop                        : std_logic;
    
    -- High when this lane contains an active branch unit.
    pc_enable                   : std_logic;
    
    -- PC of the bundle being executed in this pipelane.
    pc_PC                       : rvex_address_type;
    
    -- High when the given PC is not sequential w.r.t. the previous PC and
    -- should thus always be traced.
    pc_isBranch                 : std_logic;
    
    -- High when the next PC will not be sequential w.r.t. the current PC and
    -- should thus always be traced.
    pc_isBranching              : std_logic;
    
    -- High when this instruction performed a memory access.
    mem_enable                  : std_logic;
    
    -- Address of the memory operation, if mem_enable is high.
    mem_address                 : rvex_address_type;
    
    -- Write enable bits for the memory access, if mem_enable is high. When all
    -- these are zero, a read operation is implied.
    mem_writeMask               : rvex_mask_type;
    
    -- Data written to the memory, if mem_enable is high and mem_writeMask is
    -- nonzero.
    mem_writeData               : rvex_data_type;
    
    -- High when a general purpose register was written.
    reg_gpEnable                : std_logic;
    
    -- Address of the general purpose register which was written, if any.
    reg_gpAddress               : rvex_gpRegAddr_type;
    
    -- Whether the link register was written.
    reg_linkEnable              : std_logic;
    
    -- Data written to the general purpose or link register if gprl_enable is
    -- high.
    reg_intData                 : rvex_data_type;
    
    -- High when the indexed branch register was written by this instruction.
    reg_brEnable                : rvex_brRegData_type;
    
    -- Data written to the indexed branch register if br_enable is high.
    reg_brData                  : rvex_brRegData_type;
    
    -- Whether the current instruction is the first in the trap handler, i.e. a
    -- trap has been handled.
    trap_enable                 : std_logic;
    
    -- Trap cause of the trap handled by this instruction, if trap_enable is
    -- high.
    trap_cause                  : rvex_trap_type;
    
    -- Trap point of the trap handled by this instruction, if trap_enable is
    -- high.
    trap_point                  : rvex_address_type;
    
    -- Trap argument of the trap handled by this instruction, if trap_enable is
    -- high.
    trap_arg                    : rvex_address_type;
    
    -- Cache status flags from the cache block associated with this lane.
    cache_status                : rvex_cacheStatus_type;
    
    -- Whether an instruction fetch was performed or not.
    instr_enable                : std_logic;
    
    -- The syllable as it was fetched, valid when instr_enable is high.
    instr_syllable              : rvex_syllable_type;
    
  end record;
  
  -- Array type for the above.
  type pl2trace_data_array is array (natural range <>) of pl2trace_data_type;
  
end core_intIface_pkg;

package body core_intIface_pkg is
end core_intIface_pkg;
