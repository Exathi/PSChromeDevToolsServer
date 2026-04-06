function Get-CdpFrame {
    <#
		.SYNOPSIS
		Gets a frame from the Frametree if it exists.
		.PARAMETER Url
		The regex pattern of a url to look for
		.PARAMETER Timeout
		Max time to wait(ms) before giving up.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$Timeout = 5000
    )

    process {
        $Start = Get-Date
        do {
            $Command = Get-Page.getFrameTree $CdpPage.TargetInfo.SessionId
            $Response = $CdpPage.CdpServer.SendCommand($Command, 1)
            $FramesTree = Get-CdpFrameTree $Response.result.frameTree
            $Match = $FramesTree.url | Select-String -Pattern $Url
            $MatchedFrame = $FramesTree | Where-Object { $_.url -eq $Match.Line }
            $CdpFrame = $CdpPage.Frames.Values | Where-Object { $_.FrameId -eq $MatchedFrame.id }
            if ($CdpFrame) { break }
            Start-Sleep 0
        } while (($Start.AddMilliseconds($Timeout) - (Get-Date)).Milliseconds -gt 0)

        if (!$CdpFrame) { throw ('No frame found using: {0}' -f $Url) }

        [pscustomobject]@{
            CdpPage = $CdpPage
            CdpFrame = $CdpFrame
        }
    }
}
