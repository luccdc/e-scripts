param (
    # Domain name being checked
    [Parameter(Mandatory = $false)]
    [string]$Name,

    # These 2 are only for listing 
    [Parameter(Mandatory = $false)]
    [string]$DnsServer,

    [switch]$List
)

# Usage was done by AI but its so cool
function Show-Usage {
    Write-Host "`nUsage:" -ForegroundColor Yellow
    Write-Host "  .\$(Split-Path -Leaf $PSCommandPath) -Name <DomainName> [-List] [-DnsServer <ServerNameOrIP>]" -ForegroundColor White
    Write-Host "`nParameters:" -ForegroundColor Yellow
    Write-Host "  -Name        Domain name to resolve or check." -ForegroundColor White
    Write-Host "  -List        List all records for the given domain (requires -DnsServer)." -ForegroundColor White
    Write-Host "  -DnsServer   Target DNS server for listing." -ForegroundColor White
    Write-Host "`nExamples:" -ForegroundColor Yellow
    Write-Host "  Check DNS servers and resolve a name:" -ForegroundColor White
    Write-Host "    .\dnscheck.ps1 -Name example.com" -ForegroundColor DarkGray
    Write-Host "  List records from a specific DNS server:" -ForegroundColor White
    Write-Host "    .\dnscheck.ps1 -Name example.com -List -DnsServer 192.168.1.1" -ForegroundColor DarkGray
    Write-Host ""
}

# Show usage if parameters are invalid
if ($List -and -not $DnsServer) {
    Write-Error "You must specify -DnsServer when using -List."
    Show-Usage
    exit 1
}

if (-not $Name) {
    Write-Error "Missing required parameter: -Name."
    Show-Usage
    exit 1
}


# Function returns all of the records on a given DNS server. Only run when List is true
function Show-Records {
    param(
        [string]$Target,
        [string]$Zone
    )

    try {
        $records = dnscmd $Target /enumrecords $Zone '@' 2>&1
        # since dnscmd is a cmd utility and not a cmdlet, error handling was a bit weird. This should work
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to enumerate records from $Target"
        }
        # Returns the string value of dnscommand
        $records
    }
    catch {
        Write-Error "Error retrieving DNS records: $_"
    }
}


function Test-Servers {
    $dnsInfo = Get-DnsClientServerAddress | # Grabs all DNS servers for each interface
        Where-Object { $_.AddressFamily -eq 2 } | # Only ones with ipv4 addresses
        Select-Object InterfaceAlias, ServerAddresses # Selects both the interface its on, and the IP of the dns server

    foreach ($entry in $dnsInfo) {
        if (-not $entry.ServerAddresses -or $entry.ServerAddresses.Count -eq 0) { # if the entry is either null or 0, skip it. This does happen, as if the record is only ipv6 then it will still grab it unfortunatly
            continue # Continue is neat- it skips the current loop but doesnt break and moves on to the next item
        }


        # if you are struggling to read the next 2 lines, its nested arrays. 
        Write-Host "`nInterface: $($entry.InterfaceAlias)" -ForegroundColor Cyan
        foreach ($server in $entry.ServerAddresses) {
            Write-Host -NoNewline "Checking DNS server: $server... "
            # Test-NetConnection returns a bool when Informationlevel is set to Quiet. very neat!
            if (Test-NetConnection -ComputerName $server -Port 53  -InformationLevel Quiet -ErrorAction SilentlyContinue) {
                Write-Host "Port 53 Reachable and accepting." -ForegroundColor Green
            }
            else {
                # Actually a great error check. This step *can* be slow, but it will give an overview of if it can connect to the host VIA ICMP, what its route was, etc etc. 
                Write-Host "Server is either unreachable or blocking traffic to port 53. Printing diagnostic overview" -ForegroundColor Red
                Test-NetConnection -ComputerName $server -TraceRoute -informationlevel detailed
            }
        }
    }
}

function Resolve-Dns {
    param(
        [string]$QueryName
    )

    try {
        # prints out the responding DNS server, along with its address
        $nsResult = nslookup $QueryName 2>&1 | Where-Object { $_ -match '^(Server:|Address:)' }
        if ($nsResult) {
            Write-Host "`nNSLookup Results:" -ForegroundColor Yellow
            $nsResult
        }
        else {
            Write-Warning "No nslookup results. Check to see if computer is on fire and/or someone ran chatgpt powershell"
        }

        # Resolve-DnsName
        Write-Host "`nResolve-DnsName Results:" -ForegroundColor Yellow
        Resolve-DnsName -Name $QueryName -ErrorAction Stop # throws if an error occurs. Otherwise prints all of the records associated with the query
    }
    catch {
        Write-Host "DNS resolution failed." -ForegroundColor Red
        Write-Warning $_.Exception.Message
    }
}

# --- Main ---

if ($List) {
    if (-not $DnsServer) {
        Write-Error "You must specify a target DNS server with -DnsServer when using -List."
        exit 1
    }
    Show-Records -Target $DnsServer -Zone $Name
}
else {
    Test-Servers
    Resolve-Dns -QueryName $Name
}




