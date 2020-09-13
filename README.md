# PIA NextGen Servers Port Forwarding
New PIA pfSense (Private Internet Access) port forwarding API script for next gen servers. Coming soon: standalone script.

Before starting make sure to have configured PIA on your pfSense according to this guide: https://blog.networkprofile.org/private-internet-access-vpn-on-pfsense/

The scripts have variables that you must change in order for the script to work, make sure to read the scripts before running them.

Your pfSense needs the following packages: `xmlstarlet` `jq` `base64`

About base64: if you can't install base64 with `pkg install base64` download the binary from here: https://pkg.freebsd.org/FreeBSD:11:amd64/quarterly/All/base64-1.5_1.txz , install it with `pkg-static install base64-1.5_1.txz` and verify base64 is present in `/usr/local/bin`

Now you can follow the Installation Guide:

# **pfSense side**

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
-Create new rule like bellow (blue values could be different depending on your current VPN configuration)</br>
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
-paste following code and save ( :wq )</br>

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
