class CdpFrame {
    [string]$FrameId
    [string]$ParentFrameId
    [string]$SessionId

    hidden [System.Threading.ManualResetEventSlim]$RuntimeReady = [System.Threading.ManualResetEventSlim]::new($false)

    CdpFrame ($FrameId, $SessionId) {
        $this.LoadingState['NetworkIdle'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FrameStoppedLoading'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['Load'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FirstPaint'] = [System.Threading.ManualResetEventSlim]::new($false)

        $this.FrameId = $FrameId
        $this.ParentFrameId = $null
        $this.SessionId = $SessionId
        $this.PageInfo['RuntimeUniqueId'] = $null
    }

    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$PageInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]$LoadingState = [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]::new()

    [void]ResetLoadingState() {
        $this.LoadingState['NetworkIdle'].Reset()
        $this.LoadingState['FrameStoppedLoading'].Reset()
        $this.LoadingState['Load'].Reset()
        $this.LoadingState['FirstPaint'].Reset()
    }

    [void]Dispose() {
        $this.RuntimeReady.Set()
        $this.RuntimeReady.Dispose()
        foreach ($LoadingState in $this.LoadingState.GetEnumerator()) {
            $LoadingState.Value.Set()
            $LoadingState.Value.Dispose()
        }
    }
}
