#!/bin/sh
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin

# Vers: 1.1 beta
# Date: 10/17/2020
# pfSense/Transmission integration thanks to: HolyK https://forum.netgate.com/topic/150156/pia-automatic-port-forward-update-for-transmission-daemon
# Based on: https://github.com/thrnz/docker-wireguard-pia/blob/master/extra/pf.sh
# Dependencies: xmlstarlet jq
# Compatibility: pfSense 2.4>
# Before starting setup PIA following this guide: https://blog.networkprofile.org/private-internet-access-vpn-on-pfsense/

####### Adjust all of the following variables #######

# PIA Credentials
piauser='PIAuser'
piapass='PIApassword'

# Transmission RPC Credentials
transuser='TransUser'
transpass='TransPass'

# OpenVPN interface name
ovpniface='ovpnc1'

# Alias names for Transmission IP and PORT. Not the real IP nor Port numbers!
ipalias='Transmission_IP'
portalias='Transmission_Port'

######################## MAIN #########################
# Wait for VPN interface to get fully UP
# Increase this if you have very slow connection or connecting to PIA servers with huge response times
sleep 10

# pfSense config file and tempconfig location
conffile='/cf/conf/config.xml'
tmpconffile='/tmp/tmpconfig.xml'

# Fetch remote Transmission IP from config
transip=$(xml sel -t -v "//alias[name=\"$ipalias\"]/address" $conffile)

###### Nextgen PIA port forwarding #######
# If your connection is unstable you might need to adjust these.
curl_max_time=15
curl_retry=5
curl_retry_delay=15

get_auth_token () {
  tok=$(curl --interface ${ovpniface} --insecure --silent --show-error --request POST --max-time $curl_max_time \
    --header "Content-Type: application/json" \
    --data "{\"username\":\"$piauser\",\"password\":\"$piapass\"}" \
    "https://www.privateinternetaccess.com/api/client/v2/token" | jq -r '.token')
  tok_rc=$?
  if [ "$tok_rc" -ne 0 ]; then
    logger "[PIA-API] Error! Failed to acquire auth token!"
    exit 1
  fi
}
get_auth_token > /dev/null 2>&1

bind_port () {
  pf_bind=$(curl --interface ${ovpniface} --insecure --get --silent --show-error \
    --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
    --data-urlencode "payload=$pf_payload" \
    --data-urlencode "signature=$pf_getsignature" \
    "https://$pf_host:19999/bindPort")
  if [ "$(echo "$pf_bind" | jq -r .status)" != "OK" ]; then
    logger "[PIA-API] Error! Failed to bind received port!"
    exit 1
  fi
}

get_sig () {
  pf_getsig=$(curl --interface ${ovpniface} --insecure --get --silent --show-error \
    --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
    --data-urlencode "token=$tok" \
    "https://$pf_host:19999/getSignature")
  if [ "$(echo "$pf_getsig" | jq -r .status)" != "OK" ]; then
    logger "[PIA-API] Error! Failed to receive Signature!"
    exit 1
  fi
  pf_payload=$(echo "$pf_getsig" | jq -r .payload)
  pf_getsignature=$(echo "$pf_getsig" | jq -r .signature)
  pf_port=$(echo "$pf_payload" | b64decode -r | jq -r .port)
  pf_token_expiry_raw=$(echo "$pf_payload" | b64decode -r | jq -r .expires_at)
  pf_token_expiry=$(date -jf %Y-%m-%dT%H:%M:%S "$pf_token_expiry_raw" +%s)
}

# Rebind every 15 mins (same as desktop app)
pf_bindinterval=$(( 15 * 60))

# Get a new token when the current one has less than this remaining
# Defaults to 7 days (same as desktop app)
pf_minreuse=$(( 60 * 60 * 24 * 7 ))

pf_remaining=0
vpn_ip=$(traceroute -i ${ovpniface} -m 1 privateinternetaccess.com | tail -n 1 | awk '{print $2}')
pf_host="$vpn_ip"
log_cycle=0
reloadcfg=0

while true; do
  pf_remaining=$(( pf_token_expiry - $(date +%s) ))
  # Get a new pf token as the previous one will expire soon
  if [ $pf_remaining -lt $pf_minreuse ]; then
    get_sig
    bind_port
  fi
  
  # Some checks that we received valid port number and not some garbage.
  if [ -z "$pf_port" ]; then
    pf_port='0'
    logger "[PIA] You are not connected to a PIA region that supports port forwarding. Aborting..."
    exit 1
  elif ! [ "$pf_port" -eq "$pf_port" ] 2> /dev/null; then
    logger "[PIA] Fatal error! Value $pf_port is not a number. PIA API has most probably changed. Manual check necessary."
    exit 1
  elif [ "$pf_port" -lt 1024 ] || [ "$pf_port" -gt 65535 ]; then
    logger "[PIA] Fatal error! Value $pf_port outside allowed port range. PIA API has most probably changed. Manual check necessary."
    exit 1
  fi
  
  # Get current NAT port number using xmlstarlet to parse the config file.
  natport=$(xml sel -t -v "//alias[name=\"$portalias\"]/address" $conffile)

  # If the acquired port is the same as already configured do not pointlessly reload config.
  if [ "$natport" -eq "$pf_port" ]; then
    reloadcfg=0
    if [ "$log_cycle" -lt 3 ]; then
      logger "[PIA] Acquired port $pf_port equals the already configured port $natport - no action required."
      log_cycle=$((log_cycle+1))
    elif [ "$log_cycle" -eq 3 ]; then
      logger "[PIA] Acquired port $pf_port equals the already configured port $natport - no action required. Silencing further messages."
      log_cycle=$((log_cycle+1))
    fi
	else
    # If the port has changed update the tempconfig file and reset the log cycle.
    logger "[PIA] Acquired NEW forwarding port: $pf_port, current NAT rule port: $natport"
    xml ed -u "//alias[name=\"$portalias\"]/address" -v $pf_port $conffile > $tmpconffile
    log_cycle=0
    reloadcfg=1
  fi

  # Validate the XML file just to ensure we don't nuke whole configuration
  xml val -q $tmpconffile
  xmlval=$?
  if [ "$xmlval" -gt 0 ]; then
	 logger "[PIA] Fatal error! Updated tempconf file $tmpconffile does not have valid XML format. Verify that the port alias is correct in script header and exists in pfSense Alias list"
	 exit 1
  fi

  # If the updated tempconfig is valid and the port changed update and reload config
  if [ "$reloadcfg" -eq 1 ]; then
    cp $conffile ${conffile}.bck
    cp $tmpconffile $conffile
    # Force pfSense to re-read it's config and reload the rules.
    rm /tmp/config.cache
    /etc/rc.filter_configure
    logger "[PIA] New port $pf_port updated in pfSense config file."
  fi

  ###### Remote update of the Transmisson port #######
  # Check if Transmission host is reachable
  ping -c1 -t1 -q "$transip" > /dev/null 2>&1
  pingrc=$?
  if [ "$pingrc" -gt 0 ]; then
    if [ -z "${thost_log+x}" ] || [ "$thost_log" -eq 1 ]; then
      logger "[Trans] Error! Transmission host $transip is not reachable! Port update skipped. Won't log further failures till success."
      thost_log=0
    fi
  else
    thost_log=1
    # Check if the Transmission RPC service is running
    curl --silent --connect-timeout 10 "$transip":9091/transmission/rpc > /dev/null 2>&1
    curlrc=$?
    if [ "$curlrc" -gt 0 ]; then
      if [ -z "${trpc_log+x}" ] || [ "$trpc_log" -eq 1 ]; then
        logger "[Trans] Error! Transmission service is NOT reachable on $transip. Check the service. Won't log further failures till success."
        trpc_log=0
      fi
    else
      trpc_log=1
      # Update the Transmission port
      session_header=$(curl --silent --user $transuser:$transpass "${transip}":9091/transmission/rpc | sed 's/.*<code>//g;s/<\/code>.*//g')
      if [ -n "$session_header" ]; then
        getdata="{\"method\": \"session-get\"}"
        getport=$(curl -u $transuser:$transpass --silent http://"${transip}":9091/transmission/rpc -d "$getdata" -H "$session_header" | sed 's/.*\"peer-port\"://g;s/,\".*//g' )
        if [ "$getport" -ne "$pf_port" ]; then
          setdata="{\"method\": \"session-set\", \"arguments\": { \"peer-port\" : $pf_port } }"
          setport=$(curl -u $transuser:$transpass --silent http://"${transip}":9091/transmission/rpc -d "$setdata" -H "$session_header" | sed 's/.*result\":\"//g;s/\".*//g' )
          if [ "$setport" = "success" ]; then
            logger "[Trans] New port $pf_port successfully updated in remote Transmission system."
            tport_log=1
          elif [ -z "${tport_log+x}" ] || [ "$tport_log" -eq 1 ]; then
            logger "[Trans] Error! Failed to update the port. Response from RPC was: \"$setport\". Won't log further failures till success."
            tport_log=0
          fi
        fi
      fi
    fi
  fi

  sleep $pf_bindinterval &
  wait $!
  bind_port

done
