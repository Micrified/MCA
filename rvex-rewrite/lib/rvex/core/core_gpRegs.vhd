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
use rvex.core_pipeline_pkg.all;

--=============================================================================
-- This entity contains the general purpose register file and associated
-- forwarding logic.
-------------------------------------------------------------------------------
entity core_gpRegs is
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
    
    -- Active high stall signal for each lane group.
    stall                       : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);

    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : in  std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies the context associated with the indexed pipelane group.
    cfg2any_context             : in  rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -----------------------------------------------------------------------------
    -- Read and write ports
    -----------------------------------------------------------------------------
    -- Read ports. There's two for each lane. The read value is provided for all
    -- lanes which receive forwarding information.
    pl2gpreg_readPorts          : in  pl2gpreg_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
    gpreg2pl_readPorts          : out gpreg2pl_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
    
    -- Write ports and forwarding information. There's one write port for each
    -- lane.
    pl2gpreg_writePorts         : in  pl2gpreg_writePort_array(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Debug interface
    ---------------------------------------------------------------------------
    -- When claim is high (and stall is high, which will always be the case)
    -- one of the processor ports should be connected to the port below.
    creg2gpreg_claim            : in  std_logic;
    
    -- Register address and context.
    creg2gpreg_addr             : in  rvex_gpRegAddr_type;
    creg2gpreg_ctxt             : in  std_logic_vector(CFG.numContextsLog2-1 downto 0);
    
    -- Write command.
    creg2gpreg_writeEnable      : in  std_logic;
    creg2gpreg_writeData        : in  rvex_data_type;
    
    -- Read data returned one cycle after the claim.
    gpreg2creg_readData         : out rvex_data_type
    
  );
end core_gpRegs;

--=============================================================================
architecture Behavioral of core_gpRegs is
--=============================================================================
  
  -- This constant determines whether the block ram implementation (true) or
  -- the simulation only model thereof (false) is instantiated.
  constant INST_SYNTH_MEM         : boolean :=
    -- pragma translate_off
    SIM_FULL_GPREG_FILE and
    -- pragma translate_on
    true;
  
  -- 64 general purpose registers per context.
  constant NUM_REGS_PER_CTXT_LOG2 : natural := 6;
  constant NUM_REGS_LOG2          : natural := CFG.numContextsLog2 + NUM_REGS_PER_CTXT_LOG2;
  
  -- Two read ports and one write port per lane.
  constant NUM_READ_PORTS         : natural := 2*2**CFG.numLanesLog2;
  constant NUM_WRITE_PORTS        : natural := 2**CFG.numLanesLog2;
  
  -- Stall signal, delayed by one cycle.
  signal stall_r                  : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Internal signals connecting to the general purpose register memory banks.
  signal writeEnable              : std_logic_vector(NUM_WRITE_PORTS-1 downto 0);
  signal writeAddr                : rvex_address_array(NUM_WRITE_PORTS-1 downto 0);
  signal writeData                : rvex_data_array(NUM_WRITE_PORTS-1 downto 0);
  signal readAddr                 : rvex_address_array(NUM_READ_PORTS-1 downto 0);
  signal readData_comb            : rvex_data_array(NUM_READ_PORTS-1 downto 0);
  signal readData_reg             : rvex_data_array(NUM_READ_PORTS-1 downto 0);
  signal readData                 : rvex_data_array(NUM_READ_PORTS-1 downto 0);

--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Connect internal command signals to interface
  -----------------------------------------------------------------------------
  -- Connect read commands. The read result is connected through the forwarding
  -- logic.
  iface_connect_read_gen: for readPort in 0 to NUM_READ_PORTS-1 generate
    constant ADDR_UNUSED : std_logic_vector(31 downto NUM_REGS_LOG2) := (others => '0');
    constant laneGroup   : natural := lane2group(readPort / 2, CFG);
  begin
    
    -- Connect read address.
    readAddr(readPort)
      <= (
        
        -- Pipelane connection.
        ADDR_UNUSED
        & cfg2any_context(laneGroup)(CFG.numContextsLog2-1 downto 0)
        & pl2gpreg_readPorts(readPort).addr(S_RD)
        
      ) when creg2gpreg_claim = '0' or readPort /= 0 else (
        
        -- Debug override connection.
        ADDR_UNUSED
        & creg2gpreg_ctxt
        & creg2gpreg_addr
        
      );
    
  end generate;
  
  -- Connect write commands.
  iface_connect_write_gen: for writePort in 0 to NUM_WRITE_PORTS-1 generate
    constant ADDR_UNUSED : std_logic_vector(31 downto NUM_REGS_LOG2) := (others => '0');
    constant laneGroup   : natural := lane2group(writePort, CFG);
  begin
    
    -- Connect write address.
    writeAddr(writePort)
      <= (
        
        -- Pipelane connection.
        ADDR_UNUSED
        & cfg2any_context(laneGroup)(CFG.numContextsLog2-1 downto 0)
        & pl2gpreg_writePorts(writePort).addr(S_WB)
        
      ) when creg2gpreg_claim = '0' or writePort /= 0 else (
        
        -- Debug override connection.
        ADDR_UNUSED
        & creg2gpreg_ctxt
        & creg2gpreg_addr
        
      );
    
    -- Connect write data.
    writeData(writePort)
      <= (
        
        -- Pipelane connection.
        pl2gpreg_writePorts(writePort).data(S_WB)
        
      ) when creg2gpreg_claim = '0' or writePort /= 0 else (
        
        -- Debug override connection.
        creg2gpreg_writeData
        
      );
    
    -- Connect write enable.
    writeEnable(writePort)
      <= (
        
        -- Pipelane connection.
        pl2gpreg_writePorts(writePort).writeEnable(S_WB)
        and not stall(laneGroup)
        
      ) when creg2gpreg_claim = '0' or writePort /= 0 else (
        
        -- Debug override connection.
        creg2gpreg_writeEnable
        
      );
    
  end generate;
  
  -- Connect the debug override read data result to the read output of read
  -- port 1.
  gpreg2creg_readData <= readData_comb(0);
  
  -----------------------------------------------------------------------------
  -- Instantiate forwarding logic
  -----------------------------------------------------------------------------
  fwd_gen_stage: for stage in S_RD+L_RD to S_FW generate
    constant stagesToForward    : natural := S_WB+L_WB-stage;
    signal writeAddresses       : std_logic_vector(NUM_WRITE_PORTS * stagesToForward * NUM_REGS_PER_CTXT_LOG2 - 1 downto 0);
    signal writeDatas           : std_logic_vector(NUM_WRITE_PORTS * stagesToForward * 32 - 1 downto 0);
    signal writeEnables         : std_logic_vector(NUM_WRITE_PORTS * stagesToForward - 1 downto 0);
  begin
    
    -- Load the forwarding information into signals which are in the correct
    -- format for the forwarding logic.
    fwd_gen_stageIndices: for index in 0 to stagesToForward-1 generate
      fwd_gen_writePorts: for writePort in 0 to NUM_WRITE_PORTS-1 generate
        constant ei : natural := index * NUM_WRITE_PORTS + writePort;
        constant ai : natural := ei * NUM_REGS_PER_CTXT_LOG2;
        constant di : natural := ei * 32;
      begin
        
        writeAddresses(ai + NUM_REGS_PER_CTXT_LOG2 - 1 downto ai)
          <= pl2gpreg_writePorts(writePort).addr(stage + index + 1);
        
        writeDatas(di + 31 downto di)
          <= pl2gpreg_writePorts(writePort).data(stage + index + 1);
        
        writeEnables(ei)
          <= pl2gpreg_writePorts(writePort).forwardEnable(stage + index + 1);
        
      end generate;
    end generate;
    
    -- Generate a forwarding block for each read port.
    forwarding_gen: for readPort in 0 to NUM_READ_PORTS-1 generate
      signal forwarded          : std_logic;
      signal coupled            : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    begin
      
      -- Make use of the fact that coupled pipelanes always share the same
      -- context bits, so we don't have to do unnecessarily wide address
      -- matching when we have more than one context.
      fwd_coupled_gen: for lane in 0 to 2**CFG.numLanesLog2-1 generate
        coupled(lane) <= cfg2any_coupled(
          2**CFG.numLaneGroupsLog2 * lane2group(lane, CFG)
          + lane2group(readPort / 2, CFG)
        );
      end generate;
      
      -- Generate the forwarding for this stage and read port.
      forwarding_inst: entity rvex.core_forward
        generic map (
          ENABLE_FORWARDING     => CFG.forwarding,
          DATA_WIDTH            => 32,
          ADDRESS_WIDTH         => NUM_REGS_PER_CTXT_LOG2,
          NUM_LANES             => NUM_WRITE_PORTS,
          NUM_STAGES_TO_FORWARD => stagesToForward
        )
        port map (
          
          -- Register read connections.
          readAddress           => pl2gpreg_readPorts(readPort).addr(stage),
          readDataIn            => readData(readPort),
          readDataOut           => gpreg2pl_readPorts(readPort).data(stage),
          readDataForwarded     => forwarded,
          
          -- Queued write signals.
          writeAddresses        => writeAddresses,
          writeDatas            => writeDatas,
          writeEnables          => writeEnables,
          coupled               => coupled
          
        );
      
      -- Data is always valid in the stage where the data from the register
      -- file is valid, but is only valid in other stages when it comes from
      -- the forwarding logic.
      gpreg2pl_readPorts(readPort).valid(stage)
        <= '1' when stage = S_RD+L_RD else forwarded;
      
    end generate;
  end generate;

  -----------------------------------------------------------------------------
  -- Instantiate memory
  -----------------------------------------------------------------------------
  -- Block RAM based memory for synthesis.
  synth_mem_gen: if INST_SYNTH_MEM and CFG.gpRegImpl = RVEX_GPREG_IMPL_MEM generate
    synth_mem: entity rvex.core_gpRegs_mem
      generic map (
        NUM_REGS_LOG2           => NUM_REGS_LOG2,
        NUM_WRITE_PORTS         => NUM_WRITE_PORTS,
        NUM_READ_PORTS          => NUM_READ_PORTS
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Write ports.
        writeEnable             => writeEnable,
        writeAddr               => writeAddr,
        writeData               => writeData,
        
        -- Read ports.
        readAddr                => readAddr,
        readData                => readData_comb
        
      );
  end generate;
  
  simple_mem_gen: if INST_SYNTH_MEM and CFG.gpRegImpl = RVEX_GPREG_IMPL_SIMPLE generate
    synth_mem: entity rvex.core_gpRegs_simple
      generic map (
        NUM_REGS_LOG2           => NUM_REGS_LOG2,
        NUM_WRITE_PORTS         => NUM_WRITE_PORTS,
        NUM_READ_PORTS          => NUM_READ_PORTS
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Write ports.
        writeEnable             => writeEnable,
        writeAddr               => writeAddr,
        writeData               => writeData,
        
        -- Read ports.
        readAddr                => readAddr,
        readData                => readData_comb
        
      );
  end generate;

  -- Simulation only model of the block RAM based memory.
  sim_mem_gen: if not INST_SYNTH_MEM generate
    sim_mem: entity rvex.core_gpRegs_sim
      generic map (
        NUM_REGS_LOG2           => NUM_REGS_LOG2,
        NUM_WRITE_PORTS         => NUM_WRITE_PORTS,
        NUM_READ_PORTS          => NUM_READ_PORTS
      )
      port map (
        
        -- System control.
        reset                   => reset,
        clk                     => clk,
        clkEn                   => clkEn,
        
        -- Write ports.
        writeEnable             => writeEnable,
        writeAddr               => writeAddr,
        writeData               => writeData,
        
        -- Read ports.
        readAddr                => readAddr,
        readData                => readData_comb
        
      );
  end generate;
  
  -- The register file and forwarding system does not on its own respect
  -- stalls; it just always performs the request its given. For writes this is
  -- easily fixed by gating the write enable signal with the stall signal. For
  -- reads though, because they cross a pipeline stage, need to be
  -- synchronized; when the core performs a read and is stalled the cycle
  -- after, the read result needs to be stored temporarily for when the core
  -- is unstalled.
  read_port_stall_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        stall_r <= (others => '0');
        readData_reg <= (others => (others => '0'));
      elsif clkEn = '1' then
        stall_r <= stall;
        for prt in 0 to 2*2**CFG.numLanesLog2-1 loop
          if stall_r(lane2group(prt / 2, CFG)) = '0' then
            readData_reg(prt) <= readData_comb(prt);
          end if;
        end loop;
      end if;
    end if;
  end process;
  
  read_port_stall_mux_gen: for prt in 0 to 2*2**CFG.numLanesLog2-1 generate
    readData(prt)
      <= readData_comb(prt) when stall_r(lane2group(prt / 2, CFG)) = '0'
      else readData_reg(prt);
  end generate;
  
end Behavioral;

