function Invoke-CdpCommand {
    <#
        .SYNOPSIS
        Invokes the provided cdp command with parameters on the CdpPage.
        All commands can be found here:
        https://chromedevtools.github.io/devtools-protocol/tot/
        .PARAMETER MethodName
        The name of the cdp method ex 'Page.navigate'
        .PARAMETER Parameters
        A hashtable of the parameters.
        Excluding id, method, and sessionId
        @{
            url = 'about:blank'
        }
        .EXAMPLE
        $Response = Invoke-CdpCommand -CdpPage $CdpPage -Method 'Page.navigate' -Parameters @{url = 'about:blank' }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$MethodName,
        [object]$Parameters
    )

    process {
        $CdpServer = $CdpPage.CdpServer

        $Command = @{
            method = $MethodName
            sessionId = $CdpPage.TargetInfo['SessionId']
        }

        if ($Parameters) {
            $Command.params = $Parameters
        }

        $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
    }
}
