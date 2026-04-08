function Test-CdpSelector {
    <#
        .SYNOPSIS
        Returns nodes for exploring if selectors are found.
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

        .PARAMETER All
        Returns all found nodes for viewing

        .PARAMETER EnableDomEvents
        Keeps DOM events active
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$CdpPage,
        [scriptblock]$FilterScript,
        [int]$Index = 0,
        [switch]$All,
        [switch]$EnableDomEvents
    )

    process {
        $Command = Get-DOM.getDocument $CdpPage.TargetInfo.SessionId
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        if (!$EnableDomEvents) {
            $Command = Get-DOM.disable $CdpPage.TargetInfo.SessionId
            $CdpServer.SendCommand($Command)
        }

        $Root = $Response.result.root
        $Document = ConvertTo-FlatNode -Node $Root

        $Nodes = $Document | Where-Object { $_.TopParentName -ne 'HEAD' } | Where-Object -FilterScript $FilterScript

        if ($Nodes -and $All) { $Nodes }
        elseif ($Nodes) { $Nodes[$Index] }
        else { throw ('no node found with FilterScript: {0}' -f $FilterScript) }
    }
}
