function Wait-CdpPageLifecycleEvent {
    <#
		.SYNOPSIS
		Waits for provided LifecycleEvents.
		.PARAMETER InputObject
		The CdpPage or [pscustomobject]@{CdpPage; CdpFrame} from Get-CdpFrame.
		.PARAMETER Events
		The LifecycleEvent to wait for.
		.PARAMETER Timeout
		Max time to wait(ms) before giving up.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [ValidateSet('NetworkIdle', 'FirstPaint')]
        [string[]]$Events = @('NetworkIdle'),
        [int]$Timeout = 1000
    )

    process {
        if ($InputObject.CdpPage) {
            $CdpPage = $InputObject.CdpPage
            $Target = $InputObject.CdpFrame
        } else {
            $CdpPage = $InputObject
            $Target = $InputObject
        }

        $null = [System.Threading.SpinWait]::SpinUntil({
                $States = $Events | ForEach-Object { $Target.LoadingState[$_] }
                $States -notcontains $false
            }, $Timeout)

        if ($_) { $CdpPage }
    }
}
