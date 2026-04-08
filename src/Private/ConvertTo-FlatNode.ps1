function ConvertTo-FlatNode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Node,
        [string]$TopParent = $null
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
            # ContentFrame = $null
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
            ConvertTo-FlatNode -Node $Child.Children -TopParent $IsHead
        }

        if ($Child.contentDocument) {
            # $FlatNode.contentFrame = ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null
            ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null
        }

        $FlatNode
    }
}
