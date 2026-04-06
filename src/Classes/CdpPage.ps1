class CdpPage {
    # it's more dictionary now than property
    # did not want to use monitor.enter/exit
    [string]$TargetId
    [string]$Url
    [string]$Title
    [string]$BrowserContextId
    [int]$ProcessId
    [object]$CdpServer

    CdpPage($TargetId, $Url, $Title, $BrowserContextId, $CdpServer) {
        $this.TargetId = $TargetId
        $this.Url = $Url
        $this.Title = $Title
        $this.BrowserContextId = $BrowserContextId
        $this.CdpServer = $CdpServer

        $this.TargetInfo['SessionId'] = $null

        $this.ResetLoadingState()

        $this.PageInfo['RuntimeUniqueId'] = $null
        $this.PageInfo['ObjectId'] = $null
        $this.PageInfo['Node'] = $null
        $this.PageInfo['BoxModel'] = $null
    }

    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$TargetInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]$LoadingState = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Frames = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$PageInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

    [void]ResetLoadingState() {
        $this.LoadingState['NetworkIdle'] = $false
        $this.LoadingState['FrameStoppedLoading'] = $false
        $this.LoadingState['Load'] = $false
        $this.LoadingState['FirstPaint'] = $false
        $this.LoadingState['FrameNavigated'] = $true
    }
}
