
# This script is probably way more complicated than neccesary. by far the one I'm the most unsure of atm
param (
    #Dns name being checked
    [Parameter(Mandatory = $true)]
    [string]$name,

    # Next 2 are only for listing
    [Parameter(Mandatory = $false)]
    [string]$dnsServer,

    [switch]$list
)

# Returns all records on the DNS server
# this part of the script probably doesnt work but I cant test it, the @ was giving me problems despite the documentation saying it was correct
if ($list) {
    if (-not $dnsServer) {
    Write-Error "You must specify a Target DNS server when using the -list switch with -dnsServer"
    exit 1
}
    dnscmd $dnsServer /enumrecords $name [@]
} 

# First section is a bit of a relic from when I was trying to display it a different way, but it works
else {
    $dnsInfo = Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 } | Select-Object InterfaceAlias, ServerAddresses

    # Gives you a nuce little printout showing if it can contact the DNS server
    foreach ($entry in $dnsInfo) {
        # Skip if no DNS servers are listed
        if (-not $entry.ServerAddresses -or $entry.ServerAddresses.Count -eq 0) {
            continue
        }

        Write-Host "`nInterface: $($entry.InterfaceAlias)" -ForegroundColor Cyan

        foreach ($server in $entry.ServerAddresses) {
            Write-Host -NoNewline "Checking DNS server: $server... "

            if (Test-Connection -ComputerName $server -Count 2 -Quiet -ErrorAction SilentlyContinue) {
                Write-Host "Reachable" -ForegroundColor Green
            } 
            else {
                Write-Host "Not reachable" -ForegroundColor Red
            }
        }
    }

    # Attempt to resolve the DNS name using nslookup and Resolve-DnsName
    try {
        # Nslookup tells you what server is trying to resolve the name, and Resolve-DnsName gives you a much nicer output. Wish this could be a one liner
        nslookup $name 2>&1 | Where-Object { $_ -match '^(Server:|Address:)' } -ForegroundColor Green
        Resolve-DnsName -name $name -ErrorAction Stop

    }
    catch {
        # Main issue with this script atm is that its errors are not very useful. The exception message is almost always the same, despite the potential for it to be a couple issues
        # the -list function was made to help testing problems, but isnt a great bandaid. Would be better if the DNS server check specifically tried to see if it was operational
        # as a DNS server without trying to resolve the name. Maybe have it just try to resolve google.com or something?
        Write-Host "DNS resolution failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}