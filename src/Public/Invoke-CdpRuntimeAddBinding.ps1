function Invoke-CdpRuntimeAddBinding {
    <#
        .SYNOPSIS
        Adds a binding object to the browser
        .PARAMETER Name
        Name of the object to use in javascript - window.Name(json);
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Name
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Runtime.addBinding $SessionId $Name
        $CdpServer.SendCommand($Command)

        $_
    }
}
