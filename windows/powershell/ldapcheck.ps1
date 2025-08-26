# Script still in testing phase. Idea behind it is very cool, but complexity is high, and I want to be able to document it well

# Prompt user for input
# Hard code domain prior to running in comp

# Will add the ability to pass in parameters later, but for now I need to run more testing first
$domain = Read-Host "Enter domain (example.com)"
$username = Read-Host "Enter username"
$password = Read-Host "Enter password" -AsSecureString
# Prevents the password from being displayed in plain text in the console. This makes the script messier, but more secure.
# When marshal is used to convert the secure string to a plain text string, it will expose the password in memory. This is not ideal
# Solution to the memory problem given by AI:
    #$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    #$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)

# Zero out and free the unmanaged memory (important for security)
    #[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
# Requires more testing to see if this is trustworthy or neccesary


# Convert secure string to plain text for LDAP use
# Marshal is a NET class used to convert between managed and unmanaged code (In this case, raw memory)
# Second half turns the secure string into a BSTR (Binary String), and then returns a pointer to that BSTR (This is the piece that exposes the password in memory)
# The pointer is then converted to a plain string using the PtrToStringAuto
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
)

# Construct the LDAP path and credentials
$ldapPath = "LDAP://$domain"
$userPrincipal = "$domain\$username"

try {
    # Create the DirectoryEntry object with credentials
    # This does not create an object in the directory, it creates a local object that represents the LDAP path and credentials you want to use to access it
    $entry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $userPrincipal, $plainPassword)

    # Attempt to access a property to trigger the bind
    # This takes the path and credentials you provided before, and attempts to bind to the LDAP server using those credentials
    # This seems like a really weird and specific way to do this, but stackoverflow said it was a good idea, and I cant see any reason why it wouldnt wory or be insecure.
    $native = $entry.NativeObject

    Write-Host "LDAP authentication successful."
}
catch {
    Write-Host "LDAP connection to $domain as $username failed with error:" -ForegroundColor Red
    Write-Host $_.Exception.GetType().FullName "`n" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
