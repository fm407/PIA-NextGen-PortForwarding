# PIA NextGen Servers Port Forwarding
New PIA pfSense (Private Internet Access) port forwarding API script for next gen servers. Tested on pfSense 2.4.5-RELEASE-p1 (amd64).

# **Before starting make sure to have configured PIA on your pfSense according to this guide: https://blog.networkprofile.org/private-internet-access-vpn-on-pfsense/**

For a list of nextgen servers supporting port forwarding: https://github.com/fm407/PIA-NextGen-PortForwarding/blob/master/nextgen-portforward-servers.txt 

The scripts have variables that you must change in order for the script to work, make sure to read the scripts before running them.

Your pfSense needs the following packages: `xmlstarlet` `jq` `base64`

About base64: if you can't install base64 with `pkg install base64` download the binary from here: https://pkg.freebsd.org/FreeBSD:11:amd64/quarterly/All/base64-1.5_1.txz , install it with `pkg-static install base64-1.5_1.txz` and verify base64 is present in `/usr/local/bin`

Now you can follow this guide:

# **I. pfSense side**

**1.Enable SSH on pfSense**</br>
System -> Advanced => tick "Enable Secure Shell"</br>
<img src="imgs/ssh.png">

**2.Create custom user**</br>
-Go to System -> User manager -> Add</br>
-Fill Username, password</br>
-Add "admins" group</br>
-Grant "WebCfg - All pages" and "User - System: Shell account access" priviledges</br>
-(Optional) generate SSH keys for your custom user</br>
<img src="imgs/custom-user.png"></br>

**3.Install SUDO package**</br>
-Go to System -> Package Manager => install SUDO package</br>
-Go to System -> sudo => create user permissions as bellow</br>
<img src="imgs/sudo.png"></br>

**4.Create Alias for port forward**</br>
-Go to Firewall -> Aliases -> Ports</br>
-Create new port with name "Transmission_Port"</br>
-Give it the current port (if you have it) or non-zero value</br>
<img src="imgs/port-alias.png"></br>

**5.Create Alias for Transmission IP address**</br>
-Go to Firewall -> Aliases -> IP</br>
-Create new port with name "Transmission_IP"</br>
-Define IP or FQDN of your Transmisson daemon server</br>
<img src="imgs/ip-alias.png"></br>

**6.Create NAT rule for port-forward using the ALIAS instead of specific port/IP**</br>
-Go to Firewall -> NAT</br>
-Create new rule like bellow (some values could be different depending on your current VPN configuration)</br>
<img src="imgs/pia-nat.png"></br>

**7.Generate SSH keys for enhanced security**</br>
-SSH to the pfSense box with the user created in step 2.</br>
```
sudo su -
#<enter your user password>
#Enter an option: 8 for shell
mkdir .ssh
chmod 700 .ssh
cd .ssh
ssh-keygen -b 4096 -f ~/.ssh/id_rsa
#When prompted for "Enter passphrase" just hit ENTER twice
#Files id_rsa and id_rsa.pub will be generated.
cat id_rsa.pub
```
**Store the content of id_rsa.pub somewhere as it will be required later on**</br>

**8.Create custom devd config file**</br>
-Still under root user from previous step do</br>
```
mkdir /usr/local/etc/devd
cd /usr/local/etc/devd
vi piaport.conf
```
-paste following code and save ( :wq )- This will start the service when the PIA interface is up and stop it when down</br>

```
notify 0 {
        match "system"          "IFNET";
        match "subsystem"       "(ovpnc1)";
        match "type"            "LINK_UP";
        action "logger $subsystem is UP";
        action "service pia-portforwarding start";
};

notify 0 {
        match "system"          "IFNET";
        match "subsystem"       "(ovpnc1)";
        match "type"            "LINK_DOWN";
        action "logger $subsystem is DOWN";
        action "service pia-portforwarding stop";
};
```

**Note: The "ovpnc1" is a technical name of the OpenVPN interface from within the pfSense UI**</br>
<img src="imgs/pia-iface.png"></br>

**9.Create the custom port-update script**</br>
-Still under root user from previous step do</br>

```
mkdir -p /home/custom/piaportforward
cd /home/custom/piaportforward
touch pia-pfSense.sh
chmod u+x pia-pfSense.sh
vi pia-pfSense.sh
```
-Paste the code from https://github.com/fm407/PIA-NextGen-PortForwarding/blob/master/pia-pfSense.sh OR just download it and chmod +x it.</br>
**!!! Some customization is necessary. Please read the script. It will need at minimum your PIA user and pass and the Transmission host ssh user !!!**</br>

Put https://github.com/fm407/PIA-NextGen-PortForwarding/blob/master/pia-portforwarding-rc in `/usr/local/etc/rc.d` (rename to pia-portforwarding) and chmod +x it or just:</br>
```
touch /usr/local/etc/rc.d/pia-portforwarding
chmod +x /usr/local/etc/rc.d/pia-portforwarding
vi /usr/local/etc/rc.d/pia-portforwarding
```

And paste the following in it:</br>

```
#!/bin/sh

. /etc/rc.subr

name=pia-portforwarding
rcvar=`set_rcvar`
command=/home/custom/piaportforward/pia-pfSense.sh
start_cmd="/usr/sbin/daemon $command"

load_rc_config $name
run_rc_command "$1"
```

-Disconnect form pfSense</br>
-(Optional) Disable SSH via WebUI under System -> Advanced => un-tick "Enable Secure Shell"</br>
</br>

# **II. Transmission host side**</br>
-This part is for a Debian 10 host, your mileage may vary depending on the distro you use for your Transmission host.</br>
-If there is something already configured on your side please read the steps anyway just to be sure there are no tiny difference.</br>

**1.Enable and start SSH daemon**</br>

```
systemctl enable ssh
systemctl start ssh
```

Verify the service is running:</br>
`systemctl status ssh`
</br>

**2.Secure Transmission RPC Protocol**</br>
-This is optional but recommended for security purpose</br>
-STOP the transmission daemon by `systemctl stop transmission`</br>
-Edit /etc/transmission-daemon/settings.json</br>
-Note that the location of settings.json may vary. The above path is from Debian 10.</br>
-Update/add following parameters. Replace username, password. Ensure that IP address of your pfSense is in whitelist.</br>

```
"rpc-authentication-required": true,
"rpc-username": "SomeUserName",
"rpc-password": "SomePassword",
"rpc-whitelist": "127.0.0.1,10.10.10.1,10.10.10.5",
```

-Start the transmission service again `systemctl start transmission`</br>


**3.Create local port-update script**</br>
-This needs to be done under an unpriviledge user, not as root!</br>

```
su - transmission
touch ~/transportupdate.sh
chmod u+x ~/transportupdate.sh
vi ~/transportupdate.sh
```

-Paste the code bellow OR just download https://github.com/fm407/PIA-NextGen-PortForwarding/blob/master/transportupdate.sh and chmod +x it.</br>
**-UPDATE the USERNAME='username' and PASSWORD='password' at the beginning of the file as per the credentials configured in step II.2.**</br>

```

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
#TRANSREMOTE='transmission-remote'
TRANSREMOTE='/usr/bin/transmission-remote'

############ Rest of the code - do not touch #############

# Port numbers
NEWPORT="$1"

# Verify that received new port is a valid number.
if ! [ "$NEWPORT" -eq "$NEWPORT" ] 2> /dev/null; then
    logger "Non-numeric port ( $NEWPORT ) received from remote host. Aborting!"
    # EMAIL
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
```

**4.Create/Upload public SSH key for pfSense connection**</br>
-Still under transmission user</br>

```
mkdir ~/.ssh
chmod 700 ~/.ssh
cd ~/.ssh
touch authorized_keys
chmod 644 authorized_keys
vi authorized_keys
```

**-Paste the content of id_rsa.pub generated in step I.7. and save ( :wq )**</br>

**5.Restart OpenVPN in pfSense**</br>
<img src="imgs/pia-restart.png"></br>
-Wait for ~15secs and check Status -> System logs to see results</br>
<img src="imgs/pia-status.png"></br>
-All OK, port changed</br>
<img src="imgs/pia-success.png"></br>

