
$DebugPreference = 'continue'
$Certificate = $null

# my test server in the office
$ComputerName = "10.0.19.219"

$TcpClient = New-Object Net.Sockets.TcpClient
$TcpClient.Connect($ComputerName, 8009)
$TcpStream = $TcpClient.GetStream()

# allow this client to communicate with unauthenticated servers.
$Callback = { param($sender, $cert, $chain, $errors) return $true }

$SslStream = New-Object -TypeName System.Net.Security.SslStream -ArgumentList @($TcpStream, $true, $Callback)

$SslStream.ReadTimeout = 15000
$SslStream.WriteTimeout = 15000
$SslStream.AuthenticateAsClient($ComputerName, $null, [System.Security.Authentication.SslProtocols]::Tls11 -bor [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Default, $false)


$Certificate = $SslStream.RemoteCertificate

$writer = new-object System.IO.StreamWriter($sslStream)
$reader = New-Object System.IO.StreamReader($SslStream)

$len = 0

# Try the following test code when connectiing to my SSL test server
$data = "Hello from the client.<EOF>";
$buffer = new-object byte[] 2048
$encoder = new-object System.Text.ASCIIEncoding
$bytes = $encoder.Getbytes($data)
<#
[array]::Copy($bytes, 0, $buffer, 1, $bytes.Length)
$writer.Write($buffer, 0, $bytes.Length)
#>
$writer.Write($bytes, 0, $bytes.Length)
$writer.Flush()


$buffer = new-object byte[] 2048
$sessionId = ''
while ($sessionId -eq '')
{
    if($SslStream.CanRead -eq $true)
    {   
        $num = $reader.Read($buffer, 0, 2048);
    }
}

Write-Debug "session + sessionId"


