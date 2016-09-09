#!/bin/bash

echo ""
echo "Updating MCA/ECA workspace and tools..."
echo ""
echo "git pull update master"

cd /home/user/workspace
if git pull update master
then
    echo ""
    echo "Done. Press enter to close this terminal."
else
    echo ""
    echo "It seems like an error occurred."
    echo ""
    echo "If you know how git works, you may be able to fix it yourself. Basically, you"
    echo "just need to pull from the 'update' remote (to use the private key of this VM"
    echo "to get access to the repository) into /home/user/workspace. If you don't know"
    echo "what the error means, contact the lab assistents with the above git output."
    echo "You can copy from the terminal using ctrl+shift+c."
    echo ""
    echo "Press enter to close this terminal."
fi

read dummy
