function Send-CdpDomUploadFile {
    <#
        .SYNOPSIS
        Bypasses file upload dialog by providing the file path to upload in the found input element by FilterScript.
        .PARAMETER Files
        Fullname of files to upload
        .PARAMETER FilterScript
        The scriptblock that will filter find valid nodes.
        See Test-CdpSelector
        .PARAMETER Selector
        QuerySelectorAll syntax to find the element.
        See Test-CdpSelector
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [string[]]$Files,
        [Parameter(Mandatory, ParameterSetName = 'Scriptblock')]
        [scriptblock]$FilterScript,
        [Parameter(Mandatory, ParameterSetName = 'QuerySelectorAll')]
        [string]$Selector,
        [int]$Index = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer

        $Node = if ($FilterScript) {
            Test-CdpSelector -CdpPage $CdpPage -FilterScript $FilterScript -Index $Index -EnableDomEvents
        } else {
            Test-CdpSelector -CdpPage $CdpPage -Selector $Selector -Index $Index -EnableDomEvents
        }

        $Command = Get-Dom.setFileInputFiles $CdpPage.TargetInfo['SessionId'] $Files $Node.BackendNodeId
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        if ($Response.error) { throw ('Could not upload file: {0}' -f $Response.error) }
        $_
    }
}
