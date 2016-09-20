#!/usr/bin/python3

import xml.etree.ElementTree as etree
import os
import sys
import shutil

# Check command line.
if len(sys.argv) != 2:
  print('Usage: python3 synthesis-init.py <infile.xise>')
  print()
  print('Will generate:')
  print('  vhdl/<libname>/<source>.vhd')
  print('  constraints.ucf')
  print('  project.prj')
  exit(1)

# Determine the path to the original Xilinx project.
prjdir = os.path.dirname(sys.argv[1])

# Parse xise XML file.
root = etree.parse(sys.argv[1]).getroot()

with open("project.prj", "w") as project:
  with open("constraints.ucf", "w") as ucf:
    
    for i in root.iter('{http://www.xilinx.com/XMLSchema}file'):
      if '{http://www.xilinx.com/XMLSchema}name' not in i.attrib:
        continue
      filename = prjdir + os.sep + i.attrib['{http://www.xilinx.com/XMLSchema}name']
      if '{http://www.xilinx.com/XMLSchema}type' not in i.attrib:
        continue
      impl = False
      for j in i.iter('{http://www.xilinx.com/XMLSchema}association'):
        if '{http://www.xilinx.com/XMLSchema}name' not in j.attrib:
          continue
        if j.attrib['{http://www.xilinx.com/XMLSchema}name'] == 'Implementation':
          impl = True
          break
      
      # Handle VHDL files.
      if i.attrib['{http://www.xilinx.com/XMLSchema}type'] == 'FILE_VHDL':
        lib = "work"
        for j in i.iter('{http://www.xilinx.com/XMLSchema}library'):
          if '{http://www.xilinx.com/XMLSchema}name' not in j.attrib:
            continue
          lib = j.attrib['{http://www.xilinx.com/XMLSchema}name']
          break
        
        # Generate a unique local filename.
        newfilename = 'vhdl' + os.sep + lib + '-' + str(i.attrib['{http://www.xilinx.com/XMLSchema}name']).replace(os.sep, '-')
        
        # Copy the file.
        print('cp "' + filename + '" "' + newfilename + '"')
        shutil.copyfile(filename, newfilename)
        
        # Append to the project file.
        project.write('vhdl %s "%s"\n' % (lib, newfilename))
      
      # Handle UCF files.
      if i.attrib['{http://www.xilinx.com/XMLSchema}type'] == 'FILE_UCF':
        
        # Append to the UCF file.
        ucf.write('\n')
        ucf.write('# ==============================================================================\n')
        ucf.write('# %s\n' % filename)
        ucf.write('# ==============================================================================\n')
        ucf.write('\n')
        with open(filename, "r") as inucf:
          ucf.write(inucf.read())
        
