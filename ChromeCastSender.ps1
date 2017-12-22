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
Function CreateRequest ([String] $data, [string] $chrome_namespace, [ref]$offset, [string]$dest)
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

	if ($dest -ne '')
	{
		$msg[$offset.Value ++] = $dest.Length
        $bytes = $encoder.GetBytes($dest)
        [array]::Copy($bytes, 0, $msg, $offset.Value , $bytes.Length)
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
    [Array]::Reverse($bytes); 
    [array]::Copy($bytes, 0, $msg, 0 , 4)

  
	return $msg

}

Function ReadMessage( [byte[]] $buffer, [int] $bytes, [ref] $response)
{

	# parsing protobuffer
	$offset = 4
	$offset += 3

	# sender
	$len = $buffer[$offset]
	$offset ++
	$offset += $len

	# receiver
	$offset++
	$len = $buffer[$offset]
	$offset++
	$offset += $len

	# namespac
	$offset++
	$len = $buffer[$offset]
	$offset++
	$offset += $len

	# data
	$offset += 3
	if ($bytes -lt 200)
	{
		$len = $buffer[$offset]
		$offset++
	}
	else
	{
		$offset += 2
		$len = $bytes - $offset
	}
	$len = $bytes - $offset

    $msg = [System.Text.Encoding]::Default.GetString($buffer, $offset, $len)

    #Write-Debug $msg 

    while( $msg -notmatch '.+?}$')
    {
        $msg = $msg.Substring(0, $msg.Length-1)
        #Write-Debug $msg.Length
        #Write-Debug $msg
    }
    $response.Value = $msg

	return $true;
}


$Certificate = $null

# home 
#$ComputerName = "192.168.1.7"

# office
$ComputerName = "10.0.19.118"

# chromecast ultra
#$ComputerName = "10.0.19.76"

# my test server in the office
#$ComputerName = "10.0.19.219"

# my test server at home
#$ComputerName = "192.168.1.4"

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

$len = 0

# connect
Write-Debug "connecting..."

$data = '{"type":"CONNECT","origin":{}}'
$chrome_namespace = "urn:x-cast:com.google.cast.tp.connection";
$msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()

# get status
$data = '{"type":"GET_STATUS","requestId":46479000}'
$chrome_namespace = "urn:x-cast:com.google.cast.receiver"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()


$buffer = new-object byte[] 2048
$sessionId = $null
while ($sessionId -eq $null)
{
    if($SslStream.CanRead -eq $true)
    {   
        #$num = $reader.Read($buffer, 0, 2048);
        $num = $SslStream.Read($buffer, 0, 2048);
		if ($num -ne 0)
        {
            $response = ''
            $ret = ReadMessage $buffer $num ([ref]$response)
		    Write-Debug "response: $response"

            $obj = ConvertFrom-Json -InputObject $($response)
            if ($obj.status -ne $null)
            {
                if($obj.status.applications[0] -ne $null)
                {
                    $sessionId = $obj.status.applications[0].sessionId
                 }
            }
        }
    }
}

Write-Debug "session = $sessionId"

# PONG
$data = '{"type":"PING"}'
$chrome_namespace = "urn:x-cast:com.google.cast.tp.heartbeat"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()

# launch
$data = '{"type":"LAUNCH","requestId":46479001,"appId":"CC1AD845"}'

# CACD78FE is my receiver
$data = '{"type":"LAUNCH","requestId":46479001,"appId":"CACD78FE"}'
$chrome_namespace = "urn:x-cast:com.google.cast.receiver"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()

$transportId = $null 
while ($transportId -eq $null)
{
    if($SslStream.CanRead -eq $true)
    {   
        $num = $SslStream.Read($buffer, 0, 2048);
		if ($num -ne 0)
        {
            $response = ''
            $ret = ReadMessage $buffer $num ([ref]$response)
		    Write-Debug "response: $response"

            $obj = ConvertFrom-Json -InputObject $($response)
		    if ($obj.status -ne $null)
		    {
			    if ($obj.status.applications -ne $null)
                {
                    if ($obj.status.applications[0].transportId -ne $null)
                    {
                        $transportId = $obj.status.applications[0].transportId
                    }
                }
            }
        }
    }
}

Write-Debug "transportId = $transportId"

# PING AGAIN
$data = '{"type":"PING"}'
$chrome_namespace = "urn:x-cast:com.google.cast.tp.heartbeat"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()


# connect to new destination
$data = '{"type":"CONNECT","origin":{}}'
$chrome_namespace = "urn:x-cast:com.google.cast.tp.connection"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) $transportId

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()


# load google media source
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4","streamType":"buffered","contentType":"video/mp4"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"Big Buck Bunny","thumb":"images/BigBuckBunny.jpg"}}}'
# home
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.4/sourcempeg2_422_pro_ntsc.mp4","streamType":"buffered","contentType":"video/mp4"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"Big Buck Bunny","thumb":"images/BigBuckBunny.jpg"}}}'
# office
$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://10.0.19.112/sourcempeg2_422_pro_ntsc.mp4","streamType":"buffered","contentType":"video/mp4"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"Big Buck Bunny","thumb":"images/BigBuckBunny.jpg"}}}'
$chrome_namespace = "urn:x-cast:com.google.cast.media"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) $transportId

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()

while ($true)
{
    if($SslStream.CanRead -eq $true)
    {   
        $num = $SslStream.Read($buffer, 0, 2048);
		if ($num -ne 0)
        {
            $response = ''
            $ret = ReadMessage $buffer $num ([ref]$response)
		    Write-Debug "response: $response"

	        # PING AGAIN
	        $data = '{"type":"PING"}'

	        $chrome_namespace = "urn:x-cast:com.google.cast.tp.heartbeat"
            $msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

            Write-Debug "len = $len"
            $SslStream.Write($msg, 0, $len)
            $SslStream.Flush()
        }
    }
}

$SslStream.Close()
$TcpClient.Close()
