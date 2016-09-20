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
use rvex.core_opcodeAlu_pkg.all;

--=============================================================================
-- This entity contains the ALU (arithmetic logic unit) for a pipelane.
-------------------------------------------------------------------------------
entity core_alu is
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
    pl2alu_opcode               : in  rvex_opcode_array(S_ALU to S_ALU);
    
    -- 32-bit operands.
    pl2alu_op1                  : in  rvex_data_array(S_ALU to S_ALU);
    pl2alu_op2                  : in  rvex_data_array(S_ALU to S_ALU);
    
    -- 1-bit branch register operand.
    pl2alu_opBr                 : in  std_logic_vector(S_ALU to S_ALU);
    
    ---------------------------------------------------------------------------
    -- Outputs
    ---------------------------------------------------------------------------
    -- 32-bit add unit output, regardless of operation. This saves a couple mux
    -- stages when only the adder is needed by other hardware, for example by
    -- the memory unit.
    alu2pl_resultAdd            : out rvex_data_array(S_ALU+L_ALU1 to S_ALU+L_ALU1);
    
    -- 32-bit output.
    alu2pl_result               : out rvex_data_array(S_ALU+L_ALU1+L_ALU2 to S_ALU+L_ALU1+L_ALU2);
    
    -- 1-bit branch register output.
    alu2pl_resultBr             : out std_logic_vector(S_ALU+L_ALU1+L_ALU2 to S_ALU+L_ALU1+L_ALU2)
    
  );
end core_alu;

--=============================================================================
architecture Behavioral of core_alu is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Operation execution state vector
  -----------------------------------------------------------------------------
  -- Operation state record. This contains the full state of any possible
  -- operation and inputs.
  type operationState_type is record
    
    -- Operands and control signals for each phase.
    ctrl                        : aluCtrlSignals_type;
    op1                         : rvex_data_type;
    op2                         : rvex_data_type;
    opBr                        : std_logic;
    
    -- Muxed input operands.
    op1Muxed                    : std_logic_vector(32 downto 0);
    op2Muxed                    : std_logic_vector(32 downto 0);
    opBrMuxed                   : std_logic;
    
    -- Adder arithmetic unit outputs. CarryOut is the 33rd bit of the adder.
    adderResult                 : rvex_data_type;
    adderCarryOut               : std_logic;
    
    -- Bitwise operation outputs. The bitwise operation unit can perform
    -- bitwise and, bitwise or, bitwise xor, select, bit testing and bit
    -- setting. It uses the branch operand to determine whether to set a bit
    -- high or low. The second operand is used to index the bits in the first
    -- operand for bit selection operations. For select operations, operand 1
    -- is chosen when the branch input is high, operand 2 when it is low.
    bitwiseResult               : rvex_data_type;
    bitTestResult               : std_logic;
    
    -- Barrel shifter result.
    shiftResult                 : rvex_data_type;
    
    -- Count-leading-zeros unit result.
    clzResult                   : rvex_data_type;
    
    -- Compare unit 1 result. This compare unit will compare operand 1 either
    -- with operand 2 or with zero.
    cmp1Result                  : std_logic;
    
    -- Compare unit 2 result. This compare unit will compare operand 2 with
    -- zero.
    cmp2Result                  : std_logic;
    
    -- Results.
    result                      : rvex_data_type;
    resultBr                    : std_logic;
    
  end record;
  
  -- Initial/reset state for the operation state record.
  constant operationState_init  : operationState_type := (
    ctrl                        => ALU_CTRL_NOP,
    opBr                        => RVEX_UNDEF,
    opBrMuxed                   => RVEX_UNDEF,
    adderCarryOut               => RVEX_UNDEF,
    bitTestResult               => RVEX_UNDEF,
    cmp1Result                  => RVEX_UNDEF,
    cmp2Result                  => RVEX_UNDEF,
    resultBr                    => RVEX_UNDEF,
    op1Muxed                    => (others => RVEX_UNDEF),
    op2Muxed                    => (others => RVEX_UNDEF),
    others                      => (others => RVEX_UNDEF)
  );
  
  -- The operation state record defined above is used for the internal pipeline
  -- registers. Note that this might instantiate unused registers which will be
  -- optimized away during synthesis.
  type operationState_array is array (natural range <>) of operationState_type;
  
  -- Execution phase definitions.
  constant P_OM                 : natural := 1; -- Apply Operand Mux operations.
  constant P_AR                 : natural := 2; -- Perform ARithmetic.
  constant P_SEL                : natural := 3; -- SELect between arithmetic outputs.
  
  -- Number of execution phases (= last phase).
  constant NUM_PHASES           : natural := P_SEL;
  
  -- Internal execution phase inputs and outputs. The indexes respect the
  -- execution phase indices. si contains the inputs for an execution phase,
  -- so contains the outputs. Depending on configuration, there may or may not
  -- be registers between si(n) and so(n-1).
  signal si                     : operationState_array(1 to NUM_PHASES) := (others => operationState_init);
  signal so                     : operationState_array(1 to NUM_PHASES) := (others => operationState_init);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Check configuration
  -----------------------------------------------------------------------------
  assert (L_ALU1 = 0) or (L_ALU1 = 1)
    report "Latency for ALU phase 1 (L_ALU1) must be set to 0 or 1 in "
         & "pipeline_pkg.vhd."
    severity failure;
  
  assert (L_ALU2 = 0) or (L_ALU2 = 1)
    report "Latency for ALU phase 2 (L_ALU2) must be set to 0 or 1 in "
         & "pipeline_pkg.vhd."
    severity failure;
  
  assert L_ALU = L_ALU1 + L_ALU2
    report "Total latency for the ALU must match sum of phase latencies."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Prepare execution phase 1 (operand mux)
  -----------------------------------------------------------------------------
  -- Simply copy the operands into the record.
  si(P_OM).op1  <= pl2alu_op1(S_ALU);
  si(P_OM).op2  <= pl2alu_op2(S_ALU);
  si(P_OM).opBr <= pl2alu_opBr(S_ALU);
  
  -- Decode the control signals based on the opcode.
  si(P_OM).ctrl <= OPCODE_TABLE(vect2uint(pl2alu_opcode(S_ALU))).aluCtrl;
  
  -----------------------------------------------------------------------------
  -- Execute phase 1 (operand mux)
  -----------------------------------------------------------------------------
  operand_mux_execute: process (si(P_OM)) is
  begin
    
    -- Forward by default.
    so(P_OM) <= si(P_OM);
    
    -- Perform operation for operand 1.
    case si(P_OM).ctrl.op1Mux is
      when EXTEND32 => 
        so(P_OM).op1Muxed(32 downto 32) <= (others => si(P_OM).op1(31) and not si(P_OM).ctrl.unsignedOp);
        so(P_OM).op1Muxed(31 downto  0) <= si(P_OM).op1(31 downto 0);
        
      when EXTEND32INV =>
        so(P_OM).op1Muxed(32 downto 32) <= (others => not (si(P_OM).op1(31) and not si(P_OM).ctrl.unsignedOp));
        so(P_OM).op1Muxed(31 downto  0) <= not si(P_OM).op1(31 downto 0);
        
      when EXTEND16 =>
        so(P_OM).op1Muxed(32 downto 16) <= (others => si(P_OM).op1(15) and not si(P_OM).ctrl.unsignedOp);
        so(P_OM).op1Muxed(15 downto  0) <= si(P_OM).op1(15 downto 0);
        
      when EXTEND8 =>
        so(P_OM).op1Muxed(32 downto  8) <= (others => si(P_OM).op1(7) and not si(P_OM).ctrl.unsignedOp);
        so(P_OM).op1Muxed( 7 downto  0) <= si(P_OM).op1(7 downto 0);
        
      when SHL1 =>
        so(P_OM).op1Muxed(32 downto  1) <= si(P_OM).op1(31 downto 0);
        so(P_OM).op1Muxed( 0 downto  0) <= (others => '0');
        
      when SHL2 =>
        so(P_OM).op1Muxed(32 downto  2) <= si(P_OM).op1(30 downto 0);
        so(P_OM).op1Muxed( 1 downto  0) <= (others => '0');

      when SHL3 =>
        so(P_OM).op1Muxed(32 downto  3) <= si(P_OM).op1(29 downto 0);
        so(P_OM).op1Muxed( 2 downto  0) <= (others => '0');

      when SHL4 =>
        so(P_OM).op1Muxed(32 downto  4) <= si(P_OM).op1(28 downto 0);
        so(P_OM).op1Muxed( 3 downto  0) <= (others => '0');
      
      when others =>
        so(P_OM).op1Muxed(32 downto  0) <= (others => 'X');
        
    end case;
    
    -- Perform operation for operand 2.
    case si(P_OM).ctrl.op2Mux is
      when EXTEND32 => 
        so(P_OM).op2Muxed(32 downto 32) <= (others => si(P_OM).op2(31) and not si(P_OM).ctrl.unsignedOp);
        so(P_OM).op2Muxed(31 downto  0) <= si(P_OM).op2(31 downto 0);
        
      when ZERO =>
        so(P_OM).op2Muxed(32 downto  0) <= (others => '0');
        
      when others =>
        so(P_OM).op2Muxed(32 downto  0) <= (others => 'X');
        
    end case;
    
    -- Perform operation for branch register operand.
    case si(P_OM).ctrl.opBrMux is
      when PASS   => so(P_OM).opBrMuxed <= si(P_OM).opBr;
      when INVERT => so(P_OM).opBrMuxed <= not si(P_OM).opBr;
      when TRUE   => so(P_OM).opBrMuxed <= '1';
      when FALSE  => so(P_OM).opBrMuxed <= '0';
      when others => so(P_OM).opBrMuxed <= 'X';
    end case;
    
    -- Perform some additional operations for DIVS.
    if si(P_OM).ctrl.divs = '1' then
      
      -- For proper DIVS operation, the following needs to be done:
      --   op1Muxed  := uint32_t(op1 << 1) | opBr
      --   op2Muxed  := (op1 >> 31) ? op2 : ~op2
      --   opBrMuxed := (op1 >> 31) ? 0   : 1
      -- We assume that the operand 1 mux is set to SHL1 so we only need to
      -- override the LSB with the branch operand.
      so(P_OM).op1Muxed(0) <= si(P_OM).opBr;
      if si(P_OM).op1(31) = '1' then
        so(P_OM).op2Muxed <= "0" & si(P_OM).op2;
        so(P_OM).opBrMuxed <= '0';
      else
        so(P_OM).op2Muxed <= "1" & (not si(P_OM).op2);
        so(P_OM).opBrMuxed <= '1';
      end if;
      
    end if;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Phase 1 to phase 2 forwarding
  -----------------------------------------------------------------------------
  phase_1_to_2_regs: if L_ALU1 /= 0 generate
    process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          si(P_AR) <= operationState_init;
        elsif clkEn = '1' and stall = '0' then
          si(P_AR) <= so(P_OM);
        end if;
      end if;
    end process;
  end generate;
  
  phase_1_to_2_noregs: if L_ALU1 = 0 generate
    si(P_AR) <= so(P_OM);
  end generate;
  
  -----------------------------------------------------------------------------
  -- Execute phase 2 (arithmetic)
  -----------------------------------------------------------------------------
  arithmetic_execute: process (si(P_AR)) is
    variable carry_vect         : std_logic_vector(0 downto 0);
    variable adderResult        : unsigned(32 downto 0);
    variable shift_s            : rvex_data_type;
    variable shiftExtend        : std_logic;
    variable cmpOp2             : rvex_data_type;
    variable count              : natural range 0 to 32;
  begin
    
    -- Forward by default.
    so(P_AR) <= si(P_AR);
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- 33-bit adder unit
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Perform the addition.
    carry_vect := (others => si(P_AR).opBrMuxed);
    adderResult := vect2unsigned(si(P_AR).op1Muxed)
                 + vect2unsigned(si(P_AR).op2Muxed)
                 + vect2unsigned(carry_vect);
    
    -- Extract value and carry.
    so(P_AR).adderResult <= std_logic_vector(adderResult(31 downto 0));
    so(P_AR).adderCarryOut <= adderResult(32);
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Bitwise arithmetic unit
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    case si(P_AR).ctrl.bitwiseOp is
      when BITW_AND =>
        so(P_AR).bitwiseResult <= si(P_AR).op1Muxed(31 downto 0)
                              and si(P_AR).op2Muxed(31 downto 0);
      
      when BITW_OR =>
        so(P_AR).bitwiseResult <= si(P_AR).op1Muxed(31 downto 0)
                               or si(P_AR).op2Muxed(31 downto 0);
      
      when BITW_XOR =>
        so(P_AR).bitwiseResult <= si(P_AR).op1Muxed(31 downto 0)
                              xor si(P_AR).op2Muxed(31 downto 0);
      
      when SET_BIT =>
        so(P_AR).bitwiseResult <= si(P_AR).op1Muxed(31 downto 0);
        if vect2unsigned(si(P_AR).op2Muxed(15 downto 5)) = 0 then
          so(P_AR).bitwiseResult(
            vect2uint(si(P_AR).op2Muxed(4 downto 0))
          ) <= si(P_AR).opBrMuxed;
        end if;
      
      when others =>
        so(P_AR).bitwiseResult <= (others => 'X');
      
    end case;
    
    -- Perform bit test regardless of selected operation.
    if vect2unsigned(si(P_AR).op2Muxed(15 downto 5)) = 0 then
      so(P_AR).bitTestResult <= si(P_AR).op1Muxed(
        vect2uint(si(P_AR).op2Muxed(4 downto 0))
      );
    else
      so(P_AR).bitTestResult <= '0';
    end if;
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Barrel shifter unit
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Swap input if we're shifting left, so the shifter only needs to be able
    -- to shift right. Shifting can be performed on the input operands without
    -- muxing because no special operations are ever done on the input before
    -- shifting.
    if si(P_AR).ctrl.shiftLeft = '1' then
      for i in 0 to 31 loop
        shift_s(i) := si(P_AR).op1(31 - i);
      end loop;
    else
      shift_s := si(P_AR).op1(31 downto 0);
    end if;
    
    -- Determine what to extend the value with.
    shiftExtend := si(P_AR).op1(31) and not si(P_AR).ctrl.unsignedOp;
    
    -- Explicitely instantiate barrel shifter logic.
    if si(P_AR).op2(7 downto 5) = "000" then
      if si(P_AR).op2(4) = '1' then
        shift_s(15 downto  0) := shift_s(31 downto 16);
        shift_s(31 downto 16) := (others => shiftExtend);
      end if;
      if si(P_AR).op2(3) = '1' then
        shift_s(23 downto  0) := shift_s(31 downto  8);
        shift_s(31 downto 24) := (others => shiftExtend);
      end if;
      if si(P_AR).op2(2) = '1' then
        shift_s(27 downto  0) := shift_s(31 downto  4);
        shift_s(31 downto 28) := (others => shiftExtend);
      end if;
      if si(P_AR).op2(1) = '1' then
        shift_s(29 downto  0) := shift_s(31 downto  2);
        shift_s(31 downto 30) := (others => shiftExtend);
      end if;
      if si(P_AR).op2(0) = '1' then
        shift_s(30 downto  0) := shift_s(31 downto  1);
        shift_s(31 downto 31) := (others => shiftExtend);
      end if;
    else
      shift_s := (others => shiftExtend);
    end if;
    
    -- Swap again if we were shifting left.
    if si(P_AR).ctrl.shiftLeft = '1' then
      for i in 0 to 31 loop
        so(P_AR).shiftResult(i) <= shift_s(31 - i);
      end loop;
    else
      so(P_AR).shiftResult <= shift_s;
    end if;
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Count-leading-zeros unit
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- CLZ can be performed on the input operand directly, no input muxing
    -- operations are used.
    count := 0;
    for i in 31 downto 0 loop
      if si(P_AR).op1(i) = '0' then
        count := count + 1;
      else
        exit;
      end if;
    end loop;
    so(P_AR).clzResult <= uint2vect(count, 32);
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Compare unit 1
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Based on the compare control signal, compare operand 1 with 2 or
    -- compare operand 1 with zero. When comparing 1 and 2 for compare
    -- operations, bitwise-invert input 2 while we're muxing, because input
    -- 1 will also be inverted in this case for the subtractor part of the
    -- comparison.
    if si(P_AR).ctrl.compare = '1' then
      cmpOp2 := not si(P_AR).op2Muxed(31 downto 0);
    else
      cmpOp2 := (others => '0');
    end if;
    if si(P_AR).op1Muxed(31 downto 0) = cmpOp2 then
      so(P_AR).cmp1Result <= '1';
    else
      so(P_AR).cmp1Result <= '0';
    end if;
    
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Compare unit 2
    -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    -- Compare operand 2 with 0.
    if vect2unsigned(si(P_AR).op2Muxed(31 downto 0)) = 0 then
      so(P_AR).cmp2Result <= '1';
    else
      so(P_AR).cmp2Result <= '0';
    end if;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Forward phase 2 outputs
  -----------------------------------------------------------------------------
  alu2pl_resultAdd(S_ALU+L_ALU1) <= so(P_AR).adderResult;
  
  -----------------------------------------------------------------------------
  -- Phase 2 to phase 3 forwarding
  -----------------------------------------------------------------------------
  phase_2_to_3_regs: if L_ALU2 /= 0 generate
    process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          si(P_SEL) <= operationState_init;
        elsif clkEn = '1' and stall = '0' then
          si(P_SEL) <= so(P_AR);
        end if;
      end if;
    end process;
  end generate;
  
  phase_2_to_3_noregs: if L_ALU2 = 0 generate
    si(P_SEL) <= so(P_AR);
  end generate;
  
  -----------------------------------------------------------------------------
  -- Execute phase 3 (output muxing)
  -----------------------------------------------------------------------------
  output_mux_execute: process (si(P_SEL)) is
    variable brResult_v         : std_logic;
  begin
    
    -- Forward by default.
    so(P_SEL) <= si(P_SEL);
    
    -- Decode and select branch result. Store it in a variable, because the
    -- integer result mux uses it.
    case si(P_SEL).ctrl.brResultMux is
      
      -- Passthrough.
      when PASS =>
        brResult_v := si(P_SEL).opBrMuxed;
        
      -- Logic operations. cmpxResult and cmpxResult are set to operandx == 0
      -- by the compare logic, so we need a not gate in the inputs because
      -- nonzero is true.
      when LOGIC_AND =>
        brResult_v := (not si(P_SEL).cmp1Result)
                  and (not si(P_SEL).cmp2Result);
        
      when LOGIC_NAND =>
        brResult_v := (not si(P_SEL).cmp1Result)
                 nand (not si(P_SEL).cmp2Result);
        
      when LOGIC_OR =>
        brResult_v := (not si(P_SEL).cmp1Result)
                   or (not si(P_SEL).cmp2Result);
        
      when LOGIC_NOR =>
        brResult_v := (not si(P_SEL).cmp1Result)
                  nor (not si(P_SEL).cmp2Result);
      
      -- Comparison operations. cmp1Result holds operand1 == operand2.
      -- adderCarryOut contains operand1 > operand2, because the adder
      -- performs operand2 - operand1, which generates a carry in exactly that
      -- case.
      when CMP_EQ =>
        brResult_v := si(P_SEL).cmp1Result;
        
      when CMP_NE =>
        brResult_v := not si(P_SEL).cmp1Result;
        
      when CMP_GT =>
        brResult_v := si(P_SEL).adderCarryOut;
        
      when CMP_GE =>
        brResult_v := si(P_SEL).cmp1Result or si(P_SEL).adderCarryOut;
        
      when CMP_LT =>
        brResult_v := si(P_SEL).adderCarryOut nor si(P_SEL).cmp1Result;
        
      when CMP_LE =>
        brResult_v := not si(P_SEL).adderCarryOut;
      
      -- Carry out from the adder. We need to use the 32 bit carry out here so
      -- ADDCG operations can be properly cascaded for 64 bit and larger
      -- integer operations.
      when CARRY_OUT =>
        brResult_v := si(P_SEL).adderCarryOut;
      
      -- Bit test output.
      when TBIT =>
        brResult_v := si(P_SEL).bitTestResult;
        
      when TBITF =>
        brResult_v := not si(P_SEL).bitTestResult;
        
      -- DIVS output. This is hardwired to bit 31 of operand 1.
      when DIVS =>
        brResult_v := si(P_SEL).op1(31);
      
      when others =>
        brResult_v := 'X';
      
    end case;
    
    -- Forward the branch result.
    so(P_SEL).resultBr <= brResult_v;
    
    -- Select integer result.
    case si(P_SEL).ctrl.intResultMux is
        
      -- Forward the result from the adder unit.
      when ADDER =>
        so(P_SEL).result <= si(P_SEL).adderResult;
        
      -- Forward the result from the bitwise operation unit.
      when BITWISE =>
        so(P_SEL).result <= si(P_SEL).bitwiseResult;
      
      -- Forward the result from the shift unit.
      when SHIFTER =>
        so(P_SEL).result <= si(P_SEL).shiftResult;
      
      -- Forward the result from the CLZ unit.
      when CLZ =>
        so(P_SEL).result <= si(P_SEL).clzResult;
      
      -- Output either operand 1 unchanged or operand 2 unchanged, based on the
      -- branch output. Used for the SLCT and MIN/MAX operations.
      when OP_SEL =>
        if brResult_v = '1' then
          so(P_SEL).result <= si(P_SEL).op1;
        else
          so(P_SEL).result <= si(P_SEL).op2;
        end if;
      
      -- Forward the branch output as a 32 bit integer.
      when BOOL =>
        if brResult_v = '1' then
          so(P_SEL).result <= (0 => '1', others => '0');
        else
          so(P_SEL).result <= (others => '0');
        end if;
      
      when others =>
        so(P_SEL).result <= (others => 'X');
      
    end case;
  end process;
  
  -----------------------------------------------------------------------------
  -- Forward phase 3 outputs
  -----------------------------------------------------------------------------
  alu2pl_result   (S_ALU+L_ALU1+L_ALU2) <= so(P_SEL).result;
  alu2pl_resultBr (S_ALU+L_ALU1+L_ALU2) <= so(P_SEL).resultBr;
  
end Behavioral;

