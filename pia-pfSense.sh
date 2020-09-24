#!/bin/sh
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin

# Vers: 0.1 beta
# Date: 9/13/2020
# pfSense/Transmission integration thanks to: HolyK https://forum.netgate.com/topic/150156/pia-automatic-port-forward-update-for-transmission-daemon
# Based on: https://github.com/thrnz/docker-wireguard-pia/blob/master/extra/pf.sh
# Dependencies: xmlstarlet jq
# Compatibility: pfSense 2.4>
# Before starting setup PIA following this guide: https://blog.networkprofile.org/private-internet-access-vpn-on-pfsense/

###### Update these variables if necessary ######

# OpenVPN interface name
OVPNIFACE='ovpnc1'

# Alias name for port forward
PORTALIAS='Transmission_Port'

# Alias name for Transmission IP
IPALIAS='Transmission_IP'

############## Other vars - do not touch ###################

# pfSense config file and tempconfig location
CONFFILE='/cf/conf/config.xml'
TMPCONFFILE='/tmp/tmpconfig.xml'

# Fetch remote Transmission IP from config
TRANSIP=`xml sel -t -v "//alias[name=\"$IPALIAS\"]/address" $CONFFILE`

########################  MAIN  #########################

# Wait for VPN interface to get fully UP  
sleep 10

###### PIA Variables ######
curl_max_time=15
curl_retry=5
curl_retry_delay=15
user='YOUT PIA USERNAME'
pass='YOUR PIA PASSWORD'

###### Nextgen PIA port forwarding      ##################

get_auth_token () {
    tok=$(curl --interface ${OVPNIFACE} --insecure --silent --show-error --request POST --max-time $curl_max_time \
        --header "Content-Type: application/json" \
        --data "{\"username\":\"$user\",\"password\":\"$pass\"}" \
        "https://www.privateinternetaccess.com/api/client/v2/token" | jq -r '.token')
    [ $? -ne 0 ] && echo "Failed to acquire new auth token" && exit 1
    echo "$tok"
}

get_auth_token > /dev/null 2>&1

bind_port () {
  pf_bind=$(curl --interface ${OVPNIFACE} --insecure --get --silent --show-error \
      --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
      --data-urlencode "payload=$pf_payload" \
      --data-urlencode "signature=$pf_getsignature" \
      $verify \
      "https://$pf_host:19999/bindPort")
  if [ "$(echo $pf_bind | jq -r .status)" != "OK" ]; then
    echo "$(date): bindPort error"
    echo $pf_bind
    fatal_error
  fi
}

get_sig () {
  pf_getsig=$(curl --interface ${OVPNIFACE} --insecure --get --silent --show-error \
    --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
    --data-urlencode "token=$tok" \
    $verify \
    "https://$pf_host:19999/getSignature")
  if [ "$(echo $pf_getsig | jq -r .status)" != "OK" ]; then
    echo "$(date): getSignature error"
    echo $pf_getsig
    fatal_error
  fi
  pf_payload=$(echo $pf_getsig | jq -r .payload)
  pf_getsignature=$(echo $pf_getsig | jq -r .signature)
  pf_port=$(echo $pf_payload | b64decode -r | jq -r .port)
  pf_token_expiry_raw=$(echo $pf_payload | b64decode -r | jq -r .expires_at)
  pf_token_expiry=$(date -jf %Y-%m-%dT%H:%M:%S "$pf_token_expiry_raw" +%s)
}


# Rebind every 15 mins (same as desktop app)
pf_bindinterval=$(( 15 * 60))
# Get a new token when the current one has less than this remaining
# Defaults to 7 days (same as desktop app)
pf_minreuse=$(( 60 * 60 * 24 * 7 ))

pf_remaining=0
pf_firstrun=1
vpn_ip=$(traceroute -i ${OVPNIFACE} -m 1 privateinternetaccess.com | tail -n 1 | awk '{print $2}')
pf_host="$vpn_ip"

while true; do
  pf_remaining=$((  $pf_token_expiry - $(date +%s) ))
  # Get a new pf token as the previous one will expire soon
  if [ $pf_remaining -lt $pf_minreuse ]; then
    if [ $pf_firstrun -ne 1 ]; then
      echo "$(date): PF token will expire soon. Getting new one."
    else
      echo "$(date): Getting PF token"
      pf_firstrun=0
    fi
    get_sig
    echo "$(date): Obtained PF token. Expires at $pf_token_expiry_raw"
    bind_port
    echo "$(date): Server accepted PF bind"
    echo "$(date): Forwarding on port $pf_port"
    echo "$(date): Rebind interval: $pf_bindinterval seconds"
  fi
  
if [ "$pf_port" == "" ]; then
    pf_port='0'
    logger "[PIA] Port forwarding is already activated on this connection, has expired, or you are not connected to a PIA region that supports port forwarding."
    exit 0
  elif ! [ "$pf_port" -eq "$pf_port" ] 2> /dev/null; then
    logger "[PIA] Fatal error! Value $pf_port is not a number. PIA API has most probably changed. Manual check necessary."
    exit 1
  elif [ "$pf_port" -lt 1024 ] || [ "$pf_port" -gt 65535  ]; then
    logger "[PIA] Fatal error! Value $pf_port outside allowed port range. PIA API has most probably changed. Manual check necessary."
    exit 1
  fi
logger "[PIA] Acquired forwarding port: $pf_port"

# Get current NAT port number using xmlstarlet to parse the config file.
NATPORT=`xml sel -t -v "//alias[name=\"$PORTALIAS\"]/address" $CONFFILE`
logger "[PIA] Current NAT rule port: $NATPORT"

# If the acquired port is the same as already configured do not pointlessly reload config.
if [ "$NATPORT" -eq "$pf_port" ]; then
	logger "[PIA] Acquired port $pf_port equals the already configured port $NATPORT - no action required."
	else
# If the port has changed update the tempconfig file.
xml ed -u "//alias[name=\"$PORTALIAS\"]/address" -v $pf_port $CONFFILE > $TMPCONFFILE

# Validate the XML file just to ensure we don't nuke whole configuration
xml val -q $TMPCONFFILE
XMLVAL=$?
if [ "$XMLVAL" -eq 1 ]; then
	logger "[PIA] Fatal error! Updated tempconf file $TMPCONFFILE does not have valid XML format. Verify that the port alias is correct in script header and exists in pfSense Alias list"
	exit 1
fi

# If the updated tempconfig is valid backup and replace the real config file.
cp $CONFFILE ${CONFFILE}.bck 
cp $TMPCONFFILE $CONFFILE

# Force pfSense to re-read it's config and reload the rules.
rm /tmp/config.cache
/etc/rc.filter_configure
logger "[PIA] New port $pf_port updated in pfSense config file."

# Check if Transmission host is reachable
ping -c1 -t1 -q $TRANSIP
PINGRC=$?
if [ "$PINGRC" -gt 0  ]; then
	logger "[PIA] Error! Transmission host $TRANSIP is not reachable!"
	exit 1
fi

# Update remote Transmission config with new port

ssh_user='YOUR SSH USER'

ssh ${ssh_user}@${TRANSIP} "./transportupdate.sh ${pf_port}"
TRANSRC=$?

if [ "$TRANSRC" -gt 0  ]; then
	logger "[PIA] Error! Unable to remotely update Transmission port over SSH!"
	exit 1
fi
logger "[PIA] New port successfully updated in remote Transmission system."
fi

  logger "[PIA] Rebinding Port..."
  sleep $pf_bindinterval &
  wait $!
  echo "Binding..."
  bind_port
  echo "$(date): Server accepted PF bind"
  echo "$(date): Forwarding on port $pf_port"
  echo "$(date): Rebind interval: $pf_bindinterval seconds"


done
