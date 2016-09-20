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
use rvex.bus_pkg.all;
use rvex.utils_pkg.all;

--=============================================================================
-- This peripheral manages interrupts in a multiprocessor/multicontext
-- environment. It also contains a repetitive interrupt timer, and the timer
-- and other contexts can be automatically disabled when a context is waiting
-- for a breakpoint.
-- 
-- Up to 31 interrupts are supported, including the built-in timer, identified
-- as 1 to 31 or 33 to 63 depending on the PRIO bit (selectable per
-- core-interrupt pair) if configurable priorities are enabled, or always 1 to
-- 31 if not. Lower interrupts have lower priority. Nesting is supported by
-- means of a minimum IRQ level register, which, when set to the interrupt ID,
-- will prevent the same interrupt or lower priority interrupts from firing,
-- regardless of the mask.
-- 
-- The actual interrupt ID as received by the interrupt handler is built as
-- follows:
--  - bit 4..0:   interrupt index
--  - bit 5:      priority flag
--  - bit 10..6:  interrupt core ID
--  - bit 31..11: interrupt controller base address
-- 
-- The core ID is intended to permit easy access to the interrupt control
-- registers from the assembly handler, as long as the base address is known.
-- This is useful in particular when nesting all interrupts, as it allows the
-- ICR_LEVELn register to be easily accessible.
-- 
-- Multi-core is done by essentially having independent interrupt controllers
-- for each core, mapped to the same interrupt request signals. Each core has
-- its own interrupt pending and interrupt mask flags. That is, if an interrupt
-- fires that is enabled for multiple cores, each of these cores will be
-- interrupted. A first-come-first-serve system must be emulated in software if
-- desired.
-- 
-- The interrupt controller requires 2kiB of address space. The memory map is
-- as follows:
-- 
--  - 0x000:          ICR_DONE   - done bits for all contexts.
--  - 0x004:          ICR_IDLE   - idle bits for all contexts.
--  - 0x008:          ICR_BREAK  - break bits for all contexts.
--  - 0x00C:          ICR_CAPS   - capabilities register.
--  - 0x018:          ICR_PERIOD - timer period register.
--  - 0x01C:          ICR_TIME   - current timer value (counts down to zero).
--  - 0x400 + 0x20*n: ICR_BRBROn - breakpoint broadcast register for context n.
--  - 0x404 + 0x20*n: ICR_RVECTn - reset vector for context n.
--  - 0x408 + 0x20*n: ICR_LEVELn - interrupt level for context n.
--  - 0x40C + 0x20*n: ICR_PRIOn  - interrupt priorities for context n.
--  - 0x410 + 0x20*n: ICR_ENAn   - interrupt enable register for context n.
--  - 0x414 + 0x20*n: ICR_DISAn  - interrupt disable register for context n.
--  - 0x418 + 0x20*n: ICR_PENDn  - interrupt pend register for context n.
--  - 0x41C + 0x20*n: ICR_CLEARn - interrupt clear register for context n.
-- 
-- Bitfields:
-- 
--  - ICR_DONE, ICR_IDLE, ICR_BREAK:
---     * Bit i is mapped to context i.
--      * Non-existing contexts always read zero.
--      * Write 1 to ICR_DONE to reset contexts.
--
--  - ICR_CAPS:
--      * Bit 7..0: number of contexts serviced.
--      * Bit 15..8: number of interrupts serviced.
--      * Bit 23..16: number of timer bits.
--      * Bit 24: whether the BRBROn registers exist.
--      * Bit 25: whether the RVECTn registers exist.
--      * Bit 26: whether the LEVELn registers exist.
--      * Bit 27: whether the PRIOn registers exist.
--      * Bit 31..27: reserved (zero).
-- 
--  - ICR_PERIOD:
--      * Bit 31..0: timer reload value.
--      * Timer reload is triggered when the value is 1 or 0; the interrupt is
--        requested only at 1. Thus, the period is reload/clk for reload >= 1
--        and the timer is off when reload is 0.
-- 
--  - ICR_TIME:
--      * Bit 31..0: current counter value.
-- 
--  - ICR_NRNROn:
--      * Bit i enables broadcasting the breakpoint state of context n to
--        context i (i.e., context i is halted if context n DCR.B is set).
--      * Bit 31 enables broadcasting the breakpoint state of context n to the
--        timer (i.e., the timer is halted if context n DCR.B is set).
--      * Other bits read as zero.
-- 
--  - ICR_RVECTn:
--      * Bit 31..3: reset vector for context n.
--      * Bit 2..0: always zero.
-- 
--  - ICR_PRIOn, ICR_ENAn, ICR_DISAn, ICR_PENDn, ICR_CLEARn:
--      * Bit i: controls interrupt i.
--      * Bit 0: always zero.
--      * Functions:
--          o PRIO:  increases the priority and IRQ ID of this interrupt by 32.
--          o ENA:   reads as interrupt enabled, write 1 to enable interrupt.
--          o DISA:  reads as interrupt enabled, write 1 to disable interrupt.
--          o PEND:  reads as interrupt pending, write 1 to pend interrupt.
--          o CLEAR: reads as interrupt pending, write 1 to clear interrupt.
-- 
-------------------------------------------------------------------------------
entity periph_irq is
--=============================================================================
  generic (
    
    -- Base address of the interrupt controller registers as seen from the
    -- processors. This is part of the interrupt request ID (i.e. the trap
    -- argument), allowing a generic interrupt handler to be written in
    -- assembly. This must be aligned to a 2 kiB boundary.
    BASE_ADDRESS                : rvex_address_type := (others => '0');
    
    -- Number of contexts to service. Min 1, max 31.
    NUM_CONTEXTS                : natural := 1;
    
    -- Number of external interrupts to service. Min 1, max 31. The timer
    -- interrupt is shared with interrupt 1.
    NUM_IRQ                     : natural := 1;
    
    -- Number of bits in the timer value. 0 for timer disabled. Min 2, max 32
    -- for an actual timer.
    TIMER_BITS                  : natural := 32;
    
    -- Enables (1) or disables (0) configurable interrupt priorities. That is,
    -- this controls the existence of the PRIOn registers and a double-width
    -- priority decoder.
    CONFIG_PRIO_ENABLE          : natural := 1;
    
    -- Enables (1) or disables (0) interrupt nesting support. That is, this
    -- controls the existence of the LEVELn registers and the interrupt level
    -- comparator.
    NESTING_ENABLE              : natural := 1;
    
    -- Enables (1) or disables (0) breakpoint broadcasting (i.e. stopping cores
    -- and/or the timer in response to a breakpoint in another core). That is,
    -- this controls the existence of the BRBROn registers and the broadcasting
    -- logic.
    BREAKPOINT_BROADCASTING     : natural := 1;
    
    -- Enables (1) or disables (0) configurable reset vectors. That is, this
    -- controls the existence of the RVECTn registers. When disabled, the
    -- reset vector output is always zero for each context.
    CONFIG_RVECT_ENABLE         : natural := 1;
    
    -- Enables (1) or disables (0) inserting a register in the interrupt
    -- request path from the controller to the processor. This can be used to
    -- break the critical path if it ends up here or decrease the strain on
    -- the router a bit at the cost of an extra cycle's worth of interrupt
    -- latency.
    OUTPUT_REGISTER             : natural := 0
    
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
    -- r-VEX interface
    ---------------------------------------------------------------------------
    -- Interrupt request signals to the r-VEX.
    irq2rv_irq                  : out std_logic_vector(NUM_CONTEXTS-1 downto 0);
    irq2rv_irqID                : out rvex_address_array(NUM_CONTEXTS-1 downto 0);
    
    -- Interrupt acknowledge signal back from the r-VEX. Must be high for one
    -- clkEn'd cycle only.
    rv2irq_irqAck               : in  std_logic_vector(NUM_CONTEXTS-1 downto 0) := (others => '0');
    
    -- Active high run output. This is pulled low when another context is
    -- waiting for an externally managed breakpoint to be serviced and the
    -- respective BRBRO bit is set.
    irq2rv_run                  : out std_logic_vector(NUM_CONTEXTS-1 downto 0);
    
    -- Active high idle signal from the r-VEX. This is asserted when the core
    -- is not doing anything.
    rv2irq_idle                 : in  std_logic_vector(NUM_CONTEXTS-1 downto 0) := (others => '0');
    
    -- Active high break signal from the r-VEX. This is asserted when the core
    -- is waiting for an externally handled breakpoint.
    rv2irq_break                : in  std_logic_vector(NUM_CONTEXTS-1 downto 0) := (others => '0');
    
    -- Trace stall input. When this is asserted, the timer is stopped.
    rv2irq_traceStall           : in  std_logic := '0';
    
    -- Active high context reset output. When high, the context control
    -- registers (including PC, done and break flag) should be reset.
    irq2rv_reset                : out std_logic_vector(NUM_CONTEXTS-1 downto 0);
    
    -- Reset vector. When the context or the entire core is reset, the PC
    -- register should be set to this value.
    irq2rv_resetVect            : out rvex_address_array(NUM_CONTEXTS-1 downto 0);
    
    -- Active high done signal from the r-VEX. This is asserted when the
    -- context encounters a stop syllable.
    rv2irq_done                 : in  std_logic_vector(NUM_CONTEXTS-1 downto 0) := (others => '0');
   
    ---------------------------------------------------------------------------
    -- Interrupt inputs
    ---------------------------------------------------------------------------
    -- External interrupt IDs. Interrupt 1 is shared with the timer. To pend an
    -- interrupt, the respective periph2irq bit must be asserted high for one
    -- clkEn'd cycle.
    periph2irq                  : in  std_logic_vector(NUM_IRQ downto 1) := (others => '0');
    
    ---------------------------------------------------------------------------
    -- Bus interface
    ---------------------------------------------------------------------------
    -- This bus master is controlled by the debug packets, to allow the
    -- debugging software running on the computer to access mapped memory
    -- regions.
    bus2irq                     : in  bus_mst2slv_type;
    irq2bus                     : out bus_slv2mst_type
    
  );
end periph_irq;

--=============================================================================
architecture Behavioral of periph_irq is
--=============================================================================
  
  -- Figure out the number of bits needed to select a context.
  constant NUM_CONTEXTS_LOG2    : integer := integer(ceil(log2(real(NUM_CONTEXTS))));
  
  -- Figure out the number of bits needed to represent an interrupt (excluding
  -- priority bit).
  constant NUM_IRQ_LOG2         : integer := integer(ceil(log2(real(NUM_IRQ+1))));
  
  -- Define a type with one bit per context.
  subtype perCtxt_type is std_logic_vector(NUM_CONTEXTS-1 downto 0);
  type perCtxt_array is array (natural range <>) of perCtxt_type;
  
  -- Define a type with one bit per interrupt.
  subtype perIRQ_type is std_logic_vector(NUM_IRQ downto 1);
  type perIRQ_array is array (natural range <>) of perIRQ_type;
  
  -- Define a type with the interrupt level size.
  subtype level_type is std_logic_vector(5 downto 0);
  type level_array is array (natural range <>) of level_type;
  
  -- Define a type for the reset vectors.
  subtype resetVect_type is std_logic_vector(31 downto 3);
  type resetVect_array is array (natural range <>) of resetVect_type;
  
  -- Define a type for the timer value.
  subtype timer_type is std_logic_vector(max_nat(TIMER_BITS, 1)-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Timer registers and signals
  -----------------------------------------------------------------------------
  -- Whether the timer should run.
  signal timer_run              : std_logic;
  
  -- Current timer value.
  signal timer_value_r          : std_logic_vector(31 downto 0);
  
  -- Asserted when the current timer value is greater than one.
  signal timer_gtOne            : std_logic;
  
  -- Timer reload value.
  signal timer_reload_r         : std_logic_vector(31 downto 0);
  
  -----------------------------------------------------------------------------
  -- Interrupt signals
  -----------------------------------------------------------------------------
  -- One-hot signals indicating that the currently requested interrupt is
  -- acknowledged by the core.
  signal irqClear               : perIRQ_array(NUM_CONTEXTS-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Context control registers
  -----------------------------------------------------------------------------
  -- Breakpoint broadcast-to-context registers. These correspond to the low
  -- bits of the ICR_BRBROn registers.
  signal brkkBroadcastCtxt_r    : perCtxt_array(NUM_CONTEXTS-1 downto 0);
  
  -- Breakpoint broadcase-to-timer registers. These correspond to the MSB of
  -- each ICR_BRBROn register.
  signal brkkBroadcastTimer_r   : perCtxt_type;
  
  -- Reset vector for each context, corresponding to the high bits of each
  -- ICR_RVECTn register.
  signal resetVects_r           : resetVect_array(NUM_CONTEXTS-1 downto 0);
  
  -- Interrupt level for each context.
  signal irqLevel_r             : level_array(NUM_CONTEXTS-1 downto 0);
  
  -- Interrupt priority for each context-interrupt pair, corresponding to the
  -- contents of each ICR_PRIOn register. Interrupts with their PRIO bits set
  -- have priority over all interrupts with unset PRIO bits. For equal PRIO
  -- bits, lower interrupts have higher priority.
  signal irqPrio_r              : perIRQ_array(NUM_CONTEXTS-1 downto 0);
  
  -- Interrupt enable register for each context-interrupt pair, corresponding
  -- to the contents of each ICR_ENAn/ICR_DISAn register.
  signal irqEnabled_r           : perIRQ_array(NUM_CONTEXTS-1 downto 0);
  
  -- Interrupt pending register for each context-interrupt pair, corresponding
  -- to the contents of each ICR_PENDn/ICR_CLEARn register.
  signal irqPending_r           : perIRQ_array(NUM_CONTEXTS-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Interrupt handling
  -----------------------------------------------------------------------------
  irq_handlers: for ctxt in 0 to NUM_CONTEXTS-1 generate
    constant PRIO_DEC_WIDTH   : natural := NUM_IRQ_LOG2+CONFIG_PRIO_ENABLE;
    
    -- Priority decoder signals. The priority decoder is taken from the
    -- optiprims file so it can be easily optimized per target.
    signal prio_input         : std_logic_vector(2**PRIO_DEC_WIDTH-1 downto 0);
    signal prio_output        : std_logic_vector(PRIO_DEC_WIDTH-1 downto 0);
    signal prio_any           : std_logic;
    
    -- Whether an enabled interrupt with priority greater than the current
    -- interrupt level is pending.
    signal irqReq             : std_logic;
    
    -- Requested interrupt level.
    signal irqReqLevel        : level_type;
    
    -- Optionally registered versions of the above two signals. If
    -- OUTPUT_REGISTER is zero, the register is not inserted.
    signal irqReq_r           : std_logic;
    signal irqReqLevel_r      : level_type;
    
  begin
    
    -- Pack the interrupt pending data into the priority decoder input
    -- signal.
    prio_inp: process (
      irqPending_r(ctxt), irqEnabled_r(ctxt), irqPrio_r(ctxt)
    ) is
      variable request        : perIRQ_type;
    begin
      
      -- Set all interrupts to cleared by default.
      prio_input <= (others => '0');
      
      -- Mask the pending registers with the enabled registers.
      request := irqPending_r(ctxt) and irqEnabled_r(ctxt);
      
      if CONFIG_PRIO_ENABLE = 0 then
        
        -- No configurable priorities. The interrupts map one-to-one to the
        -- decoder input.
        prio_input(perIRQ_type'range) <= request;
        
      elsif CONFIG_PRIO_ENABLE = 1 then
        
        -- Configurable priorities are enabled. Map the low priority
        -- interrupts.
        prio_input(
          perIRQ_type'high + 0 downto
          perIRQ_type'low  + 0
        ) <= (
          request and not irqPrio_r(ctxt)
        );
        
        -- Map the high priority interrupts.
        prio_input(
          perIRQ_type'high + 2**NUM_IRQ_LOG2 downto
          perIRQ_type'low  + 2**NUM_IRQ_LOG2
        ) <= (
          request and irqPrio_r(ctxt)
        );
        
      end if;
    end process;
    
    -- Instantiate the priority decoder.
    prio_dec: entity work.utils_priodec
      generic map (
        NUM_LOG2  => NUM_IRQ_LOG2 + CONFIG_PRIO_ENABLE
      )
      port map (
        inp       => prio_input,
        outp      => prio_output,
        any       => prio_any
      );
    
    -- Decode the priority decoder output and mask it with the interrupt
    -- level.
    prio_outp: process (
      prio_output, irqLevel_r
    ) is
      variable irqReqLevel_v  : level_type;
      variable irqReq_v       : std_logic;
    begin
      
      -- Initialize the interrupt level variable with no interrupt.
      irqReqLevel_v := (others => '0');
      
      -- Decode the priority decoder output.
      irqReqLevel_v(NUM_IRQ_LOG2-1 downto 0) 
        := prio_output(NUM_IRQ_LOG2-1 downto 0);
      if CONFIG_PRIO_ENABLE = 1 then
        irqReqLevel_v(irqReqLevel_v'high) := prio_output(NUM_IRQ_LOG2);
      end if;
      
      -- Request an interrupt when any priority decoder input is active by
      -- default.
      irqReq_v := prio_any;
      
      -- If nesting is enabled, we should only request the interrupt if the
      -- current interrupt level is lower than the interrupt priority.
      if NESTING_ENABLE = 1 then
        if unsigned(irqReqLevel_v) <= unsigned(irqLevel_r(ctxt)) then
          irqReq_v := '0';
        end if;
      end if;
      
      -- Assign the interrupt request variables to the signals.
      irqReq <= irqReq_v;
      irqReqLevel <= irqReqLevel_v;
      
    end process;
    
    -- Forward the requested interrupt level to the processor in case the
    -- output should be registered.
    output_reg_gen: if OUTPUT_REGISTER = 1 generate
    begin
      output_reg_proc: process (clk) is
      begin
        if rising_edge(clk) then
          if reset = '1' then
            irqReq_r      <= '0';
            irqReqLevel_r <= (others => '0');
          elsif clkEn = '1' then
            
            -- Disable the interrupt request in the cycle after an
            -- acknowledgement. We need to do this because there is a two cycle
            -- delay from acknowledgement to clearing the request otherwise,
            -- violating the r-VEX timing requirements.
            irqReq_r      <= irqReq and not rv2irq_irqAck(ctxt);
            irqReqLevel_r <= irqReqLevel;
            
          end if;
        end if;
      end process;
    end generate;
    
    -- Forward the requested interrupt level to the processor in case the
    -- output should be combinatorial.
    output_comb_gen: if OUTPUT_REGISTER = 0 generate
    begin
      irqReq_r      <= irqReq;
      irqReqLevel_r <= irqReqLevel;
    end generate;
    
    -- Assign the request signals to the cores.
    irq2rv_irq(ctxt)   <= irqReq_r;
    irq2rv_irqID(ctxt) <= BASE_ADDRESS(BASE_ADDRESS'high downto 11)
                        & std_logic_vector(to_unsigned(ctxt, 5))
                        & irqReqLevel_r;
    
    -- Interrupts should automatically be cleared when they are accepted by the
    -- core. Generate the clear signals for that here.
    irq_clear_proc: process (irqReqLevel_r, rv2irq_irqAck(ctxt)) is
    begin
      
      -- Don't clear interrupts by default.
      irqClear(ctxt) <= (others => '0');
      
      -- If the core is acknowledging an interupt, clear the interrupt that was
      -- being requested.
      if rv2irq_irqAck(ctxt) = '1' then
        for irq in 1 to NUM_IRQ loop
          if unsigned(irqReqLevel_r(4 downto 0)) = irq then
            irqClear(ctxt)(irq) <= '1';
          end if;
        end loop;
      end if;
      
    end process;
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Timer value compare unit
  -----------------------------------------------------------------------------
  -- Use an optimized wide or gate to determine if the timer is at zero
  -- or one.
  timer_compare_gen: if TIMER_BITS > 1 generate
  begin
    timer_compare: entity work.utils_wideor
      generic map (
        WIDTH     => timer_type'length - 1
      )
      port map (
        inp       => timer_value_r(timer_type'HIGH downto 1),
        outp      => timer_gtOne,
        outp_int  => open
      );
  end generate;
  
  -----------------------------------------------------------------------------
  -- Breakpoint broadcasting
  -----------------------------------------------------------------------------
  brk_broad_gen: if BREAKPOINT_BROADCASTING = 1 generate
  begin
    process (
      rv2irq_break, brkkBroadcastCtxt_r, brkkBroadcastTimer_r,
      rv2irq_traceStall
    ) is
      variable flag : std_logic;
    begin
      
      -- Broadcast from contexts to other contexts.
      for rxCtxt in 0 to NUM_CONTEXTS-1 loop
        flag := '1';
        for txCtxt in 0 to NUM_CONTEXTS-1 loop
          if brkkBroadcastCtxt_r(txCtxt)(rxCtxt) = '1' then
            if rv2irq_break(txCtxt) = '1' then
              flag := '0';
            end if;
          end if;
        end loop;
        irq2rv_run(rxCtxt) <= flag;
      end loop;
      
      -- Broadcast from the contexts and the trace stall input to the timer.
      flag := not rv2irq_traceStall;
      for txCtxt in 0 to NUM_CONTEXTS-1 loop
        if brkkBroadcastTimer_r(txCtxt) = '1' then
          if rv2irq_break(txCtxt) = '1' then
            flag := '0';
          end if;
        end if;
      end loop;
      timer_run <= flag;
      
    end process;
  end generate;
  
  -- If breakpoint broadcasting is disabled, tie all the run signals high.
  no_brk_broad_gen: if BREAKPOINT_BROADCASTING /= 1 generate
  begin
    irq2rv_run <= (others => '1');
    timer_run <= not rv2irq_traceStall;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Reset vector outputs
  -----------------------------------------------------------------------------
  -- Forward the reset vector registers if configurable reset vectors are
  -- enabled.
  cfg_rvect_gen: if CONFIG_RVECT_ENABLE = 1 generate
  begin
    process (resetVects_r) is
    begin
      for ctxt in 0 to NUM_CONTEXTS-1 loop
        irq2rv_resetVect(ctxt) <= resetVects_r(ctxt) & "000";
      end loop;
    end process;
  end generate;
  
  -- Assign the reset vectors to zero if configurable reset vectors are not
  -- enabled.
  no_cfg_rvect_gen: if CONFIG_RVECT_ENABLE /= 1 generate
  begin
    irq2rv_resetVect <= (others => (others => '0'));
  end generate;
  
  -----------------------------------------------------------------------------
  -- Control registers, timer logic, and interrupt pend logic
  -----------------------------------------------------------------------------
  proc: process (clk) is
    variable bus_resp   : bus_slv2mst_type;
    variable ctxt       : integer range 0 to 31;
    variable rdat       : rvex_data_type;
    variable wdat       : rvex_data_type;
    variable wmaskfull  : std_logic;
    variable we         : std_logic;
    variable bits       : std_logic_vector(2 downto 0);
    variable tick       : std_logic;
    variable irqPending : perIRQ_array(NUM_CONTEXTS-1 downto 0);
  begin
    if rising_edge(clk) then
      bus_resp := BUS_SLV2MST_IDLE;
      
      -- The context reset outputs are zero unless otherwise specified.
      irq2rv_reset <= (others => '0');
      
      if reset = '1' then
        
        -- Reset the context control registers.
        brkkBroadcastCtxt_r   <= (others => (others => '0'));
        brkkBroadcastTimer_r  <= (others => '0');
        resetVects_r          <= (others => (others => '0'));
        irqLevel_r            <= (others => (others => '0'));
        irqPrio_r             <= (others => (others => '0'));
        irqEnabled_r          <= (others => (others => '0'));
        irqPending_r          <= (others => (others => '0'));
        
      elsif clkEn = '1' then
        
        -----------------------------------------------------------------------
        -- Timer
        -----------------------------------------------------------------------
        -- Tick stores whether a timer interrupt should be requested.
        tick := '0';
        
        -- The timer counts down to 1 and is then reloaded with the reload
        -- value. At the same time an interrupt is requested. If the timer is
        -- reloaded with zero, it essentially stops, as it is constantly
        -- reloaded, with no interrupts requested. Reloading the timer with one
        -- constantly requests interrupts.
        if TIMER_BITS > 1 then
          if timer_run = '1' then
            if timer_gtOne = '0' then
              if timer_value_r(0) = '1' then
                
                -- Request the timer interrupt.
                tick := '1';
                
              end if;
              
              -- Reload the timer.
              timer_value_r <= timer_reload_r;
              
            else
              
              -- Decrement the timer.
              timer_value_r <= std_logic_vector(unsigned(timer_value_r) - 1);
              
            end if;
          end if;
        end if;
        
        -----------------------------------------------------------------------
        -- Interrupt logic
        -----------------------------------------------------------------------
        -- Store which interrupts are currently pending.
        irqPending := irqPending_r;
        
        for ctxt in 0 to NUM_CONTEXTS-1 loop
          
          -- Pend in case of external interrupts.
          irqPending(ctxt) := irqPending(ctxt) or periph2irq;
          
          -- Pend in case of a timer interrupt.
          irqPending(ctxt)(1) := irqPending(ctxt)(1) or tick;
          
          -- Clear if an interrupt is acknowledged.
          irqPending(ctxt) := irqPending(ctxt) and not irqClear(ctxt);
          
        end loop;
        
        -----------------------------------------------------------------------
        -- Bus access
        -----------------------------------------------------------------------
        -- Read data defaults to zero.
        rdat := (others => '0');
        
        -- Handle invalid writes (only 32-bit writes are supported).
        wmaskfull := bus2irq.writeMask(0) and bus2irq.writeMask(1) and 
                     bus2irq.writeMask(2) and bus2irq.writeMask(3);
        we := wmaskfull and bus2irq.writeEnable;
        
        -- Load writeData into a variable for convenience.
        wdat := bus2irq.writeData;
        
        -- Multiplex based on address.
        if bus2irq.address(10) = '0' then
          
          -- Disable inferrence of the timer registers when TIMER_BITS is zero.
          bits := bus2irq.address(4 downto 2);
          if TIMER_BITS = 0 then
            bits(2) := '0';
          end if;
          case bits is
            
            -- ICR_DONE
            when "000" =>
              if we = '1' then
                irq2rv_reset <= wdat(perCtxt_type'range);
              end if;
              rdat(perCtxt_type'range) := rv2irq_done;
            
            -- ICR_IDLE
            when "001" =>
              rdat(perCtxt_type'range) := rv2irq_idle;
            
            -- ICR_BREAK
            when "010" =>
              rdat(perCtxt_type'range) := rv2irq_break;
            
            -- ICR_CAPS
            when "011" =>
              rdat( 7 downto  0) := std_logic_vector(to_unsigned(NUM_CONTEXTS,            8));
              rdat(15 downto  8) := std_logic_vector(to_unsigned(NUM_IRQ,                 8));
              rdat(23 downto 16) := std_logic_vector(to_unsigned(TIMER_BITS,              8));
              rdat(24 downto 24) := std_logic_vector(to_unsigned(BREAKPOINT_BROADCASTING, 1));
              rdat(25 downto 25) := std_logic_vector(to_unsigned(CONFIG_RVECT_ENABLE,     1));
              rdat(26 downto 26) := std_logic_vector(to_unsigned(NESTING_ENABLE,          1));
              rdat(27 downto 27) := std_logic_vector(to_unsigned(CONFIG_PRIO_ENABLE,      1));
            
            -- ICR_PERIOD
            when "110" =>
              if TIMER_BITS > 1 then
                if we = '1' then
                  timer_reload_r <= wdat(timer_type'range);
                end if;
                rdat(timer_type'range) := timer_reload_r;
              end if;
              
            -- ICR_TIME
            when "111" =>
              if TIMER_BITS > 1 then
                if we = '1' then
                  timer_value_r <= wdat(timer_type'range);
                end if;
                rdat(timer_type'range) := timer_value_r;
              end if;
              
            -- Undefined.
            when others => null;
            
          end case;
        else
          
          -- Determine which context to use.
          ctxt := to_integer(unsigned(bus2irq.address(4+NUM_CONTEXTS_LOG2 downto 5)));
          if ctxt < NUM_CONTEXTS then
            case bus2irq.address(4 downto 2) is
              
              -- ICR_BRBROn
              when "000" =>
                if BREAKPOINT_BROADCASTING = 1 then
                  if we = '1' then
                    
                    -- Override the broadcast bit from ourselves to ourselves
                    -- to zero. The tools should then recognize that this
                    -- register is always zero and not instantiate it.
                    -- Hopefully.
                    wdat(ctxt) := '0';
                    
                    brkkBroadcastCtxt_r(ctxt) <= wdat(perCtxt_type'range);
                    if TIMER_BITS > 1 then
                      brkkBroadcastTimer_r(ctxt) <= wdat(31);
                    end if;
                  end if;
                  rdat(perCtxt_type'range) := brkkBroadcastCtxt_r(ctxt);
                  if TIMER_BITS > 1 then
                    rdat(31) := brkkBroadcastTimer_r(ctxt);
                  end if;
                end if;
                
              -- ICR_RVECTn
              when "001" =>
                if CONFIG_RVECT_ENABLE = 1 then
                  if we = '1' then
                    resetVects_r(ctxt) <= wdat(resetVect_type'range);
                  end if;
                  rdat(resetVect_type'range) := resetVects_r(ctxt);
                end if;
                
              -- ICR_LEVELn
              when "010" =>
                if NESTING_ENABLE = 1 then
                  if we = '1' then
                    irqLevel_r(ctxt) <= wdat(level_type'range);
                  end if;
                  rdat(level_type'range) := irqLevel_r(ctxt);
                end if;
                
              -- ICR_PRIOn
              when "011" =>
                if CONFIG_PRIO_ENABLE = 1 then
                  if we = '1' then
                    irqPrio_r(ctxt) <= wdat(perIRQ_type'range);
                  end if;
                  rdat(perIRQ_type'range) := irqPrio_r(ctxt);
                end if;
                
              -- ICR_ENAn
              when "100" =>
                if we = '1' then
                  irqEnabled_r(ctxt) <= irqEnabled_r(ctxt)
                                     or wdat(perIRQ_type'range);
                end if;
                rdat(perIRQ_type'range) := irqEnabled_r(ctxt);
                
              -- ICR_DISAn
              when "101" =>
                if we = '1' then
                  irqEnabled_r(ctxt) <= irqEnabled_r(ctxt)
                                and not wdat(perIRQ_type'range);
                end if;
                rdat(perIRQ_type'range) := irqEnabled_r(ctxt);
                
              -- ICR_PENDn
              when "110" =>
                if we = '1' then
                  
                  -- Update the variable instead of the signal, otherwise we
                  -- may lose interrupts/acknowledgements if they occur in the
                  -- same cycle as the write access.
                  irqPending(ctxt) := irqPending(ctxt)
                                   or wdat(perIRQ_type'range);
                  
                end if;
                
                -- Whether the new value of the previous value is read by the
                -- bus is pretty much don't care, so use the register to make
                -- routing easier.
                rdat(perIRQ_type'range) := irqPending_r(ctxt);
                
              -- ICR_CLEARn
              when "111" => -- See ICR_PENDn for comments.
                if we = '1' then
                  irqPending(ctxt) := irqPending(ctxt)
                              and not wdat(perIRQ_type'range);
                end if;
                rdat(perIRQ_type'range) := irqPending_r(ctxt);
                
              -- Undefined.
              when others => null;
              
            end case;
          end if;
        end if;
        
        -- Write the updated interrupt pending states to the register signals.
        irqPending_r <= irqPending;
        
        -- Acknowledge all bus transfers immediately.
        bus_resp.ack := bus_requesting(bus2irq);
        bus_resp.fault := bus2irq.writeEnable and not wmaskfull;
        if bus2irq.readEnable = '1' then
          bus_resp.readData := rdat;
        else
          bus_resp.readData := X"21333262"; -- ASCII "!32b"
        end if;
        
      end if;
      irq2bus <= bus_resp;
    end if;
  end process;
  
end Behavioral;
