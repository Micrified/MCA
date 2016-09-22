
echo "Making workspace pristine..."
cd ~/workspace
git status
git clean -fdx --dry-run
echo 'If the above looks good, press enter. Otherwise, ctrl+c.'
read dummy
git clean -fdx
git reset --hard

echo "Resetting group number configuration..."
rm -rf ~/boardserver
cd ~/.dropbox-folder/Dropbox
dropbox exclude add `ls`

echo "Clearing bash history..."
rm -f ~/.bash_history

echo "Clearing firefox history..."
rm ~/.mozilla/firefox/*.default/cookies.sqlite
rm ~/.mozilla/firefox/*.default/*.sqlite ~/.mozilla/firefox/*default/sessionstore.js
rm -r ~/.cache/mozilla/firefox/*.default/*

