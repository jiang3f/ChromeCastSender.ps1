<#

    Copyright (C) 2017 Patrick Jiang (jiang3f@gmail.com)

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
#>

###############################################
# Send control message to ChromeCast
###############################################


#
# Set Variables
#

param (
    [URI]$content ='file:///d:\examples\sourcempeg2_422_pro_ntsc.mp4',
    [URI]$wwwRoot ='file:///c:\test',
    [string]$httpServerAddr = '192.168.1.10',
    [string]$httpServerPort = '8787'
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

# copy media files
#
$outputLocalPath = $wwwRoot.LocalPath
$extName = [System.IO.Path]::GetExtension($content.LocalPath)
$shortName = [System.IO.Path]::GetFileName($content.LocalPath)
if((($extName -eq '.mpd') -or ($extName -eq '.ismc') -or ($extName -eq 'm3u8')) -eq $true)
{
    $sourcePath = Split-Path -Path $($content.LocalPath) 
    $sourcePath += '\*'
    Copy-Item $sourcePath $outputLocalPath -recurse
}
elseif (($extName -eq '.mp4') -eq $true)
{
    Copy-Item $content.LocalPath $outputLocalPath 
}
else
{
    Write-Debug "Unsupported format"
    return
}

# chromecast's IP address
#$ComputerName = "10.0.19.118"
$ComputerName = "192.168.1.12"

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

# launch default player
#$data = '{"type":"LAUNCH","requestId":46479001,"appId":"CC1AD845"}'

# CACD78FE is my customer receiver
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


$codec = ''
if($extName -eq '.mp4')
{
    $codec = "video/mp4"
}
elseif($exName -eq '.mpd')
{
    $codec = "application/dash+xml"
}
elseif($exName -eq '.m3u8')
{
    $codec = "application/x-mpegurl"
}
elseif($extName -eq '.ismc')
{
    $codec = "application/vnd.ms-sstr+xml"
}


<# Play the mp4 file located on the local HTTP server
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://10.0.19.112/sourcempeg2_422_pro_ntsc.mp4","streamType":"buffered","contentType":$codec},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'
#local mp4 file (works)
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10/sourcempeg2_422_pro_ntsc.mp4","streamType":"buffered","contentType":"video/mp4"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local mp4 file, Python HTTP server (works)
$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/sourcempeg2_422_pro_ntsc.mp4","streamType":"buffered","contentType":"video/mp4"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

# local smoothstreaming file
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.4/SmoothStreaming/test1/10s_MPEG2-PS_1920x1080.ism","streamType":"buffered","contentType":"application/vnd.ms-sstr+xml"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local hls mp4 (failed)
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/Dash.js/TEST35_CMAF_VTT_VANTAGE/ezr.m3u8","streamType":"buffered","contentType":"application/x-mpegurl"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local hls mpeg2 ts (works)
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/Dash.js/test41_hls_ts/sourcempeg2_422_pro_ntsc.m3u8","streamType":"buffered","contentType":"application/x-mpegurl"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local DASH MP4 on demand (failed)
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/Dash.js/test32_dash_OnDemand/sourcempeg2_422_pro_ntsc.mpd","streamType":"buffered","contentType":"application/dash+xml"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local CMAF -- DASH manifest (WORKS)
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/Dash.js/TEST35_CMAF_VTT_VANTAGE/ezr.mpd","streamType":"buffered","contentType":"application/dash+xml"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'

#local HSS (failed) 
#$data = '{"type":"LOAD","requestId":46479002,"sessionId":" + $sessionId + ","media":{"contentId":"http://192.168.1.10:8787/Dash.js/TEST42_HSS/sourcempeg2_422_pro_ntsc.ismc","streamType":"buffered","contentType":"application/vnd.ms-sstr+xml"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"sourcempeg2_422_pro_ntsc","thumb":"images/BigBuckBunny.jpg"}}}'
#>

$data = '{"type":"LOAD","requestId":46479002,"sessionId":"' + $sessionId + '","media":{"contentId":"http://' + $httpServerAddr + ':' + $httpServerPort + '/' + $shortName + '","streamType":"buffered","contentType":"' + $codec + '"},"autoplay":true,"currentTime":0,"customData":{"payload":{"title:":"test_file","thumb":"images/BigBuckBunny.jpg"}}}'

$chrome_namespace = "urn:x-cast:com.google.cast.media"
$msg = CreateRequest $data $chrome_namespace ([ref]$len) $transportId

Write-Debug "len = $len"
$SslStream.Write($msg, 0, $len)
$SslStream.Flush()

$exitflag = $false;

while ($exitflag -ne $true)
{
    if($SslStream.CanRead -eq $true)
    {   
        $num = $SslStream.Read($buffer, 0, 2048);
		if ($num -ne 0)
        {
            $response = ''
            $ret = ReadMessage $buffer $num ([ref]$response)
		    #Write-Debug "response: $response"

            $obj = ConvertFrom-Json -InputObject $($response)
		    if ($obj.status -ne $null)
		    {
                if($obj.status[0].idleReason -ne $null)
                {
                    if($obj.status[0].idleReason -eq 'FINISHED')
                    {
                        Write-Debug "Finished!"                    
                    }
                    $exitflag = $true
                }
            }

	        # PING AGAIN
	        $data = '{"type":"PING"}'

	        $chrome_namespace = "urn:x-cast:com.google.cast.tp.heartbeat"
            $msg = CreateRequest $data $chrome_namespace ([ref]$len) ''

            #Write-Debug "len = $len"
            $SslStream.Write($msg, 0, $len)
            $SslStream.Flush()
        }
    }
}

$SslStream.Close()
$TcpClient.Close()
