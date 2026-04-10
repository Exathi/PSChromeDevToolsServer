function ConvertTo-FlatNode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Node,
        [string]$TopParent = $null,
        [bool]$IsShadowRoot
    )

    foreach ($Child in $Node) {
        # Determine the ultimate parent for this child
        $IsHead = if ($Child.nodeName -eq 'HEAD') {
            $Child.nodeName
        } else {
            $TopParent
        }

        $FlatNode = [PSCustomObject]@{
            TopParentName = $IsHead
            IsShadowRoot = $IsShadowRoot
            NodeId = $Child.nodeId
            NodeType = $Child.nodeType
            ParentId = $Child.parentId
            BackendNodeId = $Child.backendNodeId
            NodeValue = $Child.nodeValue
            NodeName = $Child.nodeName
            LocalName = $Child.localName
            Attributes = $null
            FrameId = $Child.frameId
            AttributesString = $Child.attributes
            DocumentURL = $Child.documentURL
            # ShadowRoots = $Child.shadowRoots
            # ContentFrame = $Child.contentFrame
        }

        $FlatNode.Attributes = if ($Child.attributes) {
            for ($i = 0; $i -lt $Child.attributes.Count; $i += 2) {
                [pscustomobject]@{
                    Name = $Child.attributes[$i]
                    Value = $Child.attributes[$i + 1]
                }
            }
        }

        if ($Child.Children) {
            ConvertTo-FlatNode -Node $Child.Children -TopParent $IsHead -IsShadowRoot $IsShadowRoot
        }

        if ($Child.contentDocument) {
            # $FlatNode.contentFrame = ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null
            ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null -IsShadowRoot $IsShadowRoot
        }

        if ($Child.shadowRoots) {
            ConvertTo-FlatNode -Node $Child.shadowRoots -TopParent $null -IsShadowRoot $true
        }

        $FlatNode
    }
}
