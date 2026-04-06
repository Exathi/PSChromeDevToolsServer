class CdpFrame {
    [string]$FrameId
    [string]$ParentFrameId
    [string]$SessionId

    CdpFrame ($FrameId, $SessionId) {
        $this.ResetLoadingState()
        $this.FrameId = $FrameId
        $this.ParentFrameId = $null
        $this.SessionId = $SessionId
        $this.PageInfo['RuntimeUniqueId'] = $null
    }

    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$PageInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]$LoadingState = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()

    [void]ResetLoadingState() {
        $this.LoadingState['NetworkIdle'] = $false
        $this.LoadingState['FrameStoppedLoading'] = $false
        $this.LoadingState['Load'] = $false
        $this.LoadingState['FirstPaint'] = $false
    }
}
