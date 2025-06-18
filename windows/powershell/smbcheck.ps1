# Parameters can be fed in either through command line flags or manually when running the script
param (
    [Parameter(Mandatory)]
    [string]$CName,

    [Parameter(Mandatory)]
    [string]$SName
)

$target = "\\$CName\$SName"

try {
    # Checks if the Path is avalible, throws all non terminating errors
    $connection = Test-Path $target -ErrorAction Stop
    # Test-Path returns a boolean
    if ($connection) {
        Write-Host "SMB connection to $target succeeded. Displaying contents: `n"
        Get-ChildItem -Path $target
    } else {
        # If Test-Path returns false, the share is not accessible. Does not throw an exception
        Write-Host "SMB connection to $target failed: Share not accessible."
    }
}
# Catches any exceptions thrown by Test-Path, such as network issues or permission errors
catch {
    Write-Host "SMB connection to $target failed with error:"
    Write-Host $_.Exception.GetType().FullName "`n"
    Write-Host $_.Exception.Message
}