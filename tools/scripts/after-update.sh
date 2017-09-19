
# Remove OpenSUSE update repositories now that they no longer work.
if [ ! -f ~/.update-repos-removed ]; then
  echo "Disabling broken software repositories..."
  sudo zypper rr openSUSE-13.2-Debug
  sudo zypper rr openSUSE-13.2-Update-Debug
  sudo zypper rr openSUSE-13.2-Update-Debug-Non-Oss
  sudo zypper rr openSUSE-13.2-Source
  sudo zypper rr openSUSE-13.2-Update
  sudo zypper rr openSUSE-13.2-Update-Non-Oss
  touch ~/.update-repos-removed
fi

# Disable dropbox service now that we use a websocket connection for the boardserver.
if [ ! -f ~/.dropbox-disabled ]; then
  echo "Disabling dropbox..."
  dropbox autostart n
  dropbox stop
  touch ~/.dropbox-disabled
fi

# Nothing here yet.
echo "Everything up-to-date."


