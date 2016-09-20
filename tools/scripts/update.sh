#!/bin/bash

echo ""
echo "Updating MCA/ECA workspace and tools..."
echo ""
echo "git pull update master"

cd /home/user/workspace
if git pull update master
then
    cd /home/user/workspace/tools/scripts
    if [ -e "after-update.sh" ]
    then
        echo ""
        echo "Running after-update script..."
        echo ""
        echo "after-update.sh"
        ./after-update.sh
    fi
    echo ""
    echo "Done. Press enter to close this terminal."
else
    echo ""
    echo "It seems like an error occurred."
    echo ""
    echo "If you know how git works, you may be able to fix it yourself. Basically, you"
    echo "just need to pull from the 'update' remote (to use the private key of this VM"
    echo "to get access to the repository) into /home/user/workspace. Afterwards, you"
    echo "may need to run /home/user/workspace/tools/scripts/after-update.sh. If you"
    echo "don't know what the error means, contact the lab assistents with the above git"
    echo "output. You can copy from the terminal using ctrl+shift+c."
    echo ""
    echo "Press enter to close this terminal."
fi

read dummy
