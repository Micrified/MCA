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
use rvex.core_opcode_pkg.all;
use rvex.core_opcodeMultiplier_pkg.all;

--=============================================================================
-- This entity contains the optional multiply unit for a pipelane.
-------------------------------------------------------------------------------
entity core_mulu is
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
    -- Operand and control inputs
    ---------------------------------------------------------------------------
    -- Opcode.
    pl2mulu_opcode              : in  rvex_opcode_array(S_MUL to S_MUL);
    
    -- 32-bit operands.
    pl2mulu_op1                 : in  rvex_data_array(S_MUL to S_MUL);
    pl2mulu_op2                 : in  rvex_data_array(S_MUL to S_MUL);
    
    ---------------------------------------------------------------------------
    -- Outputs
    ---------------------------------------------------------------------------
    -- 32-bit output.
    mulu2pl_result              : out rvex_data_array(S_MUL+L_MUL to S_MUL+L_MUL)
    
  );
  
  -- Hint to XST that we want it to retime the registers in this entity to get
  -- a balanced pipeline.
  attribute mult_style              : string;
  attribute mult_style of core_mulu : entity is "pipe_block";
  
end core_mulu;

--=============================================================================
architecture Behavioral of core_mulu is
--=============================================================================
  
  -- Opcode delay line.
  signal opcode                 : rvex_opcode_array(S_MUL to S_MUL+L_MUL);
  
  -- Decoded control signals.
  signal ctrl_inMux             : multiplierCtrlSignals_array(S_MUL to S_MUL);
  signal ctrl_outMux            : multiplierCtrlSignals_array(S_MUL+L_MUL to S_MUL+L_MUL);
  
  -- Operand 1 mux output.
  subtype op1mux_type is std_logic_vector(32 downto 0);
  type op1mux_array is array (natural range <>) of op1mux_type;
  signal op1mux                 : op1mux_array(S_MUL to S_MUL+L_MUL1);
  
  -- Operand 2 mux output.
  subtype op2mux_type is std_logic_vector(16 downto 0);
  type op2mux_array is array (natural range <>) of op2mux_type;
  signal op2mux                 : op2mux_array(S_MUL to S_MUL+L_MUL1);
  
  -- Multiplication result before muxing.
  subtype result_type is std_logic_vector(49 downto 0);
  type result_array is array (natural range <>) of result_type;
  signal result                 : result_array(S_MUL+L_MUL1 to S_MUL+L_MUL);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Check configuration
  -----------------------------------------------------------------------------
  assert L_MUL = L_MUL1 + L_MUL2
    report "Pipeline configuration: multiply unit latency (L_MUL) must be set "
         & "to L_MUL1 + L_MUL2."
    severity failure;
  
  assert L_MUL1 <= 2
    report "XST can only absorb two pipeline stages before the multiplier "
         & "into the multiplier itself; it does not make sense to make the "
         & "longer."
    severity warning;
  
  assert L_MUL2 <= 2
    report "XST can only absorb two pipeline stages after the multiplier "
         & "into the multiplier itself; it does not make sense to make the "
         & "longer."
    severity warning;
  
  -----------------------------------------------------------------------------
  -- Generate pipeline registers
  -----------------------------------------------------------------------------
  regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        opcode(S_MUL+1 to S_MUL+L_MUL) <= (others => (others => '0'));
        op1mux(S_MUL+1 to S_MUL+L_MUL1) <= (others => (others => '0'));
        op2mux(S_MUL+1 to S_MUL+L_MUL1) <= (others => (others => '0'));
        result(S_MUL+L_MUL1+1 to S_MUL+L_MUL) <= (others => (others => '0'));
      elsif clkEn = '1' and stall = '0' then
        opcode(S_MUL+1 to S_MUL+L_MUL) <= opcode(S_MUL to S_MUL+L_MUL-1);
        op1mux(S_MUL+1 to S_MUL+L_MUL1) <= op1mux(S_MUL to S_MUL+L_MUL1-1);
        op2mux(S_MUL+1 to S_MUL+L_MUL1) <= op2mux(S_MUL to S_MUL+L_MUL1-1);
        result(S_MUL+L_MUL1+1 to S_MUL+L_MUL) <= result(S_MUL+L_MUL1 to S_MUL+L_MUL-1);
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Generate opcode decoding logic
  -----------------------------------------------------------------------------
  -- Copy the opcode into the delay line.
  opcode(S_MUL) <= pl2mulu_opcode(S_MUL);
  
  -- Decode in the first stage (for input muxing) and the final stage (for
  -- output muxing).
  ctrl_inMux(S_MUL)
    <= OPCODE_TABLE(vect2uint(opcode(S_MUL))).multiplierCtrl;
  
  ctrl_outMux(S_MUL+L_MUL)
    <= OPCODE_TABLE(vect2uint(opcode(S_MUL+L_MUL))).multiplierCtrl;
  
  -----------------------------------------------------------------------------
  -- Perform input muxing
  -----------------------------------------------------------------------------
  -- Perform muxing for operand 1.
  det_op1mux: process (ctrl_inMux, pl2mulu_op1) is
  begin
    case ctrl_inMux(S_MUL).op1sel is
      
      when LOW_HALF =>
        
        -- Select lower halfword.
        op1mux(S_MUL)(15 downto 0) <= pl2mulu_op1(S_MUL)(15 downto 0);
        
        -- Sign/zero extend.
        op1mux(S_MUL)(32 downto 16) <= (others => 
          pl2mulu_op1(S_MUL)(15) and not ctrl_inMux(S_MUL).op1unsigned
        );
        
      when HIGH_HALF =>
        
        -- Select upper halfword.
        op1mux(S_MUL)(15 downto 0) <= pl2mulu_op1(S_MUL)(31 downto 16);
        
        -- Sign/zero extend.
        op1mux(S_MUL)(32 downto 16) <= (others => 
          pl2mulu_op1(S_MUL)(31) and not ctrl_inMux(S_MUL).op1unsigned
        );
        
      when WORD =>
        
        -- Select the full word.
        op1mux(S_MUL)(31 downto 0) <= pl2mulu_op1(S_MUL)(31 downto 0);
        
        -- Sign/zero extend.
        op1mux(S_MUL)(32)
          <= pl2mulu_op1(S_MUL)(31) and not ctrl_inMux(S_MUL).op1unsigned;
        
    end case;
  end process;
  
  -- Perform muxing for operand 2.
  det_op2mux: process (ctrl_inMux, pl2mulu_op2) is
  begin
    case ctrl_inMux(S_MUL).op2sel is
      
      when LOW_HALF =>
        
        -- Select lower halfword.
        op2mux(S_MUL)(15 downto 0) <= pl2mulu_op2(S_MUL)(15 downto 0);
        
        -- Sign/zero extend.
        op2mux(S_MUL)(16)
          <= pl2mulu_op2(S_MUL)(15) and not ctrl_inMux(S_MUL).op2unsigned;
        
      when HIGH_HALF =>
        
        -- Select upper halfword.
        op2mux(S_MUL)(15 downto 0) <= pl2mulu_op2(S_MUL)(31 downto 16);
        
        -- Sign/zero extend.
        op2mux(S_MUL)(16)
          <= pl2mulu_op2(S_MUL)(31) and not ctrl_inMux(S_MUL).op2unsigned;
        
    end case;
  end process;
  
  -----------------------------------------------------------------------------
  -- Instantiate multiplier
  -----------------------------------------------------------------------------
  -- We let XST (or whatever synthesizer you're using) take complete care of
  -- this - we just perform a numeric_std signed multiplication.
  result(S_MUL+L_MUL1) <= std_logic_vector(
    vect2signed(op1mux(S_MUL+L_MUL1)) * vect2signed(op2mux(S_MUL+L_MUL1))
  );
  
  -----------------------------------------------------------------------------
  -- Perform output muxing
  -----------------------------------------------------------------------------
  det_result: process (ctrl_outMux, result) is
  begin
    case ctrl_outMux(S_MUL+L_MUL).resultSel is
      
      when PASS =>
        
        -- Passthrough without shifting.
        mulu2pl_result(S_MUL+L_MUL)(31 downto 0)
          <= result(S_MUL+L_MUL)(31 downto 0);
        
      when SHR16 =>
        
        -- Shift right 16 bits.
        mulu2pl_result(S_MUL+L_MUL)(31 downto 0)
          <= result(S_MUL+L_MUL)(47 downto 16);
        
      when SHR32 =>
        
        -- Shift right 32 bits and sign extend.
        mulu2pl_result(S_MUL+L_MUL)(15 downto 0)
          <= result(S_MUL+L_MUL)(47 downto 32);
        
        mulu2pl_result(S_MUL+L_MUL)(31 downto 16) <= (others =>
          result(S_MUL+L_MUL)(47)
        );
        
      when SHL16 =>
        
        -- Shift left by 16 bits.
        mulu2pl_result(S_MUL+L_MUL)(31 downto 16)
          <= result(S_MUL+L_MUL)(15 downto 0);
        
        mulu2pl_result(S_MUL+L_MUL)(15 downto 0) <= (others => '0');
        
    end case;
  end process;
  
end Behavioral;

