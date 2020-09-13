#!/bin/sh
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin

# Vers: 1.2
# Date: 1.2.2020
# This script has to be placed in the Transmission seedbox
# Script by HolyK https://forum.netgate.com/user/holyk

############ Update these please #############

# Transmission-remote WEB credentials
USERNAME='TRANSMISSION WEBUI USER'
PASSWORD='TRANSMISSION WEBUI PASS'

# Transmission-remote binary is usually under known environment location.
# Validate the command is known by " which transmission-remote "
# If the "transmission-remote" is not known try to " find / -name transmission-remote "
# Then update the variable bellow with full-path to the binary
TRANSREMOTE='/usr/bin/transmission-remote'

############ Rest of the code - do not touch #############

# Port numbers
NEWPORT="$1"

# Verify that received new port is a valid number.
if ! [ "$NEWPORT" -eq "$NEWPORT" ] 2> /dev/null; then
    logger "Non-numeric port ( $NEWPORT ) received from remote host. Aborting!"
    exit 1
fi

# Check if Transmission is running
service transmission-daemon status
TRANSSVCRC=$?
if [ "$TRANSSVCRC" -gt 0  ]; then
  logger "Transmission service is not running. Port update aborted!"
        exit 1
else
  # Configure new port received from remote system
  $TRANSREMOTE --auth ${USERNAME}:${PASSWORD} -p ${NEWPORT}
  TRANSREMOTERC=$?
  if [ "$TRANSREMOTERC" -gt 0  ]; then
    logger "Error when calling transmission-remote binary. Port was NOT updated!"
         exit 1
  fi
  logger "Transmission port succesfully updated. New port is: ${NEWPORT}"
  exit 0
fi
