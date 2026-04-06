function Invoke-CdpInputClickElement {
    <#
		.SYNOPSIS
		Finds and clicks with element in the center of the box. Clicks from the top left of the element when $TopLeft is switched on.
		.PARAMETER Selector
		Javascript that returns ONE node object
		For example:
		document.querySelectorAll('[name=q]')[0]
		.PARAMETER Click
		Number of times to left click the mouse
		.PARAMETER OffsetX
		Number of pixels to offset from the center of the element on the X axis
		.PARAMETER OffsetY
		Number of pixels to offset from the center of the element on the Y axis
		.PARAMETER TopLeft
		Clicks from the top left of the element instead of center. Offset x and y will be relative to this position instead.
		.PARAMETER BringToFront
		Attemps to brings page to front once before sending click.
		.PARAMETER Delay
		Time in ms between each mouse down and mouse up command.
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Selector,
        [Parameter(ParameterSetName = 'Click')]
        [int]$Click = 0,
        [Parameter(ParameterSetName = 'Click')]
        [int]$OffsetX = 0,
        [Parameter(ParameterSetName = 'Click')]
        [int]$OffsetY = 0,
        [Parameter(ParameterSetName = 'Click')]
        [switch]$TopLeft,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $Command = Get-Runtime.evaluate $SessionId $Selector
        $Command.params.uniqueContextId = "$($CdpPage.PageInfo['RuntimeUniqueId'])"
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpPage.PageInfo['ObjectId'] = $Response.result.result.objectId

        if ($Click -le 0) { return $_ }

        $Command = Get-DOM.describeNode $SessionId $CdpPage.PageInfo.ObjectId
        $Command.params.objectId = $CdpPage.PageInfo['ObjectId']
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        if ($Response.error) {
            throw ('Error describing node: {0}' -f $Response.error.message)
        }

        $CdpPage.PageInfo['Node'] = $Response.result.node
        if ($Response.result.node.nodeType -ne 1) { throw ('Node is not an element. {0}' -f $Response.result.node) }

        $Command = Get-DOM.getBoxModel $SessionId $CdpPage.PageInfo['ObjectId']
        $Command.params.objectId = $CdpPage.PageInfo['ObjectId']
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        $CdpPage.PageInfo['BoxModel'] = $Response.result.model

        if ($TopLeft) {
            $PixelX = $CdpPage.PageInfo['BoxModel'].content[0] + $OffsetX
            $PixelY = $CdpPage.PageInfo['BoxModel'].content[1] + $OffsetY
        } else {
            $PixelX = $CdpPage.PageInfo['BoxModel'].content[0] + ($CdpPage.PageInfo['BoxModel'].width / 2) + $OffsetX
            $PixelY = $CdpPage.PageInfo['BoxModel'].content[1] + ($CdpPage.PageInfo['BoxModel'].height / 2) + $OffsetY
        }

        $Command = Get-Input.dispatchMouseEvent $SessionId 'mousePressed' $PixelX $PixelY 'left'
        $Command.params.clickCount = $Click

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        $CommandIdWaiter = @(
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            $Command.params.type = 'mouseReleased'
            Start-Sleep -Milliseconds $Delay # if we send click too fast it will fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        )

        [System.Threading.SpinWait]::SpinUntil({
                $CommandResponse = $CommandIdWaiter.Where({ $CdpServer.SharedState.MessageHistory.ContainsKey([version]::new($_, 0)) })
                $CommandResponse.Count -eq 2
            }
        )

        $_
    }
}
