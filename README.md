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
Go to System -> User manager -> Add</br>
Fill Username, password</br>
Add "admins" group</br>
Grant "WebCfg - All pages" and "User - System: Shell account access" priviledges</br>
(Optional) generate SSH keys for your custom user</br>
<img src="imgs/custom-user.png"></br>
