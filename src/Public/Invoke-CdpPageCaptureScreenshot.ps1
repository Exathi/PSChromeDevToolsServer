function Invoke-CdpPageCaptureScreenshot {
    <#
        .SYNOPSIS
        Creates a screenshot of the current page. The browser will be brought to front for the screenshot.
        .PARAMETER FilePath
        The fullname of the screenshot file.
        .PARAMETER Format
        Supports 'jpeg', 'png', or 'webp'
        .PARAMETER X
        Pixel X axis to start from.
        .PARAMETER Y
        Pixel Y axis to start from.
        .PARAMETER Width
        Width from Pixel X.
        .PARAMETER Height
        Height from Pixel Y.
        .PARAMETER Scale
        Scale of the screenshot.
        .PARAMETER BringToFront
        If the browser is minimized, the command will hang until it is not minimized. This switch will automatically bring the browser to front to avoid hanging.
    #>
    [CmdletBinding(DefaultParameterSetName = 'CommonSize')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [string]$FilePath,
        [ValidateSet('jpeg', 'png', 'webp')]
        [string]$Format = 'png',
        [Parameter(ParameterSetName = 'Viewport')]
        [int]$X,
        [Parameter(ParameterSetName = 'Viewport')]
        [int]$Y,
        [Parameter(ParameterSetName = 'Viewport')]
        [int]$Width,
        [Parameter(ParameterSetName = 'Viewport')]
        [int]$Height,
        [Parameter(ParameterSetName = 'Viewport')]
        [ValidateRange(0.1, 2)]
        [decimal]$Scale = 1,
        [switch]$BringToFront
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $Command = @{
            method = 'Page.captureScreenshot'
            sessionId = $CdpPage.TargetInfo['SessionId']
        }

        if ($PSCmdlet.ParameterSetName.Contains('Viewport')) {
            $Command.params = @{
                format = $Format
                clip = @{
                    x = $X
                    y = $Y
                    width = $Width
                    height = $Height
                    scale = $Scale
                }
            }
        } else {
            $Command.params = @{format = $Format }
        }

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $CdpPage.TargetInfo['SessionId']
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        if ($Response.error) { throw ('Could not screenshot. {0}' -f $Response.error) }
        [System.IO.File]::WriteAllBytes($FilePath, [System.Convert]::FromBase64String($Response.result.data))
        $CdpServer.SharedState.CommandHistory[$Response.id].Response.result.data = $null # remove base64 string after writing since it is large.

        $_
    }
}
