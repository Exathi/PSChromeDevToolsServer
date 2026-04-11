function Wait-CdpPageLifecycleEvent {
    <#
        .SYNOPSIS
        Waits for provided LifecycleEvents.
        .PARAMETER InputObject
        The CdpPage or [pscustomobject]@{CdpPage; CdpFrame} from Get-CdpFrame.
        .PARAMETER Events
        The LifecycleEvent to wait for.
        FirstPaint does not always fire, such as on about:blank.
        There needs to be viewable text or renderable objects excluding frames, as frames have their own paintable content.
        .PARAMETER Timeout
        Max time to wait(ms) before giving up.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [ValidateSet('NetworkIdle', 'FirstPaint')]
        [string[]]$Events = @('NetworkIdle'),
        [int]$Timeout = 5000
    )

    process {
        if ($InputObject.CdpPage) {
            $CdpPage = $InputObject.CdpPage
            $Target = $InputObject.CdpFrame
        } else {
            $CdpPage = $InputObject
            $Target = $InputObject
        }

        $Events | ForEach-Object {
            if (!$Target.LoadingState[$_].Wait($Timeout)) {
                throw ('Event did not fire in {0}ms. Try setting a higher timeout or make sure the page has paintable content.' -f $Timeout)
            }
        }

        if ($_) { $CdpPage }
    }
}
