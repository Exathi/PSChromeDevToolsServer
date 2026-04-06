function New-CdpPage {
    <#
		.SYNOPSIS
		Creates a new tab target and enables Page events, PageLifeCycle events, and Runtime.
        .PARAMETER NewWindow
        Creates a new browser context and tab.
	#>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [Parameter(ParameterSetName = 'ByPage')]
        [CdpPage]$CdpPage,
        [Parameter(ValueFromPipeline, Position = 0)]
        [Parameter(ParameterSetName = 'ByServer')]
        [CdpServer]$CdpServer,
        [string]$Url = 'about:blank',
        [switch]$NewWindow
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByPage') { $CdpServer = $CdpPage.CdpServer }

        if ($NewWindow) {
            $Command = Get-Target.createBrowserContext
            $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        }

        $Command = Get-Target.createTarget $Url
        if ($NewWindow) {
            $Command.params.newWindow = $true
            $Command.params.browserContextId = $Response.result.browserContextId
        } else {
            $Command.params.browserContextId = $CdpPage.BrowserContextId
        }

        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        $CdpPage = $CdpServer.GetPageByTargetId($Response.result.targetId)

        $CdpServer.SetupNewPage($CdpPage)

        $CdpPage
    }
}
