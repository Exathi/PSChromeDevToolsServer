function Invoke-CdpInputSendKeys {
    <#
		.SYNOPSIS
		Sends keys to a session
		.PARAMETER Keys
		String to send
		.EXAMPLE
		Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'Hello World'
		.PARAMETER BringToFront
		Attemps to brings page to front once before sending keys.
		.PARAMETER Delay
		Time in ms between sending each key command.
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Keys,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Input.DispatchKeyEvent $SessionId $null

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        $CommandIdWaiter = $Keys.ToCharArray().ForEach({
                $Command.params.text = $_
                Start-Sleep -Milliseconds $Delay # if we send keys too fast it will fail to register.
                $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            }
        )

        $KeyCount = $Keys.ToCharArray().Count
        [System.Threading.SpinWait]::SpinUntil({
                $CommandResponse = $CommandIdWaiter.Where({ $CdpServer.SharedState.MessageHistory.ContainsKey([version]::new($_, 0)) })
                $CommandResponse.Count -eq $KeyCount
            }
        )

        $_
    }
}
