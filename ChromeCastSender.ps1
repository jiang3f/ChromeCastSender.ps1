###############################################
# Send control message to ChromeCast
###############################################


#
# Set Variables
#

 param (
    [Parameter(Mandatory=$false)][hashtable]$soa_hash = @{"soa_time_numerator" = 1; "soa_time_denominator" = 1; "soa_duration_denominator" = 1; "soa_duration_numerator" = 1; "outMedia" = "d:\vantage_store\9f6a097b-a131-4a87-8cb7-42c71f0d30ee\";},
    [URI]$DASH ='file:///d:\vantage_store\6b9e6fb4-9129-4597-b798-7563edeb1ce4\sourcempeg2_422_pro_ntsc\sourcempeg2_422_pro_ntsc.mpd'
#    [URI]$DASH

 )

$DebugPreference = 'continue'

# constant variables
$TYPE_ENUM = 0
$TYPE_STRING = 2
$TYPE_BYTES = $TYPE_STRING
$protocolVersion = 0
$source_id = "sender-0"
$destination_id = "receiver-0"

# Function to get string len
Function GetLenOf ([string] $s, [ref] $len, [ref]$bytes)
{
    $bytes.Value = 0
    $length = $s.Length

    while($length -ge 0x7f)
    {
        $length1 = $length -band 0xff
        $v = $length1 -band 0x7f
        $v = $v -bor 0x80
        $len.Value[$bytes.Value] = $v
        $length = $length -shr 7
        $bytes.Value = $bytes.Value + 1

    }

    $length = $length -band 0x7f
    $len.Value[$bytes.Value] = $length
    $bytes.Value ++
}

Function GetType( [byte] $fieldId, [byte] $t)
{
    $ret = $fieldId -shl 3
    $ret = $ret -bor $t
    return $ret
}


# Function to create Chromecast request
Function CreateRequest ([String] $data, [string] $chrome_namespace, [ref]$offset)
{
    $payloadType = 0

    $msg = new-object byte[] 2048

	$payloadType = 0;
	
    $len = new-object byte[] 4
    $nLen = 0

    GetLenOf $data ([ref]$len) ([ref]$nLen)

    Write-Debug "Send: $data"

	$offset.Value = 4
	$msg[$offset.Value ++] = GetType 1 $TYPE_ENUM
	$msg[$offset.Value ++] = $protocolVersion;
	$msg[$offset.Value ++] = GetType 2 $TYPE_STRING
	$msg[$offset.Value ++] = $source_id.length

    $encoder = new-object System.Text.UTF8Encoding
    $bytes = $encoder.Getbytes($source_id)
    [array]::Copy($bytes, 0, $msg, $offset.Value, $bytes.Length)

	$offset.Value  += $source_id.Length

	$msg[$offset.Value ++] = GetType 3 $TYPE_STRING

	if ($dest)
	{
		$msg[$offset.Value ++] = $dest.Length
        [array]::Copy($dest, 0, $msg, $offset.Value , $dest.Length)
		$offset.Value  += $dest.Length
	}
	else
	{
		$msg[$offset.Value ++] = $destination_id.Length
        $bytes = $encoder.Getbytes($destination_id)
        [array]::Copy($bytes, 0, $msg, $offset.Value , $bytes.Length)
		$offset.Value  += $destination_id.Length
	}

	$msg[$offset.Value ++] = GetType 4 $TYPE_STRING

	$msg[$offset.Value ++] = $chrome_namespace.Length

    $bytes = $encoder.Getbytes($chrome_namespace)
    [array]::Copy($bytes, 0, $msg, $offset.Value , $bytes.Length)

    $offset.Value  += $chrome_namespace.Length;
	$msg[$offset.Value ++] = GetType 5 $TYPE_ENUM
	$msg[$offset.Value ++] = $payloadType
	$msg[$offset.Value ++] = GetType 6 $TYPE_BYTES

    [array]::Copy($len, 0, $msg, $offset.Value , $nLen)

    $offset.Value  += $nLen
    
    $bytes = $encoder.Getbytes($data)
    [array]::Copy($bytes, 0, $msg, $offset.Value , $data.Length)
	$offset.Value  += $data.Length;

    $dataLen = $offset.Value  - 4
    $bytes = [bitconverter]::GetBytes($dataLen)
    [array]::Copy($bytes, 0, $msg, 0 , 4)
    
	return $msg

}

$Certificate = $null

# home 
#$ComputerName = "192.168.1.7"

# office
$ComputerName = "10.0.19.226"

$TcpClient = New-Object -TypeName System.Net.Sockets.TcpClient


$TcpClient.Connect($ComputerName, 8009)
$TcpStream = $TcpClient.GetStream()

# allow this client to communicate with unauthenticated servers.
$Callback = { param($sender, $cert, $chain, $errors) return $true }

$SslStream = New-Object -TypeName System.Net.Security.SslStream -ArgumentList @($TcpStream, $true, $Callback)

$sslStream.ReadTimeout = 5000;
$sslStream.WriteTimeout = 5000;
    
$SslStream.AuthenticateAsClient('')
$Certificate = $SslStream.RemoteCertificate

<# test code
$buffer = new-object byte[] 2048
$sessionId = ''
while ($sessionId -eq '')
{
    if($SslStream.CanRead -eq $true)
    {   
        $sslStream.ReadAsync($buffer, 0, 200);
    }
}#>
    
# connect
Write-Debug "connecting..."

$len = 0
$data = '{"type":"CONNECT","origin":{}}'
$chrome_namespace = "urn:x-cast:com.google.cast.tp.connection";
$msg = CreateRequest $data $chrome_namespace ([ref]$len)

Write-Debug "len = $len"
$sslStream.Write($msg, 0, $len)
$SslStream.Flush()

# get status
$data = '{"type":"GET_STATUS","requestId":46479000}'
$chrome_namespace = "urn:x-cast:com.google.cast.receiver"
$msg = CreateRequest $data $chrome_namespace ([ref]$len)

Write-Debug "len = $len"
$sslStream.Write($msg, 0, $len)
$SslStream.Flush()

$buffer = new-object byte[] 2048
$sessionId = ''
while ($sessionId -eq '')
{
    if($SslStream.CanRead -eq $true)
    {   
        $sslStream.ReadAsync($buffer, 0, 200);
    }
}

Write-Debug "session + sessionId"


