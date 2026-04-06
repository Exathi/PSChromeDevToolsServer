# [NoRunspaceAffinity()]
class CdpEventHandler {
    [System.Collections.Generic.Dictionary[string, object]]$SharedState
    [hashtable]$EventHandlers

    CdpEventHandler([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$SharedState) {
        $this.SharedState = $SharedState
        $this.InitializeHandlers()
    }

    hidden [void]InitializeHandlers() {
        $this.EventHandlers = @{
            'Page.frameAttached' = $this.FrameAttached
            'Page.frameDetached' = $this.FrameDetached
            'Page.FrameNavigated' = $this.FrameNavigated
            'Page.lifecycleEvent' = $this.LifecycleEvent
            'Page.frameStartedNavigating' = $this.FrameStartedNavigating
            'Page.frameStoppedLoading' = $this.FrameStoppedLoading
            'Target.targetCreated' = $this.TargetCreated
            'Target.targetDestroyed' = $this.TargetDestroyed
            'Target.targetInfoChanged' = $this.TargetInfoChanged
            'Target.attachedToTarget' = $this.AttachedToTarget
            'Target.detachedFromTarget' = $this.DetachedFromTarget
            'Runtime.executionContextsCleared' = $this.ExecutionContextsCleared
            'Runtime.executionContextCreated' = $this.ExecutionContextCreated
        }
    }

    [void]ProcessEvent($Response) {
        if ($null -eq $Response.method) { return }
        $Handler = $this.EventHandlers[$Response.method]
        if ($Handler) {
            $Handler.Invoke($Response)
        }
        # else {
        # 	Write-Debug ('Unprocessed Event: ({0})' -f $Response.method)
        # }
        $Callback = $this.SharedState.Callbacks["On$($Response.method.Split('.')[1])".ToUpper()]
        if ($Callback) {
            $Callback.Invoke($Response)
        }
    }

    hidden [void]FrameAttached($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $Frame = $CdpPage.Frames.GetOrAdd($Response.params.frameId, [CdpFrame]::new($Response.params.frameId, $Response.sessionId))
        $Frame.ParentFrameId = $Response.params.parentFrameId
    }

    hidden [void]FrameDetached($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $CdpFrame = $null
        if ($CdpPage.Frames.TryRemove($Response.params.frameId, [ref]$CdpFrame)) {
            $CdpFrame.LoadingState['FrameStoppedLoading'] = $true
            $CdpFrame.LoadingState['NetworkIdle'] = $true
            $CdpFrame.LoadingState['FirstPaint'] = $true
        }
    }

    hidden [void]FrameNavigated($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        if ($CdpPage.TargetId -eq $Response.params.frame.id) {
            $CdpPage.LoadingState['FrameNavigated'] = $true
        }
    }

    hidden [void]LifecycleEvent($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $Target = if ($CdpPage.TargetId -eq $Response.params.frameId) {
            $CdpPage
        } else {
            $CdpPage.Frames.GetOrAdd($Response.params.frameId, [CdpFrame]::new($Response.params.frameId, $Response.sessionId))
        }
        $LifeCycleName = $Response.params.name
        if ($LifeCycleName -eq 'networkIdle' -or $LifeCycleName -eq 'load' -or $LifeCycleName -eq 'firstPaint') {
            switch ($LifeCycleName) {
                'networkIdle' {
                    $Target.LoadingState['NetworkIdle'] = $true
                    break
                }
                'load' {
                    $Target.LoadingState['Load'] = $true
                    break
                }
                'firstPaint' {
                    $Target.LoadingState['FirstPaint'] = $true
                    break
                }
            }
        }
    }

    hidden [void]FrameStartedNavigating($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        if ($CdpPage.TargetId -eq $Response.params.frameId) {
            $CdpPage.LoadingState['FrameNavigated'] = $false
        }
    }

    hidden [void]FrameStoppedLoading($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        if ($CdpPage.TargetId -eq $Response.params.frameId) {
            $CdpPage.LoadingState['FrameStoppedLoading'] = $true
        } else {
            $Frame = $null
            $null = $CdpPage.Frames.TryGetValue($Response.params.frameId, [ref]$Frame)
            if ($Frame) {
                $Frame.LoadingState['FrameStoppedLoading'] = $true
            }
        }
    }

    hidden [void]TargetCreated($Response) {
        $Target = $Response.params.targetInfo
        $CdpPage = [CdpPage]::new($Target.targetId, $Target.Url, $Target.Title, $Target.browserContextId, $this.SharedState.CdpServer)
        $null = $this.SharedState.Targets.TryAdd($Target.targetId, $CdpPage)
    }

    hidden [void]TargetDestroyed($Response) {
        $CdpPage = $this.GetPageByTargetId($Response.params.targetId)
        if ($CdpPage) {
            $null = $this.SharedState.Targets.TryRemove($CdpPage.TargetId, [ref]$null)
        }
    }

    hidden [void]TargetInfoChanged($Response) {
        $Target = $Response.params.targetInfo
        $CdpPage = $this.GetPageByTargetId($Target.targetId)
        if ($CdpPage) {
            $CdpPage.Url = $Target.Url
            $CdpPage.Title = $Target.Title
            $CdpPage.ProcessId = $Target.pid
        }
    }

    hidden [void]AttachedToTarget($Response) {
        $Target = $Response.params.targetInfo
        $CdpPage = $this.GetPageByTargetId($Target.targetId)
        $CdpPage.TargetInfo.AddOrUpdate('SessionId', $Response.params.sessionId, { param($Key, $OldValue) $Response.params.sessionId })
        $null = $this.SharedState.Sessions.TryAdd($Response.params.sessionId, $CdpPage)
    }

    hidden [void]DetachedFromTarget($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.params.sessionId)
        $CdpPage.TargetInfo.AddOrUpdate('SessionId', $null, { param($Key, $OldValue) $null })
        $null = $this.SharedState.Sessions.TryRemove($Response.params.sessionId, [ref]$null)
    }

    hidden [void]ExecutionContextsCleared($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $CdpPage.Frames.Clear()
    }

    hidden [void]ExecutionContextCreated($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $FrameId = $Response.params.context.auxData.frameId
        if ($CdpPage.TargetId -eq $FrameId) {
            $CdpPage.PageInfo.AddOrUpdate('RuntimeUniqueId', $Response.params.context.uniqueId, { param($Key, $OldValue) $Response.params.context.uniqueId } )
        } else {
            $Frame = $CdpPage.Frames.GetOrAdd($FrameId, [CdpFrame]::new($FrameId, $Response.sessionId))
            $Frame.PageInfo['RuntimeUniqueId'] = $Response.params.context.uniqueId
        }
    }

    [CdpPage]GetPageBySessionId([string]$SessionId) {
        $CdpPage = $null
        [System.Threading.SpinWait]::SpinUntil({ $this.SharedState.Sessions.TryGetValue($SessionId, [ref]$CdpPage) })
        return $CdpPage
    }

    [CdpPage]GetPageByTargetId([string]$TargetId) {
        $CdpPage = $null
        [System.Threading.SpinWait]::SpinUntil({ $this.SharedState.Targets.TryGetValue($TargetId, [ref]$CdpPage) })
        return $CdpPage
    }
}
