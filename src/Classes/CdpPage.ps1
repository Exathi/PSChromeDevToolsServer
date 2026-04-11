class CdpPage {
    # it's more dictionary now than property
    # did not want to use monitor.enter/exit
    [string]$TargetId
    [string]$Title
    [int]$ProcessId
    [object]$CdpServer

    hidden [System.Threading.ManualResetEventSlim]$SessionReady = [System.Threading.ManualResetEventSlim]::new($false)
    hidden [System.Threading.ManualResetEventSlim]$RuntimeReady = [System.Threading.ManualResetEventSlim]::new($false)

    CdpPage($TargetId, $Url, $Title, $BrowserContextId, $CdpServer) {
        $this.LoadingState['NetworkIdle'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FrameStoppedLoading'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['Load'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FirstPaint'] = [System.Threading.ManualResetEventSlim]::new($false)

        $this.TargetId = $TargetId
        $this.Title = $Title
        $this.CdpServer = $CdpServer

        $this.TargetInfo['SessionId'] = $null
        $this.TargetInfo['Url'] = $Url
        $this.TargetInfo['BrowserContextId'] = $BrowserContextId

        $this.PageInfo['RuntimeUniqueId'] = $null
        $this.PageInfo['ObjectId'] = $null
        $this.PageInfo['Node'] = $null
        $this.PageInfo['BoxModel'] = $null
    }

    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$TargetInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$PageInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]$LoadingState = [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, CdpFrame]]$Frames = [System.Collections.Concurrent.ConcurrentDictionary[string, CdpFrame]]::new()


    [void]ResetLoadingState() {
        $this.LoadingState['NetworkIdle'].Reset()
        $this.LoadingState['FrameStoppedLoading'].Reset()
        $this.LoadingState['Load'].Reset()
        $this.LoadingState['FirstPaint'].Reset()
    }

    [void]Dispose() {
        $this.SessionReady.Set()
        $this.RuntimeReady.Set()
        $this.SessionReady.Dispose()
        $this.RuntimeReady.Dispose()
        foreach ($LoadingState in $this.LoadingState.GetEnumerator()) {
            $LoadingState.Value.Set()
            $LoadingState.Value.Dispose()
        }

        foreach ($CdpFrame in $this.Frames.GetEnumerator()) {
            $CdpFrame.Dispose()
        }
    }
}
