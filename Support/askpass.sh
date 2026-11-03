#!/bin/sh
# Homebrew runs `sudo -A` when SUDO_ASKPASS is set (some casks install .pkg files).
# Gingerbrew has no terminal, so ask for the password with a native dialog.
# The password goes straight to sudo on stdout; it is never stored.
exec /usr/bin/osascript \
  -e 'set dialogText to "Homebrew needs your administrator password to continue."' \
  -e 'text returned of (display dialog dialogText default answer "" with hidden answer with title "Gingerbrew" with icon caution buttons {"Cancel", "OK"} default button "OK")'
