function Invoke-CdpInputSendKeys {
    <#
        .SYNOPSIS
        Sends keys to a session
        .PARAMETER Keys
        String to send.
        Include "$([char]13)" to press enter at any given point in the string.
        .EXAMPLE
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys "Hello World$([char]13)"
        .PARAMETER BringToFront
        Attemps to brings page to front once before sending keys.
        .PARAMETER Delay
        Time in ms between sending each key command.
        .PARAMETER ExpectNavigation
        Resets loading state of main page inorder to wait for the next page on click.
        .PARAMETER Timeout
        Max time in ms to wait for expected navigation before throwing an error.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Keys,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0,
        [Parameter(ParameterSetName = 'Navigation')]
        [switch]$ExpectNavigation,
        [Parameter(ParameterSetName = 'Navigation')]
        [int]$Timeout = 60000
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Input.DispatchKeyEvent $SessionId $null

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpPage.ResetLoadingState()
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

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpServer.WaitForPageLoad($CdpPage, $Timeout)
        }

        $_
    }
}
