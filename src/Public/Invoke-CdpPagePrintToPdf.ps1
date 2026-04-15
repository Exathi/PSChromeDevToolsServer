function Invoke-CdpPagePrintToPdf {
    <#
        .SYNOPSIS
        Prints page to pdf.
        https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF
        .PARAMETER FilePath
        The fullname of the pdf.
        .PARAMETER PageRanges
        Paper ranges to print, one based, e.g., '1-5, 8, 11-13'.
        Pages are printed in the document order, not in the order specified, and no more than once.
        Defaults to empty string, which implies the entire document is printed.
        The page numbers are quietly capped to actual page count of the document, and ranges beyond the end of the document are ignored.
        If this results in no pages to print, an error is reported.
        It is an error to specify a range with start greater than end.
        .PARAMETER HeaderTemplate
        HTML template for the print header. Should be valid HTML markup with following classes used to inject printing values into them:

        date: formatted print date
        title: document title
        url: document location
        pageNumber: current page number
        totalPages: total pages in the document

        For example, <span class=title></span> would generate span containing the title.
        .PARAMETER FooterTemplate
        See HeaderTemplate.
    #>
    [CmdletBinding(DefaultParameterSetName = 'CommonSize')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [string]$FilePath,
        [bool]$Landscape,
        [bool]$DisplayHeaderFooter,
        [bool]$PrintBackground = $true,
        [ValidateRange(0.1, 2)]
        [decimal]$Scale = 1,
        [Parameter(ParameterSetName = 'CommonSize')]
        [ValidateSet('A0', 'A1', 'A2', 'A3', 'A4', 'A5', 'Letter', 'Legal')]
        [string]$PaperSize = 'Letter',
        [Parameter(ParameterSetName = 'UserSize')]
        [decimal]$PaperWidth,
        [Parameter(ParameterSetName = 'UserSize')]
        [decimal]$PaperHeight,
        [decimal]$MarginTop,
        [decimal]$MarginBottom,
        [decimal]$MarginLeft,
        [decimal]$MarginRight,
        [string[]]$PageRanges,
        [string]$HeaderTemplate,
        [string]$FooterTemplate
    )

    begin {
        $Width, $Height = switch ($PaperSize) {
            'A0' { 33.1; 46.8 }
            'A1' { 23.4; 33.1 }
            'A2' { 16.5; 23.4 }
            'A3' { 11.7; 16.5 }
            'A4' { 8.3; 11.7 }
            'A5' { 5.8; 8.3 }
            'Letter' { 8.5; 11 }
            'Legal' { 8.5; 14 }
        }
    }

    process {
        $CdpServer = $CdpPage.CdpServer
        $Command = @{
            method = 'Page.printToPDF'
            sessionId = $CdpPage.TargetInfo['SessionId']
        }

        $Command.params = @{
            landscape = $Landscape
            displayHeaderFooter = $DisplayHeaderFooter
            printBackground = $PrintBackground
            scale = $Scale
            paperWidth = if ($Width) { $Width } else { $PaperWidth }
            paperHeight = if ($Height) { $Height } else { $PaperHeight }
            marginTop = $MarginTop
            marginBottom = $MarginBottom
            marginLeft = $MarginLeft
            marginRight = $MarginRight
            pageRanges = if ($PageRanges) { @($PageRanges) } else { '' }
            headerTemplate = $HeaderTemplate
            footerTemplate = $FooterTemplate
        }

        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        if ($Response.error) { throw ('Did not print. {0}' -f $Response.error) }
        [System.IO.File]::WriteAllBytes($FilePath, [System.Convert]::FromBase64String($Response.result.data))
        $CdpServer.SharedState.CommandHistory[$Response.id].Response.result.data = $null # remove base64 string after writing since it is large.

        if ($_) { $_ }
    }
}
