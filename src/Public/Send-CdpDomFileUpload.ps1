function Send-CdpDomUploadFile {
    <#
        .SYNOPSIS
        Bypasses file upload dialog by providing the file path to upload in the found input element by FilterScript.
        .PARAMETER Files
        Fullname of files to upload
        .PARAMETER FilterScript
        The scriptblock that will filter find valid nodes. See Test-CdpSelector.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [string[]]$Files,
        [scriptblock]$FilterScript
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript $FilterScript
        $Command = Get-Dom.setFileInputFiles $CdpPage.TargetInfo['SessionId'] $Files $Node.BackendNodeId
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        if ($Response.error) { throw ('Could not upload file: {0}' -f $Response.error) }
        $_
    }
}
