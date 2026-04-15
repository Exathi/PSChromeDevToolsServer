function Invoke-CdpPageNavigate {
    <#
        .SYNOPSIS
        Navigates and automatically waits for the page to load with Page.lifecycleEvent.load and FrameStoppedLoading
        Also waits for frames to load if they are present
        .PARAMETER Timeout
        Max amount of time to wait for page to load before throwing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$Timeout = 60000
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $CdpPage.ResetLoadingState()
        $CdpPage.RuntimeReady.Reset()
        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            $CdpFrame.Value.Dispose()
        }
        $CdpPage.Frames.Clear()

        $Command = Get-Page.navigate $SessionId $Url
        $null = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpServer.WaitForPageLoad($CdpPage, $Timeout)

        if ($_) { $_ }
    }
}
