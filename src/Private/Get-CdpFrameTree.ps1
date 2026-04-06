function Get-CdpFrameTree {
    param($Tree)
    if ($Tree.frame) { $Tree.frame }
    if ($Tree.childFrames) {
        foreach ($Child in $Tree.childFrames) {
            Get-CdpFrameTree $Child
        }
    }
}
