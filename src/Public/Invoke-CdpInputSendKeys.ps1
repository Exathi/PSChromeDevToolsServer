function Invoke-CdpInputSendKeys {
    <#
        .SYNOPSIS
        Sends keys to a session.
        If this induces navigation, use Test-CdpSelector to wait for the new url then follow with Wait-CdpLifecycleEvent.
        .PARAMETER Keys
        String to send.
        Include "$([char]13)" to press enter at any given point in the string.
        .EXAMPLE
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys "Hello World$([char]13)"
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
        [int]$Delay = 1
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Input.DispatchKeyEvent $SessionId $null

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        $CommandIds = foreach ($Char in $Keys[0..($Keys.Length - 1)]) {
            $Command.params.text = $Char
            Start-Sleep -Milliseconds $Delay # if we send keys too fast it can fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        }

        foreach ($Id in $CommandIds) {
            $History = $CdpServer.SharedState.CommandHistory[$Id]
            $History.CommandReady.Wait()
            $History.CommandReady.Dispose()
            $History.CommandReady = $null
        }

        if ($_) { $_ }
    }
}
