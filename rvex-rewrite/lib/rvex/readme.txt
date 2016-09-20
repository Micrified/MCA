This directory contains all VHDL sources for the rvex library.

bus     - Contains VHDL sources to do with bus arbitration and multiplexing.

cache   - Contains the sources for the reconfigurable instruction and data
          cache for the rvex processor.

common  - Packages and sources common to all other units.

core    - Contains the sources for the rvex processor itself.

gaisler - Contains interfaces between the rvex processor files and an AMBA bus.
          Requires sources from grlib.

periph  - Basic peripherals to connect to the bus.

system  - Contains system files which wrap the rvex processor core and add
          caches or local on-chip memories to it.

utils   - Utility libraries which are not specific to the rvex processor, but
          are used extensively throughout the rest of the sources.

