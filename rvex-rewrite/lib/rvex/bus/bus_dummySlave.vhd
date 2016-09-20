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
use rvex.simUtils_pkg.all;
use rvex.bus_pkg.all;

--=============================================================================
-- Responds with randomized replies to incoming requests at randomized
-- latencies. Simulation only.
-------------------------------------------------------------------------------
entity bus_dummySlave is
--=============================================================================
  port (
    
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input.
    clkEn                       : in  std_logic;
    
    -- Bus under test.
    mosi                        : in  bus_mst2slv_type;
    miso                        : out bus_slv2mst_type
    
  );
end bus_dummySlave;

--=============================================================================
architecture Behavioral of bus_dummySlave is
--=============================================================================
  
begin
  
  process is
    variable r      : bus_mst2slv_type;
    variable seed1  : positive;
    variable seed2  : positive;
    variable rnd    : rvex_data_type;
  begin
    loop
      
      -- Reset/idle state.
      miso.readData <= (others => 'U');
      miso.fault <= 'U';
      miso.busy <= '0';
      miso.ack <= '0';
      
      -- Handle accesses.
      loop
        
        -- Wait for a clock edge.
        loop
          wait until rising_edge(clk);
          exit when reset = '1' or clkEn = '1';
        end loop;
        exit when reset = '1';
        
        -- Reset any response setup in the previous cycle.
        miso.readData <= (others => 'U');
        miso.fault <= 'U';
        miso.busy <= '0';
        miso.ack <= '0';
        
        -- Make a copy of the current request.
        r := mosi;
        
        -- Report an error if both readEnable and writeEnable are active
        -- simultaneously.
        if r.writeEnable = '1' and r.readEnable = '1' then
          report "Receiving simultaneous read and write requests! Handling as write." severity error;
        end if;
        
        -- Delay for a random amount of cycles.
        if r.writeEnable = '1' or r.readEnable = '1' then
          loop
            
            -- 50/50 chance to delay another cycle.
            rvs_randomVect(seed1, seed2, rnd);
            exit when rnd(0) = '1';
            
            -- Assert busy.
            miso.busy <= '1';
            
            -- Wait for a clock edge.
            loop
              wait until rising_edge(clk);
              exit when reset = '1' or clkEn = '1';
            end loop;
            exit when reset = '1';
            
            -- Verify that the request is stable while busy is asserted.
            if mosi /= r then
              report "Request changed while busy was asserted!" severity error;
            end if;
            
          end loop;
          exit when reset = '1';
          
          -- Release busy (if it was asserted) and acknowledge.
          miso.ack <= '1';
          miso.busy <= '0';
          
          -- Setup the result.
          rvs_randomVect(seed1, seed2, rnd);
          if rnd(0) = '1' then
            miso.fault <= '1';
            miso.readData <= X"DEADC0DE";
          elsif r.writeEnable /= '1' then
            rvs_randomVect(seed1, seed2, rnd);
            miso.readData <= rnd;
          end if;
          
        end if;
        
      end loop;
    end loop;
  end process;
  
end Behavioral;

