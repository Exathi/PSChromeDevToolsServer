function Test-CdpSelector {
    <#
        .SYNOPSIS
        Returns nodes for exploring if selectors are found.
        Will poll until found or $Timeout is reached.
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
        Keeps DOM events active. Mainly for internal use.

        .PARAMETER Selector
        QuerySelectorAll syntax to find the element.
        '#id'
        '.class'
        '[id=id]'
        'div > div'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$CdpPage,
        [Parameter(Mandatory, ParameterSetName = 'Scriptblock')]
        [scriptblock]$FilterScript,
        [int]$Index = 0,
        [switch]$All,
        [switch]$EnableDomEvents,
        [int]$Timeout = 5000,
        [Parameter(Mandatory, ParameterSetName = 'QuerySelectorAll')]
        [string]$Selector
    )

    begin {
        $PollInterval = 100
        $Sequence = 0
    }

    process {
        $CdpServer = $CdpPage.CdpServer
        $DocumentCommand = Get-DOM.getDocument $CdpPage.TargetInfo['SessionId']

        $EndTime = (Get-Date).AddMilliseconds($Timeout)

        while ($true) {
            $Sequence++

            $Response = $CdpServer.SendCommand($DocumentCommand, [WaitForResponse]::Message)

            if ($PSCmdlet.ParameterSetName.Contains('Scriptblock')) {
                $Root = $Response.result.root
                $Document = ConvertTo-FlatNode -Node $Root
                $Nodes = $Document | Where-Object { $_.TopParentName -ne 'HEAD' } | Where-Object -FilterScript $FilterScript
            } else {
                $Command = @{
                    method = 'DOM.querySelectorAll'
                    sessionId = $CdpPage.TargetInfo['SessionId']
                    params = @{
                        nodeId = $Response.result.root.nodeId
                        selector = $Selector
                    }
                }
                $QuerySelectorResponse = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
                if ($QuerySelectorResponse.error) { throw ('Invalid selector: {0}' -f $QuerySelectorResponse.error) }

                $Nodes = foreach ($NodeId in $QuerySelectorResponse.result.nodeIds) {
                    $Command = Get-DOM.describeNode $CdpPage.TargetInfo['SessionId']
                    $Command.params.nodeId = $NodeId
                    $DescribeResponse = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
                    ConvertTo-FlatNode -Node $DescribeResponse.result.node
                }
            }

            if ($Nodes) {
                break
            } elseif (($EndTime - (Get-Date)).TotalMilliseconds -lt 0) {
                $SelectorValue = if ($FilterScript) { $FilterScript } else { $Selector }
                throw ('No node found in allotted time with: {0}' -f $SelectorValue)
            } else {
                Start-Sleep -Milliseconds ([math]::Min(($PollInterval * $Sequence), 1000))
            }
        }

        if (!$EnableDomEvents) {
            $Command = Get-DOM.disable $CdpPage.TargetInfo['SessionId']
            $CdpServer.SendCommand($Command)
        }

        if ($Nodes -and $All) { $Nodes }
        else { $Nodes[$Index] }
    }
}
