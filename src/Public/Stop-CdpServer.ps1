function Stop-CdpServer {
    <#
        .SYNOPSIS
        Disposes the Server Pipes, Threads, ChromeProcess, and RunspacePool
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [CdpPage]$CdpPage,
        [Parameter(ValueFromPipeline, Position = 0)]
        [CdpServer]$CdpServer
    )

    process {
        if ($CdpPage) { $CdpServer = $CdpPage.CdpServer }
        $CdpServer.Stop()
    }
}
