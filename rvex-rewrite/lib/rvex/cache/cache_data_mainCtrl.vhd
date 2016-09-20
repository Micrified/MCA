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
use rvex.bus_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;

--=============================================================================
-- This entity contains the state machine which handles cache misses,
-- write-through accesses and bypass accesses for a data cache block.
-------------------------------------------------------------------------------
entity cache_data_mainCtrl is
--=============================================================================
  generic (
    
    -- Core configuration. Must be equal to the configuration presented to the
    -- rvex core connected to the cache.
    RCFG                        : rvex_generic_config_type := rvex_cfg;
    
    -- Cache configuration.
    CCFG                        : cache_generic_config_type := cache_cfg
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Clock input.
    clk                         : in  std_logic;
    
    -- Active high reset input.
    reset                       : in  std_logic;
    
    -- Active high clock enable input for the CPU domain.
    clkEnCPU                    : in  std_logic;
    
    -- Active high clock enable input for the bus domain.
    clkEnBus                    : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- CPU interface signals
    ---------------------------------------------------------------------------
    -- CPU address input, delayed by one cycle to sync up with hit.
    addr                        : in  rvex_address_type;
    
    -- CPU read enable signal, delayed by one cycle to sync up with hit.
    readEnable                  : in  std_logic;
    
    -- CPU read data output. Valid when clkEnCPU is high and stall is low.
    readData                    : out rvex_data_type;
    
    -- CPU write enable signal, delayed by one cycle to sync up with hit.
    writeEnable                 : in  std_logic;
    
    -- CPU write data, delayed by one cycle to sync up with hit.
    writeData                   : in  rvex_data_type;
    
    -- CPU write data byte mask, delayed by one cycle to sync up with hit.
    writeMask                   : in  rvex_mask_type;
    
    -- CPU bypass signal, delayed by one cycle to sync up with hit.
    bypass                      : in  std_logic;
    
    -- Stall input from the CPU.
    stall                       : in  std_logic;
    
    -- Reconfiguration blocking signal. When high, reconfiguration is not
    -- allowed because the cache block is busy.
    blockReconfig               : out std_logic;
    
    -- Stall output signal for write or bypass signals. Read miss stalls are
    -- computed in the mux/demux network.
    writeOrBypassStall          : out std_logic;
    
    -- Bus fault output. This is asserted when a bus fault occurs.
    busFault                    : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Mux control signals
    ---------------------------------------------------------------------------
    -- Update enable signal from the mux/demux logic signalling that the cache
    -- line which contains cpuAddr should be refreshed. While an update is in
    -- progress, cpuAddr is assumed to be stable. Governed by the clkEnCPU
    -- clock gate signal.
    updateEnable                : in  std_logic;
    
    -- Control signal from the mux/demux logic, indicating that this block
    -- should be the one to handle the write request. Synchronized with the
    -- hit signal like everything else.
    handleWrite                 : in  std_logic;
    
    -- Write selection priority. This is used to determine which of the cache
    -- blocks should handle writes by the mux/demux network.
    writePrio                   : out std_logic_vector(1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Cache memory interface signals
    ---------------------------------------------------------------------------
    -- Whether the cache memory is valid for the word requested by the CPU.
    hit                         : in  std_logic;
    
    -- Data read from the cache memory.
    cacheReadData               : in  rvex_data_type;
    
    -- Signals that the updateData should be written to the addressed line
    -- in the cache data memory in accordance with updateMask, that the tag
    -- must be updated and that the valid bit must be set.
    update                      : out std_logic;
    
    -- Write data for the cache data memory.
    updateData                  : out rvex_data_type;
    
    -- Write data for the cache data memory.
    updateMask                  : out rvex_mask_type;
    
    ---------------------------------------------------------------------------
    -- Main memory interface signals
    ---------------------------------------------------------------------------
    -- Connections to the memory bus. Governed by clkEnBus.
    cacheToBus                  : out bus_mst2slv_type;
    busToCache                  : in  bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Status signals
    ---------------------------------------------------------------------------
    -- This signal is high when this block is servicing or has serviced a
    -- write. It is reset when stall is low.
    servicedWrite               : out std_logic;
    
    -- This signal is high when a write is currently buffered.
    writeBuffered               : out std_logic
    
  );
end cache_data_mainCtrl;

--=============================================================================
architecture Behavioral of cache_data_mainCtrl is
--=============================================================================
  
  -- Control unit state machine state type.
  type controllerState_type is (
    STATE_IDLE, STATE_WRITE, STATE_UPDATE_1,
    STATE_UPDATE_2, STATE_BYPASS, STATE_WAIT_FOR_CPU
  );
  
  -- Current and next state machine state.
  signal state                  : controllerState_type;
  signal nextState              : controllerState_type;
  
  -- Write buffer signals.
  signal writeBufEna            : std_logic;
  signal writeBufAddr           : rvex_address_type;
  signal writeBufData           : rvex_data_type;
  signal writeBufMask           : rvex_mask_type;
  
  -- Read data synchronization register signals.
  signal memSyncRegEna          : std_logic;
  signal memSyncRegData         : rvex_data_type;
  signal memSyncRegFault        : std_logic;
  
  -- Write accepted register. This is set when a write is started and reset
  -- only when the CPU moves on to the next command.
  signal acceptWrite            : std_logic;
  signal writeAccepted          : std_logic;
  
  -- When a write is buffered and executed in the cache, we want the CPU to
  -- resume in the cycle thereafter. To accomplish that one cycle delay, we
  -- have this register.
  signal resumeAfterWrite       : std_logic;
  signal resumeAfterWrite_next  : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Instantiate registers.
  seq_proc: process (clk) is
  begin
    if rising_edge(clk) then
      
      -- Instantiate state machine state register.
      if reset = '1' then
        state <= STATE_IDLE;
      else
        state <= nextState;
      end if;
      
      -- Instantiate write buffer registers.
      if writeBufEna = '1' then
        writeBufAddr <= addr;
        writeBufData <= writeData;
        writeBufMask <= writeMask;
      end if;
      
      -- Instantiate read data synchronization register to go from the clkEnBus
      -- domain to the clkEnCPU domain. When the bus returns read data, this
      -- stores the data in case clkEnCPU was not active in that cycle.
      if reset = '1' then
        memSyncRegData <= (others => '0');
        memSyncRegFault <= '0';
      elsif memSyncRegEna = '1' then
        memSyncRegData <= busToCache.readData;
        memSyncRegFault <= busToCache.fault;
      end if;
      
      -- Instantiate write accepted register.
      if reset = '1' or (stall = '0' and clkEnCPU = '1') then
        writeAccepted <= '0';
      elsif acceptWrite = '1' then
        writeAccepted <= '1';
      end if;
      
      -- Instantiate write accepted register.
      if reset = '1' or (stall = '0' and clkEnCPU = '1') then
        resumeAfterWrite <= '0';
      elsif resumeAfterWrite_next = '1' then
        resumeAfterWrite <= '1';
      end if;
      
    end if;
  end process;
  
  -- Instantiate state machine logic.
  comb_proc: process (
    
    -- Current state.
    state,
    
    -- Clock enable inputs.
    clkEnCPU, clkEnBus,
    
    -- Inputs from CPU.
    addr, readEnable, writeEnable, writeData, writeMask, bypass, stall,
    
    -- Inputs from mux/demux network.
    updateEnable, handleWrite,
    
    -- Inputs from cache memory.
    hit, cacheReadData,
    
    -- Inputs from main memory bus.
    busToCache,
    
    -- Inputs from write buffer registers.
    writeBufAddr, writeBufData, writeBufMask,
    
    -- Inputs from synchronization register.
    memSyncRegData, memSyncRegFault,
    
    -- Inputs from write accepted register.
    writeAccepted,
    
    -- Inputs for CPU resume after write register.
    resumeAfterWrite
    
  ) is
    variable writeMaskFull    : boolean;
  begin
    
    -- Determine if the write mask masks out any bytes.
    writeMaskFull := true;
    for i in 0 to 3 loop
      if writeMask(i) = '0' then
        writeMaskFull := false;
      end if;
    end loop;
    
    -- Load default values.
    nextState <= state;
    cacheToBus <= BUS_MST2SLV_IDLE;
    cacheToBus.address <= addr;
    cacheToBus.writeData <= writeData;
    cacheToBus.writeMask <= writeMask;
    update <= '0';
    updateData <= writeData;
    updateMask <= writeMask;
    readData <= cacheReadData;
    writeBufEna <= '0';
    memSyncRegEna <= '0';
    if (writeEnable = '1' and handleWrite = '1' and not resumeAfterWrite = '1') or bypass = '1' then
      writeOrBypassStall <= '1';
    else
      writeOrBypassStall <= '0';
    end if;
    writePrio <= "11";
    acceptWrite <= '0';
    resumeAfterWrite_next <= '0';
    blockReconfig <= '1';
    busFault <= '0';
    servicedWrite <= writeAccepted;
    writeBuffered <= '0';
    
    -- Handle state machine states.
    case state is
      when STATE_IDLE =>
        
        if (readEnable = '1' or writeEnable = '1') and bypass = '1' then
          
          cacheToBus.writeData <= writeData;
          cacheToBus.writeMask <= writeMask;
          if clkEnCPU = '1' then
            cacheToBus.readEnable <= readEnable;
            cacheToBus.writeEnable <= writeEnable;
            nextState <= STATE_BYPASS;
          end if;
          
        elsif updateEnable = '1' and clkEnCPU = '1' then
          
          -- Initiate read from the memory to the cache.
          cacheToBus.readEnable <= '1';
          nextState <= STATE_UPDATE_1;
          
        elsif writeEnable = '1' and handleWrite = '1' then
          
          -- Accept the write request.
          acceptWrite <= '1';
          
          if not writeMaskFull and hit = '0' then
            
            -- Initiate read from the memory to the cache. We need to do this
            -- to ensure cache coherency for reads which might happen while the
            -- memory is still being updated. When the state returns to IDLE
            -- after the update, hit will be high and the write will be
            -- executed.
            if clkEnCPU = '1' then
              cacheToBus.readEnable <= '1';
              nextState <= STATE_UPDATE_1;
            end if;
            
          else
            
            -- Perform the write in the cache. This doesn't need a clkEnCPU
            -- because the cache memory is only active when clkEnCPU is active.
            update <= '1';
            updateData <= writeData;
            updateMask <= writeMask;
            
            -- Make a copy of the write command and release the CPU stall
            -- signal so the CPU can continue after this cycle.
            writeBufEna <= '1';
            resumeAfterWrite_next <= '1';
            
            -- Initiate write to the memory.
            if clkEnCPU = '1' then
              cacheToBus.writeEnable <= '1';
              cacheToBus.writeData <= writeData;
              cacheToBus.writeMask <= writeMask;
              nextState <= STATE_WRITE;
            end if;
            
          end if;
        else
          
          -- Idle.
          blockReconfig <= '0';
          
        end if;
        
        -- Compute the proper write priority.
        if hit = '1' then
          writePrio <= "10";
        else
          writePrio <= "01";
        end if;
      
      when STATE_WRITE =>
        
        if clkEnBus = '1' and busToCache.ack = '1' then

          if busToCache.fault = '1' then
             
            -- Report a bus fault to the CPU. We can do this easily by just
            -- enabling the synchronization register (which also stores the
            -- fault flag) and going to the STATE_WAIT_FOR_CPU state.
            memSyncRegEna <= '1';
            nextState <= STATE_WAIT_FOR_CPU;
          else
            
            -- Memory write completed. Wait for the CPU to finish processing the
            -- write instruction (there might be other stall signals preventing
            -- it from doing so) before swicthing back to idle.
            if (clkEnCPU = '1' and stall = '0') or writeAccepted = '0' then
              nextState <= STATE_IDLE;
            else
              nextState <= STATE_WAIT_FOR_CPU;
            end if;
            
          end if;
          
        else
          
          -- Keep requesting the write, using the write buffer data.
          cacheToBus.address <= writeBufAddr;
          cacheToBus.writeEnable <= '1';
          cacheToBus.writeData <= writeBufData;
          cacheToBus.writeMask <= writeBufMask;
          
        end if;
        
        -- Compute the proper write priority.
        if hit = '1' then
          writePrio <= "10";
        else
          writePrio <= "00";
        end if;
        
        -- Signal that a write is buffered.
        writeBuffered <= '1';
      
      when STATE_UPDATE_1 =>
        
        -- Prepare the update command and synchronization register data inputs.
        updateData <= busToCache.readData;
        updateMask <= (others => '1');
        
        if clkEnBus = '1' and busToCache.ack = '1' then
          
          if busToCache.fault = '1' then
            
            -- Report a bus fault to the CPU. We can do this easily by just
            -- enabling the synchronization register (which also stores the
            -- fault flag) and going to the STATE_WAIT_FOR_CPU state.
            memSyncRegEna <= '1';
            nextState <= STATE_WAIT_FOR_CPU;
            
          else
            
            -- Update the cache line. Note that this only works if clkEnCPU is
            -- high and that the data from the bus might not stay valid that
            -- long. In this case, the synchronization data register will buffer
            -- the data from the memory.
            update <= '1';
            memSyncRegEna <= '1';
            if clkEnCPU = '1' then
              nextState <= STATE_IDLE;
            else
              nextState <= STATE_UPDATE_2;
            end if;
            
          end if;
          
        else
          
          -- Keep requesting the read.
          cacheToBus.readEnable <= '1';
          
        end if;
      
      when STATE_UPDATE_2 =>
        
        -- Update the cache line from the buffer register.
        updateData <= memSyncRegData;
        updateMask <= (others => '1');
        update <= '1';
        if clkEnCPU = '1' then
          nextState <= STATE_IDLE;
        end if;
      
      when STATE_BYPASS =>
        
        if clkEnBus = '1' and busToCache.ack = '1' then
          
          -- Store the data from the bus in the synchronization register. We
          -- could return it here directly if the CPU is not stalled for any
          -- other reason, but timing wise it's better to accept an extra cycle
          -- of delay compared to having the whole bus in a combinatorial path
          -- to the processor.
          memSyncRegEna <= '1';
          nextState <= STATE_WAIT_FOR_CPU;
          
        else
          
          -- Keep requesting.
          cacheToBus.readEnable <= readEnable;
          cacheToBus.writeData <= writeData;
          cacheToBus.writeMask <= writeMask;
          cacheToBus.writeEnable <= writeEnable;
          
        end if;
      
      when STATE_WAIT_FOR_CPU =>
        
        -- Return the data read from the memory as stored in the
        -- synchronization register.
        readData <= memSyncRegData;
        busFault <= memSyncRegFault;
        writeOrBypassStall <= '0';
        if clkEnCPU = '1' and stall = '0' then
          nextState <= STATE_IDLE;
        end if;
        
        -- Compute the proper write priority.
        if hit = '1' then
          writePrio <= "10";
        else
          writePrio <= "01";
        end if;
      
    end case;
    
    -- Force writePrio to "11" when a write is in progress.
    if writeAccepted = '1' then
      writePrio <= "11";
    end if;
    
  end process;
  
end Behavioral;

