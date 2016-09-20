echo "*********** SIMULATING UNTIL PHY INIT COMPLETES ***********"
when -label saveState {sim:/testbench/d3/rstn = '1'} {echo "Reset released, stopping sim..."; stop -sync }
run -all
echo "Adding relevant signals to trace..."
do signals.do
echo "Saving state..."
checkpoint modelsim/cpt
nowhen saveState
echo "*********** PHY INIT COMPLETE, CHECKPOINT SAVED ***********"

