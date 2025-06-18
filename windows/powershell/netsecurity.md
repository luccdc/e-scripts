# NetSecurity Cmdlets quick guide
The purpose of this guide is to provide an easy to digest resource showing how to use the Netsecurity cmdlet family, which allows for command line management of the windows firewall.

[Generic Verbs- Get, Set, Enable, Disable, New, Remove]: #

### Terms
A **Verb** is the prefix of a Cmdlet, I.E Get, Set, Remove, etc. A **Noun** is the second portion of the cmdlet, which determines the main function of the cmdlet. A **Parameter** is a flag that comes after the cmdlet, denoted by a "-", and is followed by an **Argument** when applicable.

## Nouns:
To this point, only one noun has been defined in this guide. this will be expanded at a later date (If I dont forget)

### NetFirewallRule
The purpose of the NetFirewallRule cmdlet is the viewing and management of individual Windows Firewall rules.

Unless specified, direction is assumed to be inbound

Verbs- Get, Set, Enable, Disable, New, Remove, Copy, Rename, Show

**Universal Parameters**:
These apply to any verb associated with this noun
* -Name, -DisplayName (wildcards accepted)
* -Action (Accepted arguments: NotConfigured, Allow, Block)
* -Direction (Accepted arguments: Inbound, Outbound)
* -Enabled (Accepted arguments: True, False)

Examples:
```powershell 
Get-NetFirewallRule -Action Block -Enabled True # Displays all enabled rules that block a connection

Disable-NetFirewallRule -Name *docker* # Rid the world of the spawn of evil

Disable-NetFirewallRule -Direction Inbound # Step one of securing a windows box

Enable-NetFirewallRule -Direction Inbound -Enabled False # Panic button if securing the windows box is causing more missed service checks than anticipated 
``` 
**Modifying Parameters**:
These Parameters are specific to verbs which modify firewall rules

* -LocalPort (Lists are allowed, in the following forms: 80,443 or 4100-4120)
* -Protocol (Accepted arguments: TCP/UDP/Any. Default is Any)
* -Program (Argument is full path in “”)
* -Description (Always make one!)
* -LocalAddress (Used when trying to restrict particular interfaces but not others. Refer to Microsoft documentation on how to use this one, you can either do single Ips, multiple, a range, or subnets in the form x.x.x.x/XX)
* -OverrideBlockRules (Read the tin. A lot of weird stuff going on with this one, refer to Microsoft)
* -Profile (Accepted arguments: Any, Domain, Private, Public. Or any combo with commas. Default is any)
* -RemoteAddress (Significantly more useful for Network ACLs. Same syntax as LocalAddress)

For creating a firewall rule, you always need a DisplayName, Direction, and Action. You then need one of Local/Remote Port & Protocol, Remote Address, Program, or Interface Type.

Examples:
```powershell
New-NetFireWallRule -DisplayName CCDC-SMB -Direction Inbound -Action Allow -LocalPort 443 -Protocol Any # Allowing in SMB traffic

New-NetFireWallRule -DisplayName CCDC-Knife -Direction Inbound -Action Allow -RemoteAddress 172.16.10.0/24 # Only allowing traffic from a specific subnet

Set-NetFireWallRule -DisplayName CCDC-SMB -LocalPort 445 # Fixing the typo you hopefully caught

New-NetFirewallRule -DisplayName CCDC-Fix -Direction Outbound -Action Allow -RemotePort 5601 -Protocol Any -Profile Domain -Program "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe" -OverrideBlockRules # Last ditch effort before you ask Chris whats going on
```
