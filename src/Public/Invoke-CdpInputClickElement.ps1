function Invoke-CdpInputClickElement {
    <#
		.SYNOPSIS
		Finds and clicks with element in the center of the box. Clicks from the top left of the element when $TopLeft is switched on.
		.PARAMETER FilterScript
		The scriptblock that will filter find valid nodes.
        Valid properties are:

        NodeId
        NodeType
        ParentId
        BackendNodeId
        NodeValue*
        NodeName*
        LocalName
        Attributes*
        FrameId
        AttributesString
        DocumentURL

        *The most common selectors
        NodeValue = any text on the page
        NodeName = element tag name
        Attributes = attributes for the tag such as:
            Name = id, Value = theId
            Name = autofocus

        .EXAMPLE
        $FilterScript = {
            $_.NodeName -eq '#text' -and
            $_.NodeValue -eq 'Woo woo'
        }

        $FilterScript = {
            $_.NodeName -eq 'a'
        }
        $Index = 5

        $FilterScript = {
            $_.NodeName -eq 'button'
        }
        $Index = 0

        $FilterScript = {
            $_.NodeValue -eq 'submit'
        }

		.PARAMETER Index
		The nth number of the Nodes found by FilterScript
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
        [scriptblock]$FilterScript,
        [int]$Index = 0,
        [int]$Click = 0,
        [int]$OffsetX = 0,
        [int]$OffsetY = 0,
        [switch]$TopLeft,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $CdpPage.PageInfo['Node'] = Test-CdpSelector -CdpPage $CdpPage -FilterScript $FilterScript -Index $Index -EnableDomEvents
        if ($CdpPage.PageInfo['Node'].nodeType -ne 1 -and $CdpPage.PageInfo['Node'].nodeType -ne 3) { throw ('Node is not an element or text. {0}' -f $CdpPage.PageInfo['Node'].nodeType) }

        if ($Click -le 0) { return $_ }

        $Command = Get-DOM.getBoxModel $SessionId
        $Command.params = @{
            nodeId = $CdpPage.PageInfo['Node'].nodeId
        }
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        if ($Response.error) { throw 'Could not get box model. {0}' -f "$($Response.error)" }

        # Disable dom events now that we don't need nodes anymore.
        $Command = Get-DOM.disable $CdpPage.TargetInfo.SessionId
        $CdpServer.SendCommand($Command)

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

        $CommandIds = @(
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            $Command.params.type = 'mouseReleased'
            Start-Sleep -Milliseconds $Delay # if we send click too fast it can fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        )

        foreach ($Id in $CommandIds) {
            $History = $CdpServer.SharedState.CommandHistory[$Id]
            $History.CommandReady.Wait()
            $History.CommandReady.Dispose()
            $History.CommandReady = $null
        }

        $_
    }
}
