function Invoke-CdpPageNavigate {
    <#
		.SYNOPSIS
		Navigates and automatically waits for the page to load with Page.lifecycleEvent.load and FrameStoppedLoading
		Also waits for frames to load if they are present
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $OldRuntimeUniqueId = $CdpPage.PageInfo['RuntimeUniqueId']

        $CdpPage.ResetLoadingState()
        $CdpPage.Frames.Values.ForEach({ $_.ResetLoadingState() })

        $Command = Get-Page.navigate $SessionId $Url
        $null = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $NewRuntimeUniqueId = $null
        if ($null -ne $OldRuntimeUniqueId) {
            [System.Threading.SpinWait]::SpinUntil({
                    $null = $CdpPage.PageInfo.TryGetValue('RuntimeUniqueId', [ref]$NewRuntimeUniqueId)
                    $NewRuntimeUniqueId -ne $OldRuntimeUniqueId
                }
            )
        }

        $CdpServer.WaitForPageLoad($CdpPage)

        $_
    }
}
