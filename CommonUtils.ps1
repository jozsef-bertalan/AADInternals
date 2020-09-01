﻿# This script contains common utility functions used in different functions

Function Convert-ByteArrayToB64
{

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true,ValueFromPipeline)]
        [Byte[]]$Bytes,
        [Switch]$UrlEncode,
        [Switch]$NoPadding
    )

    $b64 = [convert]::ToBase64String($Bytes);

    if($UrlEncode)
    {
        $b64 = $b64.Replace("/","_").Replace("+","-")
    }

    if($NoPadding)
    {
        $b64 = $b64.Replace("=","")
    }

    return $b64
}

Function Convert-B64ToByteArray
{

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true,ValueFromPipeline)]
        [String]
        $B64
    )
    $B64 = $B64.Replace("_","/").Replace("-","+")

    # Fill the header with padding for Base 64 decoding
    while ($B64.Length % 4)
    {
        $B64 += "="
    }

    return [convert]::FromBase64String($B64)
}

Function Convert-B64ToText
{

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true)]
        [String]
        $B64
    )

    return [text.encoding]::UTF8.GetString(([byte[]](Convert-B64ToByteArray -B64 $B64)))
}

Function Convert-ByteArrayToHex
{

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true,ValueFromPipeline)]
        [Byte[]]
        $Bytes
    )

    $HexString = [System.Text.StringBuilder]::new($Bytes.Length * 2)

    ForEach($byte in $Bytes){
        $HexString.AppendFormat("{0:x2}", $byte) | Out-Null
    }

    $HexString.ToString()
}


Function Convert-HexToByteArray
{

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true,ValueFromPipeline)]
        [String]
        $HexString
    )

    $Bytes = [byte[]]::new($HexString.Length / 2)

    For($i=0; $i -lt $HexString.Length; $i+=2){
        $Bytes[$i/2] = [convert]::ToByte($HexString.Substring($i, 2), 16)
    }

    $Bytes
}


# Converts OID string to bytes
function Convert-OidToBytes
{

    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline)]
        [String]$Oid
    )
    Process
    {
        $digits = $oid.Split(".")
        $bytes =  @()

        # Encode the first byte
        $bytes += ([byte]$digits[0]) * 40 + ([byte]$digits[1])

        # Calculate the rest
        for($pos = 2; $pos -lt $Digits.Count; $pos++)
        {
            [int]$digit = $digits[$pos]

            # Double byte integer needed 
            if($digit -gt 127)
            {
                # Move $b1 seven bits to right and switch the first bit on
                $b1 = (($digit -shr 7) -bor 0x80)
                # Keep only the "first" 8 bits by nullifying others
                $b2 = ($digit -band 0xFF)

                $bytes += [byte]$b1
                $bytes += [byte]$b2
            }
            else
            {
                $bytes += [byte]$digit
            }

        }

        # Return
        return [byte[]]$bytes

    }
}

# Converts byte array to oid string
function Convert-BytesToOid
{

    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline)]
        [byte[]]$Bytes
    )
    Process
    {
        $pos = 0

        # Check whether we have DER tag. If so, skip the first 2 bytes
        if($Bytes[0] -eq 0x06) 
        {
            $pos=2
        }
        
        # Calculate the first two digits
        $oid="$([byte]($Bytes[$pos]/40)).$([byte]$Bytes[$pos]%40)"

        # Calculate the rest
        for($pos+=1; $pos -lt $Bytes.Count; $pos++)
        {
            # Double byte integer if first bit is set
            if(($Bytes[$pos] -band 0x80) -gt 0)
            {
                $b1 = $Bytes[$pos]
                $b2 = $Bytes[$pos+1]

                # Add the last bit of $b1 to the first bit of $b2 (shift bits one step to right)
                $b2 = $b2 -bor (($b1 -band 1) -shl 7)
                # Switch the first bit of $b1 to 0 and one bit left
                $b1 = ($b1 -band 0x7F) -shr 1

                # Calculate the digit
                $digit = [int]($b1 * 256  + $b2)
                $pos++
            }
            else
            {
                $digit = $Bytes[$pos]
            }
            $oid += ".$digit"
        }

        # Return
        $oid
    }
}

# Load .pfx certificate
function Load-Certificate
{
<#
    .SYNOPSIS
    Loads X509 certificate from the given .pfx file

    .DESCRIPTION
    Loads X509 certificate from the given .pfx file

    .Parameter FileName
    The full path to .pfx file from where to load the certificate

    .Parameter Password
    The password of the .pfx file
    
    .Example
    PS C:\>Get-AADIntCertificate -FileName "MyCert.pfx" -Password -Password "mypassword"

#>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline)]
        [String]$FileName,
        [Parameter(Mandatory=$False)]
        [String]$Password="",
        [Switch]$Exportable
    )
    Process
    {
        if(!(Test-Path $PfxFileName))
        {
            throw "Certificate file $PfxFileName not found!"
        }
        
        # Load the certificate
        try
        {
            if($Exportable)
            {
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2((Get-Item $FileName).FullName, $Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable) -ErrorAction SilentlyContinue
            }
            else
            {
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2((Get-Item $FileName).FullName, $Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet) -ErrorAction SilentlyContinue
            }
            
        }
        catch
        {
            throw "Error opening certificate: $($_.Exception.InnerException.Message)"""
        }
        
        return $Certificate
    }
}


# Loads the private key from the given Certificate
function Load-PrivateKey
{
<#
    .SYNOPSIS
    Loads the private key from the given x509 certificate

    .DESCRIPTION
    Loads the private key from the given x509 certificate
        
    .Example
    $Certificate = Load-Certificate -Filename "mycert.pfx" -Password "myverysecretpassword"
    PS C:\>$PrivateKey = Load-AADIntPrivateKey -Certificate $Certificate 

#>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    Process
    {
        # Store the private key to so that it can be exported
        $cspParameters = [System.Security.Cryptography.CspParameters]::new()
        $cspParameters.ProviderName = "Microsoft Enhanced RSA and AES Cryptographic Provider"
        $cspParameters.ProviderType = 24
        $cspParameters.KeyContainerName ="AADInternals"
            
        # Get the private key from the certificate
        $privateKey = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048,$cspParameters)
        $privateKey.ImportParameters([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate).ExportParameters($true))
        
        Write-Verbose "Private Key from $($Certificate.Subject) loaded to the certificate store."
        Write-Debug   "PK: $( Convert-ByteArrayToB64 -Bytes (([System.Security.Cryptography.RSA]::Create($privateKey.ExportParameters($true))).key.Export([System.Security.Cryptography.CngKeyBlobFormat]::GenericPublicBlob)) )"

        return $privateKey
    }
}

# Unloads the private key from the store
function Unload-PrivateKey
{
<#
    .SYNOPSIS
    Unloads the private key from the store

    .DESCRIPTION
    Unloads the private key from the store
        
    .Example
    $Certificate = Load-Certificate -Filename "mycert.pfx" -Password "myverysecretpassword"
    PS C:\>$privateKey = Load-AADIntPrivateKey -Certificate $Certificate 
    PS C:\>Unload-AADIntPrivateKey -PrivateKey $privateKey

#>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline)]
        [System.Security.Cryptography.RSA]$PrivateKey
    )
    Process
    {
        try
        {
            # Remove the private key from the store
            $privateKey.PersistKeyInCsp=$false
            $privateKey.Clear()

            Write-Verbose "Private Key unloaded from the certificate store."
        }
        catch
        {
            Write-Verbose "Could not unload Private Key from the certificate store. That's probably just okay: ""$($_.Exception.InnerException.Message)"""
        }
        
    }
}