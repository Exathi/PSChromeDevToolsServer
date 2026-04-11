class CdpFrame {
    [string]$FrameId
    [string]$ParentFrameId

    hidden [System.Threading.ManualResetEventSlim]$RuntimeReady = [System.Threading.ManualResetEventSlim]::new($false)

    CdpFrame ($FrameId, $SessionId) {
        $this.LoadingState['NetworkIdle'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FrameStoppedLoading'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['Load'] = [System.Threading.ManualResetEventSlim]::new($false)
        $this.LoadingState['FirstPaint'] = [System.Threading.ManualResetEventSlim]::new($false)

        $this.FrameId = $FrameId
        $this.ParentFrameId = $null
        $this.TargetInfo['SessionId'] = $SessionId
        $this.TargetInfo['Url'] = $null
        $this.PageInfo['RuntimeUniqueId'] = $null
    }

    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$TargetInfo = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
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

# [NoRunspaceAffinity()]
class CdpEventHandler {
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$SharedState
    [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]$NewTargets = [System.Collections.Concurrent.ConcurrentDictionary[string, [System.Threading.ManualResetEventSlim]]]::new()
    [hashtable]$EventHandlers

    CdpEventHandler([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$SharedState) {
        $this.SharedState = $SharedState
        $this.InitializeHandlers()
    }

    hidden [void]InitializeHandlers() {
        $this.EventHandlers = @{
            'Page.frameAttached' = $this.FrameAttached
            'Page.frameDetached' = $this.FrameDetached
            'Page.frameNavigated' = $this.FrameNavigated
            'Page.lifecycleEvent' = $this.LifecycleEvent
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
        $Handler = $this.EventHandlers[$Response.method]
        if ($Handler) {
            $Handler.Invoke($Response)
        }

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
            $CdpFrame.Dispose()
        }
    }

    hidden [void]FrameNavigated($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)

        if ($CdpPage.TargetId -eq $Response.params.frame.id) {
            # Let targetinfo changed update instead.
            # But we have to check incase we're not adding a target into the frame dictionary
        } else {
            $Target = $CdpPage.Frames.GetOrAdd($Response.params.frame.id, [CdpFrame]::new($Response.params.frame.id, $Response.sessionId))
            $Target.TargetInfo['Url'] = $Response.params.frame.url
            $Target.TargetInfo['Name'] = $Response.params.frame.name
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

        switch ($LifeCycleName) {
            'networkIdle' {
                $Target.LoadingState['NetworkIdle'].Set()
                break
            }
            'load' {
                $Target.LoadingState['Load'].Set()
                break
            }
            'firstPaint' {
                $Target.LoadingState['FirstPaint'].Set()
                break
            }
        }
    }

    hidden [void]FrameStoppedLoading($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        if ($CdpPage.TargetId -eq $Response.params.frameId) {
            $CdpPage.LoadingState['FrameStoppedLoading'].Set()
        } else {
            $Frame = $null
            $null = $CdpPage.Frames.TryGetValue($Response.params.frameId, [ref]$Frame)
            if ($Frame) {
                $Frame.LoadingState['FrameStoppedLoading'].Set()
            }
        }
    }

    hidden [void]TargetCreated($Response) {
        $Target = $Response.params.targetInfo
        $CdpPage = [CdpPage]::new($Target.targetId, $Target.Url, $Target.Title, $Target.browserContextId, $this.SharedState.CdpServer)
        $CdpPageReady = $this.NewTargets.GetOrAdd($Target.targetId, [System.Threading.ManualResetEventSlim]::new($false))
        $this.SharedState.Targets[$Target.targetId] = $CdpPage
        $CdpPageReady.Set()
    }

    hidden [void]TargetDestroyed($Response) {
        $TargetId = $Response.params.targetId
        $CdpPage = $this.GetPageByTargetId($TargetId)
        if ($CdpPage) {
            $null = $this.SharedState.Targets.TryRemove($TargetId, [ref]$null)
            $CdpPage.Dispose()
        }
        $this.NewTargets[$TargetId].Dispose()
        $this.NewTargets[$TargetId] = $null # Don't remove. Set to null instead so if there are lingering threads that are looking for it, they won't block.
    }

    hidden [void]TargetInfoChanged($Response) {
        $Target = $Response.params.targetInfo
        $CdpPage = $this.GetPageByTargetId($Target.targetId)
        if ($CdpPage) {
            $CdpPage.TargetInfo['Url'] = $Target.Url
            $CdpPage.Title = $Target.Title
            $CdpPage.ProcessId = $Target.pid
        }
    }

    hidden [void]AttachedToTarget($Response) {
        $SessionId = $Response.params.sessionId
        $CdpPage = $this.GetPageByTargetId($Response.params.targetInfo.targetId)
        $CdpPage.TargetInfo['SessionId'] = $SessionId
        $this.SharedState.Sessions[$SessionId] = $CdpPage
        $CdpPage.SessionReady.Set()
    }

    hidden [void]DetachedFromTarget($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.params.sessionId)
        $CdpPage.TargetInfo.AddOrUpdate('SessionId', $null, { param($Key, $OldValue) $null })
        $null = $this.SharedState.Sessions.TryRemove($Response.params.sessionId, [ref]$null)
    }

    hidden [void]ExecutionContextsCleared($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        if ($CdpPage.RuntimeReady.IsSet) { $CdpPage.RuntimeReady.Reset() }
        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            if ($CdpFrame.RuntimeReady.IsSet) {
                $CdpFrame.Dispose()
            }
        }
        $CdpPage.Frames.Clear()
    }

    hidden [void]ExecutionContextCreated($Response) {
        $CdpPage = $this.GetPageBySessionId($Response.sessionId)
        $FrameId = $Response.params.context.auxData.frameId
        if ($CdpPage.TargetId -eq $FrameId) {
            $CdpPage.PageInfo.AddOrUpdate('RuntimeUniqueId', $Response.params.context.uniqueId, { param($Key, $OldValue) $Response.params.context.uniqueId } )
            $CdpPage.RuntimeReady.Set()
        } else {
            $Frame = $CdpPage.Frames.GetOrAdd($FrameId, [CdpFrame]::new($FrameId, $Response.sessionId))
            $Frame.PageInfo['RuntimeUniqueId'] = $Response.params.context.uniqueId
            $Frame.RuntimeReady.Set()
        }
    }

    [CdpPage]GetPageBySessionId([string]$SessionId) {
        return $this.SharedState.Sessions[$SessionId]
    }

    [CdpPage]GetPageByTargetId([string]$TargetId) {
        $CdpPage = $null
        if (!$this.SharedState.Targets.TryGetValue($TargetId, [ref]$CdpPage)) {
            $CdpPageReady = $this.NewTargets.GetOrAdd($TargetId, [System.Threading.ManualResetEventSlim]::new($false))
            $CdpPageReady.Wait()
        }
        return $this.SharedState.Targets[$TargetId]
    }
}

enum WaitForResponse {
    None = 0
    Message
    CommandId
}

# [NoRunspaceAffinity()]
class CdpServer {
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$SharedState = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    [System.Diagnostics.Process]$ChromeProcess
    [pscustomobject]$Threads = @{
        MessageReader = $null
        MessageReaderHandle = $null
        MessageProcessor = [System.Collections.Generic.List[Powershell]]::new()
        MessageProcessorHandle = [System.Collections.Generic.List[IAsyncResult]]::new()
        MessageWriter = $null
        MessageWriterHandle = $null
    }

    CdpServer([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks) {
        $this.Init($BrowserPath, $StreamOutput, $BrowserArgs, $AdditionalThreads, $Callbacks, $null)
    }

    CdpServer([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks, [System.Management.Automation.Runspaces.InitialSessionState]$State) {
        $this.Init($BrowserPath, $StreamOutput, $BrowserArgs, $AdditionalThreads, $Callbacks, $State)
    }

    hidden [void]Init([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks, [System.Management.Automation.Runspaces.InitialSessionState]$State) {
        $this.SharedState.IO = @{
            PipeWriter = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::Out, [System.IO.HandleInheritability]::Inheritable)
            PipeReader = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::In, [System.IO.HandleInheritability]::Inheritable)
            UnprocessedResponses = [System.Collections.Concurrent.BlockingCollection[object]]::new()
            CommandQueue = [System.Collections.Concurrent.BlockingCollection[object]]::new()
        }

        $this.SharedState.CdpServer = $this
        $this.SharedState.MessageHistory = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $this.SharedState.CommandHistory = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        $this.SharedState.CommandId = 0
        $this.SharedState.Targets = [System.Collections.Concurrent.ConcurrentDictionary[string, CdpPage]]::new()
        $this.SharedState.Sessions = [System.Collections.Concurrent.ConcurrentDictionary[string, CdpPage]]::new()
        $this.SharedState.Callbacks = [System.Collections.Generic.Dictionary[string, scriptblock]]::new()

        foreach ($Key in $Callbacks.Keys) {
            $UpperKey = $Key.ToUpper()
            $this.SharedState.Callbacks[$UpperKey] = $Callbacks[$UpperKey]
        }

        $this.SharedState.Commands = @{
            SendRuntimeEvaluate = $this.CreateDelegate($this.SendRuntimeEvaluate)
        }

        $this.SharedState.EventHandler = [CdpEventHandler]::new($this.SharedState) # New-UnboundClassInstance -type ([CdpEventHandler]) -arguments @($this.SharedState)

        if (!$State) {
            $State = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        }

        $State.ImportPSModule("$PSScriptRoot\PSChromeDevToolsServer")
        $RunspaceSharedState = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new('SharedState', $this.SharedState, $null)
        $State.Variables.Add($RunspaceSharedState)
        $State.ThrowOnRunspaceOpenError = $true
        $this.RunspacePool = [RunspaceFactory]::CreateRunspacePool(3, 3 + $AdditionalThreads, $State, $StreamOutput)
        $this.RunspacePool.Open()

        if (($BrowserArgs -like '--user-data-dir*').Count -ne 1) { throw '--user-data-dir is required.' }
        $BrowserArgs += (' --remote-debugging-pipe --remote-debugging-io-pipes={0},{1}' -f $this.SharedState.IO.PipeWriter.GetClientHandleAsString(), $this.SharedState.IO.PipeReader.GetClientHandleAsString())

        $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = $BrowserPath
        $StartInfo.Arguments = $BrowserArgs
        $StartInfo.UseShellExecute = $false

        $this.ChromeProcess = [System.Diagnostics.Process]::Start($StartInfo)

        while (!$this.SharedState.IO.PipeWriter.IsConnected -and !$this.SharedState.IO.PipeReader.IsConnected) {
            Start-Sleep -Milliseconds 1
        }

        $this.SharedState.IO.PipeWriter.DisposeLocalCopyOfClientHandle()
        $this.SharedState.IO.PipeReader.DisposeLocalCopyOfClientHandle()
    }

    [void]StartMessageReader() {
        if ($this.RunspacePool.GetAvailableRunspaces() -eq 0) { throw 'no runspaces available in runspacepool' }

        $this.Threads.MessageReader = [powershell]::Create()
        $this.Threads.MessageReader.RunspacePool = $this.RunspacePool
        $null = $this.Threads.MessageReader.AddScript({
                if ($SharedState.DebugPreference) { $DebugPreference = $SharedState.DebugPreference }
                if ($SharedState.VerbosePreference) { $VerbosePreference = $SharedState.VerbosePreference }

                $Buffer = [byte[]]::new(1024)
                $StringBuilder = [System.Text.StringBuilder]::new()
                $NullTerminatedString = "`0"

                while ($SharedState.IO.PipeReader.IsConnected) {
                    # Will hang here until something comes through the pipe.
                    $BytesRead = $SharedState.IO.PipeReader.Read($Buffer, 0, $Buffer.Length)
                    $null = $StringBuilder.Append([System.Text.Encoding]::UTF8.GetString($Buffer, 0, $BytesRead))

                    $HasCompletedMessages = if ($StringBuilder.Length) { $StringBuilder.ToString($StringBuilder.Length - 1, 1) -eq $NullTerminatedString } else { $false }
                    if ($HasCompletedMessages) {
                        $RawResponse = $StringBuilder.ToString()
                        $SplitResponse = @(($RawResponse -split $NullTerminatedString).Where({ "`0" -ne $_ }) | ConvertFrom-Json)
                        foreach ($Response in $SplitResponse) {
                            $SharedState.IO.UnprocessedResponses.Add($Response)
                        }
                        $StringBuilder.Clear()
                    }
                }
            }
        )
        $this.Threads.MessageReaderHandle = $this.Threads.MessageReader.BeginInvoke()
    }

    [void]StartMessageProcessor() {
        if ($this.RunspacePool.GetAvailableRunspaces() -eq 0) { throw 'no runspaces available in runspacepool' }

        $Powershell = [powershell]::Create()
        $this.Threads.MessageProcessor.Add($Powershell)
        $Powershell.RunspacePool = $this.RunspacePool
        $null = $Powershell.AddScript({
                if ($SharedState.DebugPreference) { $DebugPreference = $SharedState.DebugPreference }
                if ($SharedState.VerbosePreference) { $VerbosePreference = $SharedState.VerbosePreference }

                foreach ($Response in $SharedState.IO.UnprocessedResponses.GetConsumingEnumerable()) {
                    if ($Response.id) {
                        $SharedState.CommandHistory[$Response.id].Response = $Response
                        switch ($SharedState.CommandHistory[$Response.id].WaitForResponse) {
                            'None' { break }
                            Default { $SharedState.CommandHistory[$Response.id].CommandReady.Set() }
                        }
                    } else {
                        $SharedState.EventHandler.ProcessEvent($Response)
                    }

                    $SharedState.MessageHistory.Enqueue($Response)
                    while ($SharedState.MessageHistory.Count -gt 300) {
                        $SharedState.MessageHistory.TryDequeue([ref]$null)
                    }
                }
            }
        )
        $this.Threads.MessageProcessorHandle.Add($Powershell.BeginInvoke())
    }

    [void]StartMessageWriter() {
        if ($this.RunspacePool.GetAvailableRunspaces() -eq 0) { throw 'no runspaces available in runspacepool' }

        $this.Threads.MessageWriter = [powershell]::Create()
        $this.Threads.MessageWriter.RunspacePool = $this.RunspacePool
        $null = $this.Threads.MessageWriter.AddScript({
                if ($SharedState.DebugPreference) { $DebugPreference = $SharedState.DebugPreference }
                if ($SharedState.VerbosePreference) { $VerbosePreference = $SharedState.VerbosePreference }

                foreach ($CommandBytes in $SharedState.IO.CommandQueue.GetConsumingEnumerable()) {
                    $SharedState.IO.PipeWriter.Write($CommandBytes, 0, $CommandBytes.Length)
                }
            }
        )
        $this.Threads.MessageWriterHandle = $this.Threads.MessageWriter.BeginInvoke()
    }

    [void]Stop() {
        $this.SharedState.IO.PipeReader.Dispose()
        $this.SharedState.IO.PipeWriter.Dispose()
        $this.SharedState.IO.UnprocessedResponses.CompleteAdding()
        $this.SharedState.IO.CommandQueue.CompleteAdding()
        if ($this.Threads.MessageReaderHandle) {
            $this.Threads.MessageReader.EndInvoke($this.Threads.MessageReaderHandle)
            $this.Threads.MessageReader.Dispose()
        }
        if ($this.Threads.MessageProcessorHandle.Count -gt 0) {
            for ($i = 0; $i -lt $this.Threads.MessageProcessorHandle.Count; $i++) {
                $this.Threads.MessageProcessor[$i].EndInvoke($this.Threads.MessageProcessorHandle[$i])
            }
        }
        if ($this.Threads.MessageWriterHandle) {
            $this.Threads.MessageWriter.EndInvoke($this.Threads.MessageWriterHandle)
            $this.Threads.MessageWriter.Dispose()
        }
        $this.SharedState.IO.UnprocessedResponses.Dispose()
        $this.SharedState.IO.CommandQueue.Dispose()
        $this.ChromeProcess.Dispose()
        $this.RunspacePool.Dispose()
    }

    [void]SendCommand([hashtable]$Command) {
        $this.SendCommand($Command, [WaitForResponse]::None)
    }

    [object]SendCommand([hashtable]$Command, [WaitForResponse]$WaitForResponse) {
        # This should be the only place where $this.SharedState.CommandId is incremented.
        $CommandId = $this.SharedState.AddOrUpdate('CommandId', 1, { param($Key, $OldValue) $OldValue + 1 })

        $null = $this.SharedState.CommandHistory.TryAdd($CommandId, @{
                Method = $Command.method
                CommandReady = [System.Threading.ManualResetEventSlim]::new($false)
                WaitForResponse = $WaitForResponse
                Response = $null
            }
        )

        $Command.id = $CommandId
        $JsonCommand = $Command | ConvertTo-Json -Depth 10 -Compress
        $CommandBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonCommand) + 0
        $this.SharedState.IO.CommandQueue.Add($CommandBytes)

        $Response = switch ($WaitForResponse) {
            ([WaitForResponse]::None) {
                $this.SharedState.CommandHistory[$CommandId].CommandReady.Dispose()
                $this.SharedState.CommandHistory[$CommandId].CommandReady = $null
                $null
                break
            }
            ([WaitForResponse]::Message) {
                $this.SharedState.CommandHistory[$CommandId].CommandReady.Wait()
                $this.SharedState.CommandHistory[$CommandId].Response
                $this.SharedState.CommandHistory[$CommandId].CommandReady.Dispose()
                $this.SharedState.CommandHistory[$CommandId].CommandReady = $null
                break
            }
            ([WaitForResponse]::CommandId) {
                $CommandId
                break
            }
        }

        return $Response
    }

    [CdpPage]GetPageByTargetId([string]$TargetId) {
        $CdpPage = $null
        if (!$this.SharedState.Targets.TryGetValue($TargetId, [ref]$CdpPage)) {
            $CdpPageReady = $this.SharedState.EventHandler.NewTargets.GetOrAdd($TargetId, [System.Threading.ManualResetEventSlim]::new($false))
            $CdpPageReady.Wait()
        }
        return $this.SharedState.Targets[$TargetId]
    }

    [void]SendRuntimeEvaluate([string]$SessionId, [string]$Expression) {
        $Command = @{
            method = 'Runtime.evaluate'
            sessionId = $SessionId
            params = @{
                expression = $Expression
            }
        }
        $this.SendCommand($Command)
    }

    [void]EnableDefaultEvents() {
        $Command = Get-Target.setDiscoverTargets
        $this.SendCommand($Command)

        $Command = Get-Target.setAutoAttach
        $this.SendCommand($Command)
    }

    [object]ShowMessageHistory() {
        $Events = $this.SharedState.MessageHistory.GetEnumerator() | Select-Object -Property @(
            @{Name = 'id'; Expression = { $_.id } },
            @{Name = 'method'; Expression = { if ($_.method) { $_.method } else { $this.SharedState.CommandHistory[$_.id].Method } } },
            @{Name = 'error'; Expression = { $_.error } },
            @{Name = 'sessionId'; Expression = { $_.sessionId } },
            @{Name = 'params'; Expression = { $_.params } },
            @{Name = 'result'; Expression = { $_.result } }
        )
        return $Events
    }

    [void]WaitForPageLoad([CdpPage]$CdpPage, [int]$Timeout) {
        if (!$CdpPage.LoadingState['Load'].Wait($Timeout)) { throw 'Page Load event was not fired.' }
        if (!$CdpPage.LoadingState['FrameStoppedLoading'].Wait($Timeout)) { throw 'Page FrameStoppedLoading event was not fired.' }
        if (!$CdpPage.RuntimeReady.Wait($Timeout)) { throw 'Page Runtime context id was not created in time.' }

        # Wait for all child frames to load and have executioncontext
        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            if (!$CdpFrame.Value.LoadingState['Load'].Wait($Timeout)) { throw 'Frame Load event was not fired.' }
            if (!$CdpFrame.Value.LoadingState['FrameStoppedLoading'].Wait($Timeout)) { throw 'Frame FrameStoppedLoading event was not fired.' }
            if (!$CdpFrame.Value.RuntimeReady.Wait($Timeout)) { throw 'Frame Runtime context id was not created in time.' }
        }
    }

    [void]SetupNewPage([CdpPage]$CdpPage) {
        $CdpPage.SessionReady.Wait()
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $Command = Get-Runtime.enable $SessionId
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        $CdpPage.RuntimeReady.Wait()

        $Command = Get-Page.enable $SessionId
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        $Command = Get-Page.setLifecycleEventsEnabled $SessionId $true
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            $CdpFrame.Value.RuntimeReady.Wait()
        }
    }

    hidden [Delegate]CreateDelegate([System.Management.Automation.PSMethod]$Method) {
        return $this.CreateDelegate($Method, $this)
    }

    hidden [Delegate]CreateDelegate([System.Management.Automation.PSMethod]$Method, $Target) {
        $reflectionMethod = if ($Target.GetType().Name -eq 'PSCustomObject') {
            $Target.psobject.GetType().GetMethod($Method.Name)
        } else {
            $Target.GetType().GetMethod($Method.Name)
        }
        $parameterTypes = [System.Linq.Enumerable]::Select($reflectionMethod.GetParameters(), [func[object, object]] { $args[0].parametertype })
        $concatMethodTypes = $parameterTypes + $reflectionMethod.ReturnType
        $delegateType = [System.Linq.Expressions.Expression]::GetDelegateType($concatMethodTypes)
        $delegate = [delegate]::CreateDelegate($delegateType, $Target, $reflectionMethod.Name)
        return $delegate
    }
}

function ConvertTo-FlatNode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Node,
        [string]$TopParent = $null,
        [bool]$IsShadowRoot
    )

    foreach ($Child in $Node) {
        # Determine the ultimate parent for this child
        $IsHead = if ($Child.nodeName -eq 'HEAD') {
            $Child.nodeName
        } else {
            $TopParent
        }

        $FlatNode = [PSCustomObject]@{
            TopParentName = $IsHead
            IsShadowRoot = $IsShadowRoot
            NodeId = $Child.nodeId
            NodeType = $Child.nodeType
            ParentId = $Child.parentId
            BackendNodeId = $Child.backendNodeId
            NodeValue = $Child.nodeValue
            NodeName = $Child.nodeName
            LocalName = $Child.localName
            Attributes = $null
            FrameId = $Child.frameId
            AttributesString = $Child.attributes
            DocumentURL = $Child.documentURL
            # ShadowRoots = $Child.shadowRoots
            # ContentFrame = $Child.contentFrame
        }

        $FlatNode.Attributes = if ($Child.attributes) {
            for ($i = 0; $i -lt $Child.attributes.Count; $i += 2) {
                [pscustomobject]@{
                    Name = $Child.attributes[$i]
                    Value = $Child.attributes[$i + 1]
                }
            }
        }

        if ($Child.Children) {
            ConvertTo-FlatNode -Node $Child.Children -TopParent $IsHead -IsShadowRoot $IsShadowRoot
        }

        if ($Child.contentDocument) {
            # $FlatNode.contentFrame = ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null
            ConvertTo-FlatNode -Node $Child.contentDocument -TopParent $null -IsShadowRoot $IsShadowRoot
        }

        if ($Child.shadowRoots) {
            ConvertTo-FlatNode -Node $Child.shadowRoots -TopParent $null -IsShadowRoot $true
        }

        $FlatNode
    }
}


function Get-DOM.describeNode {
    param($SessionId)
    @{
        method = 'DOM.describeNode'
        sessionId = $SessionId
        params = @{}
    }
}
function Get-DOM.disable {
    param($SessionId)
    @{
        method = 'DOM.disable'
        sessionId = $SessionId
    }
}
function Get-DOM.getBoxModel {
    param($SessionId)
    @{
        method = 'DOM.getBoxModel'
        sessionId = $SessionId
        params = @{}
    }
}
function Get-DOM.getDocument {
    param($SessionId)
    @{
        method = 'DOM.getDocument'
        sessionId = $SessionId
        params = @{
            depth = -1
            pierce = $true
        }
    }
}

function Get-Input.dispatchKeyEvent {
    param($SessionId, $Text)
    @{
        method = 'Input.dispatchKeyEvent'
        sessionId = $SessionId
        params = @{
            type = 'char'
            text = $Text
        }
    }
}
function Get-Input.dispatchMouseEvent {
    param($SessionId, $Type, $X, $Y, $Button)
    @{
        method = 'Input.dispatchMouseEvent'
        sessionId = $SessionId
        params = @{
            type = $Type
            button = $Button
            clickCount = 0
            x = $X
            y = $Y
        }
    }
}

function Get-Page.bringToFront {
    param($SessionId)
    @{
        method = 'Page.bringToFront'
        sessionId = $SessionId
    }
}
function Get-Page.enable {
    param($SessionId)
    @{
        method = 'Page.enable'
        sessionId = $SessionId
    }
}
function Get-Page.navigate {
    param($SessionId, $Url)
    @{
        method = 'Page.navigate'
        sessionId = $SessionId
        params = @{
            url = $Url
        }
    }
}
function Get-Page.getFrameTree {
    param($SessionId)
    @{
        method = 'Page.getFrameTree'
        sessionId = $SessionId
    }
}
function Get-Page.setLifecycleEventsEnabled {
    param($SessionId, [bool]$Enabled)
    @{
        method = 'Page.setLifecycleEventsEnabled'
        sessionId = $SessionId
        params = @{
            enabled = $Enabled
        }
    }
}

function Get-Runtime.addBinding {
    param($SessionId, $Name)
    @{
        method = 'Runtime.addBinding'
        sessionId = $SessionId
        params = @{
            name = $Name
        }
    }
}
function Get-Runtime.enable {
    param($SessionId)
    @{
        method = 'Runtime.enable'
        sessionId = $SessionId
    }
}
function Get-Runtime.evaluate {
    param($SessionId, $Expression)
    @{
        method = 'Runtime.evaluate'
        sessionId = $SessionId
        params = @{
            expression = $Expression
        }
    }
}

function Get-Target.createTarget {
    param($Url)
    @{
        method = 'Target.createTarget'
        params = @{
            url = $Url
        }
    }
}

function Get-Target.createBrowserContext {
    param()
    @{
        method = 'Target.createBrowserContext'
        params = @{
            disposeOnDetach = $true
        }
    }
}

function Get-Target.setAutoAttach {
    param()
    @{
        method = 'Target.setAutoAttach'
        params = @{
            autoAttach = $true
            waitForDebuggerOnStart = $false
            filter = @(
                @{
                    type = 'service_worker'
                    exclude = $true
                },
                @{
                    type = 'worker'
                    exclude = $true
                },
                @{
                    type = 'browser'
                    exclude = $true
                },
                @{
                    type = 'tab'
                    exclude = $true
                },
                # @{
                #     type = 'other'
                #     exclude = $true
                # },
                @{
                    type = 'background_page'
                    exclude = $true
                },
                @{}
            )
            flatten = $true
        }
    }
}

function Get-Target.setDiscoverTargets {
    param($Url)
    @{
        method = 'Target.setDiscoverTargets'
        params = @{
            discover = $true
            filter = @(
                @{
                    type = 'service_worker'
                    exclude = $true
                },
                @{
                    type = 'worker'
                    exclude = $true
                },
                @{
                    type = 'browser'
                    exclude = $true
                },
                @{
                    type = 'tab'
                    exclude = $true
                },
                # @{
                #     type = 'other'
                #     exclude = $true
                # },
                @{
                    type = 'background_page'
                    exclude = $true
                },
                @{}
            )
        }
    }
}

function Get-CdpFrameTree {
    param($Tree)
    if ($Tree.frame) { $Tree.frame }
    if ($Tree.childFrames) {
        foreach ($Child in $Tree.childFrames) {
            Get-CdpFrameTree $Child
        }
    }
}

$script:Powershell = $null

function New-UnboundClassInstance ([Type] $type, [object[]] $arguments = $null) {
    if ($null -eq $script:Powershell) {
        $script:Powershell = [powershell]::Create()
        $script:Powershell.AddScript({
                function New-UnboundClassInstance ([Type] $type, [object[]] $arguments) {
                    [activator]::CreateInstance($type, $arguments)
                }
            }.Ast.GetScriptBlock()
        ).Invoke()
        $script:Powershell.Commands.Clear()
    }

    try {
        if ($null -eq $arguments) { $arguments = @() }
        $result = $script:Powershell.AddCommand('New-UnboundClassInstance').
        AddParameter('type', $type).
        AddParameter('arguments', $arguments).
        Invoke()
        return $result
    } finally {
        $script:Powershell.Commands.Clear()
    }
}

function ConvertTo-Delegate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [System.Management.Automation.PSMethod[]]$Method,
        [Parameter(Mandatory)]
        [object]$Target
    )

    process {
        $reflectionMethod = if ($Target.GetType().Name -eq 'PSCustomObject') {
            $Target.psobject.GetType().GetMethod($Method.Name)
        } else {
            $Target.GetType().GetMethod($Method.Name)
        }
        $parameterTypes = [System.Linq.Enumerable]::Select($reflectionMethod.GetParameters(), [func[object, object]] { $args[0].parametertype })
        $concatMethodTypes = $parameterTypes + $reflectionMethod.ReturnType
        $delegateType = [System.Linq.Expressions.Expression]::GetDelegateType($concatMethodTypes)
        $delegate = [delegate]::CreateDelegate($delegateType, $Target, $reflectionMethod.Name)
        $delegate
    }
}

function Get-CdpFrame {
    <#
        .SYNOPSIS
        Gets a frame from the Frametree if it exists.
        .PARAMETER Url
        The regex pattern of a url to look for
        .PARAMETER Timeout
        Max time to wait(ms) before giving up.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$Timeout = 5000
    )

    begin {
        $PollInterval = 100
        $Sequence = 0
    }

    process {
        $TimeoutTime = (Get-Date).AddMilliseconds($Timeout)
        do {
            $Sequence++

            $Command = Get-Page.getFrameTree $CdpPage.TargetInfo.SessionId
            $Response = $CdpPage.CdpServer.SendCommand($Command, [WaitForResponse]::Message)

            $FramesTree = Get-CdpFrameTree $Response.result.frameTree

            $Match = $FramesTree.url | Select-String -Pattern $Url
            $MatchedFrame = $FramesTree | Where-Object { $_.url -eq $Match.Line }

            $CdpFrame = $CdpPage.Frames.Values | Where-Object { $_.FrameId -eq $MatchedFrame.id }

            if ($CdpFrame) { break }
            Start-Sleep -Milliseconds ([math]::Min(($PollInterval * $Sequence), 1000))
        } while (($TimeoutTime - (Get-Date)).Milliseconds -gt 0)

        if (!$CdpFrame) { throw ('Timed out. No frame found using: {0}' -f $Url) }

        [pscustomobject]@{
            CdpPage = $CdpPage
            CdpFrame = $CdpFrame
        }
    }
}

function Invoke-CdpCommand {
    <#
        .SYNOPSIS
        Invokes the provided cdp command with parameters on the CdpPage.
        All commands can be found here:
        https://chromedevtools.github.io/devtools-protocol/tot/
        .PARAMETER MethodName
        The name of the cdp method ex 'Page.navigate'
        .PARAMETER Parameters
        A hashtable of the parameters.
        Excluding id, method, and sessionId
        @{
            url = 'about:blank'
        }
        .EXAMPLE
        $Response = Invoke-CdpCommand -CdpPage $CdpPage -Method 'Page.navigate' -Parameters @{url = 'about:blank' }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$MethodName,
        [object]$Parameters
    )

    process {
        $CdpServer = $CdpPage.CdpServer

        $Command = @{
            method = $MethodName
            sessionId = $CdpPage.TargetInfo['SessionId']
        }

        if ($Parameters) {
            $Command.params = $Parameters
        }

        $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
    }
}

function Invoke-CdpInputClickElement {
    <#
        .SYNOPSIS
        Finds and clicks with element in the center of the box. Clicks from the top left of the element when $TopLeft is switched on.
        .PARAMETER FilterScript
        The scriptblock that will filter find valid nodes.
        Valid properties are:

        NodeId
        NodeType
        ParentId
        BackendNodeId
        NodeValue*
        NodeName*
        LocalName
        Attributes*
        FrameId
        AttributesString
        DocumentURL

        *The most common selectors
        NodeValue = any text on the page
        NodeName = element tag name
        Attributes = attributes for the tag such as:
            Name = id, Value = theId
            Name = autofocus

        .EXAMPLE
        $FilterScript = {
            $_.NodeName -eq '#text' -and
            $_.NodeValue -eq 'Woo woo'
        }

        $FilterScript = {
            $_.NodeName -eq 'a'
        }
        $Index = 5

        $FilterScript = {
            $_.NodeName -eq 'button'
        }
        $Index = 0

        $FilterScript = {
            $_.NodeValue -eq 'submit'
        }

        .PARAMETER Index
        The nth number of the Nodes found by FilterScript
        .PARAMETER Click
        Number of times to left click the mouse
        .PARAMETER OffsetX
        Number of pixels to offset from the center of the element on the X axis
        .PARAMETER OffsetY
        Number of pixels to offset from the center of the element on the Y axis
        .PARAMETER TopLeft
        Clicks from the top left of the element instead of center. Offset x and y will be relative to this position instead.
        .PARAMETER BringToFront
        Attemps to brings page to front once before sending click.
        .PARAMETER Delay
        Time in ms between each mouse down and mouse up command.
        .PARAMETER ExpectNavigation
        Resets loading state of main page inorder to wait for the next page on click.
        .PARAMETER Timeout
        Max time in ms to wait for expected navigation before throwing an error.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [scriptblock]$FilterScript,
        [int]$Index = 0,
        [int]$Click = 0,
        [int]$OffsetX = 0,
        [int]$OffsetY = 0,
        [switch]$TopLeft,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0,
        [Parameter(ParameterSetName = 'Navigation')]
        [switch]$ExpectNavigation,
        [Parameter(ParameterSetName = 'Navigation')]
        [int]$Timeout = 60000
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $CdpPage.PageInfo['Node'] = Test-CdpSelector -CdpPage $CdpPage -FilterScript $FilterScript -Index $Index -EnableDomEvents
        if ($CdpPage.PageInfo['Node'].nodeType -ne 1 -and $CdpPage.PageInfo['Node'].nodeType -ne 3) { throw ('Node is not an element or text. {0}' -f $CdpPage.PageInfo['Node'].nodeType) }

        if ($Click -le 0) { return $_ }

        $Command = Get-DOM.getBoxModel $SessionId
        $Command.params = @{
            nodeId = $CdpPage.PageInfo['Node'].nodeId
        }
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        if ($Response.error) { throw 'Could not get box model. {0}' -f "$($Response.error)" }

        # Disable dom events now that we don't need nodes anymore.
        $Command = Get-DOM.disable $CdpPage.TargetInfo.SessionId
        $CdpServer.SendCommand($Command)

        $CdpPage.PageInfo['BoxModel'] = $Response.result.model

        if ($TopLeft) {
            $PixelX = $CdpPage.PageInfo['BoxModel'].content[0] + $OffsetX
            $PixelY = $CdpPage.PageInfo['BoxModel'].content[1] + $OffsetY
        } else {
            $PixelX = $CdpPage.PageInfo['BoxModel'].content[0] + ($CdpPage.PageInfo['BoxModel'].width / 2) + $OffsetX
            $PixelY = $CdpPage.PageInfo['BoxModel'].content[1] + ($CdpPage.PageInfo['BoxModel'].height / 2) + $OffsetY
        }

        $Command = Get-Input.dispatchMouseEvent $SessionId 'mousePressed' $PixelX $PixelY 'left'
        $Command.params.clickCount = $Click

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpPage.ResetLoadingState()
        }

        $CommandIds = @(
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            $Command.params.type = 'mouseReleased'
            Start-Sleep -Milliseconds $Delay # if we send click too fast it can fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        )

        foreach ($Id in $CommandIds) {
            $History = $CdpServer.SharedState.CommandHistory[$Id]
            $History.CommandReady.Wait()
            $History.CommandReady.Dispose()
            $History.CommandReady = $null
        }

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpServer.WaitForPageLoad($CdpPage, $Timeout)
        }

        $_
    }
}

function Invoke-CdpInputSendKeys {
    <#
        .SYNOPSIS
        Sends keys to a session
        .PARAMETER Keys
        String to send.
        Include "$([char]13)" to press enter at any given point in the string.
        .EXAMPLE
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys "Hello World$([char]13)"
        .PARAMETER BringToFront
        Attemps to brings page to front once before sending keys.
        .PARAMETER Delay
        Time in ms between sending each key command.
        .PARAMETER ExpectNavigation
        Resets loading state of main page inorder to wait for the next page on click.
        .PARAMETER Timeout
        Max time in ms to wait for expected navigation before throwing an error.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Keys,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0,
        [Parameter(ParameterSetName = 'Navigation')]
        [switch]$ExpectNavigation,
        [Parameter(ParameterSetName = 'Navigation')]
        [int]$Timeout = 60000
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Input.DispatchKeyEvent $SessionId $null

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpPage.ResetLoadingState()
        }

        $CommandIds = foreach ($Char in $Keys[0..($Keys.Length - 1)]) {
            $Command.params.text = $Char
            Start-Sleep -Milliseconds $Delay # if we send keys too fast it can fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        }

        foreach ($Id in $CommandIds) {
            $History = $CdpServer.SharedState.CommandHistory[$Id]
            $History.CommandReady.Wait()
            $History.CommandReady.Dispose()
            $History.CommandReady = $null
        }

        if ($PSCmdlet.ParameterSetName.Contains('Navigation')) {
            $CdpServer.WaitForPageLoad($CdpPage, $Timeout)
        }

        $_
    }
}

function Invoke-CdpPageNavigate {
    <#
        .SYNOPSIS
        Navigates and automatically waits for the page to load with Page.lifecycleEvent.load and FrameStoppedLoading
        Also waits for frames to load if they are present
        .PARAMETER Timeout
        Max amount of time to wait for page to load before throwing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$Timeout = 60000
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $CdpPage.ResetLoadingState()
        $CdpPage.RuntimeReady.Reset()
        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            $CdpFrame.Value.Dispose()
        }
        $CdpPage.Frames.Clear()

        $Command = Get-Page.navigate $SessionId $Url
        $null = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpServer.WaitForPageLoad($CdpPage, $Timeout)

        $_
    }
}

function Invoke-CdpRuntimeAddBinding {
    <#
        .SYNOPSIS
        Adds a binding object to the browser
        .PARAMETER Name
        Name of the object to use in javascript - window.Name(json);
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Name
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Runtime.addBinding $SessionId $Name
        $CdpServer.SendCommand($Command)

        $_
    }
}

function Invoke-CdpRuntimeEvaluate {
    <#
        .SYNOPSIS
        Run javascript on the browser and return the responses in:
        $CdpPage.PageInfo['EvaluateResult'] = $Response.result.result
        $CdpPage.PageInfo['EvaluateResponse'] = $Response
        .PARAMETER Expression
        The javascript expression to run.
        .PARAMETER AwaitPromise
        Use if the Expression includes a promise that needs to be awaited.

        .EXAMPLE
        This returns after ~3-4 seconds rather than 2+2+2=6 seconds
        If AwaitPromise was not used, Invoke-CdpRuntimeEvaluate will return immediately with $Result.result.result = javascript promise object.

        $Expression = @'
function timedPromise(name, delay) {
    return new Promise(resolve => {
        setTimeout(() => {
            resolve(`${name} resolved`);
        }, delay);
    });
}

async function awaitMultiplePromises() {
    const promise1 = timedPromise("Promise 1", 2000);
    const promise2 = timedPromise("Promise 2", 2000);
    const promise3 = timedPromise("Promise 3", 2000);

    const results = await Promise.all([promise1, promise2, promise3]);

    const displayBox = document.querySelector("[id=textInput]");
    displayBox.value = results;

    return 'Promise was awaited.'
}

awaitMultiplePromises();
'@
    $StartTime = Get-Date
    $Result = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage -Expression $Expression -AwaitPromise
    $EndTime = Get-Date
    ($EndTime - $StartTime).TotalSeconds
    $Result.result.result

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Expression,
        [switch]$AwaitPromise
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Runtime.evaluate $SessionId $Expression
        $CdpPage.RuntimeReady.Wait()
        $Command.params.uniqueContextId = "$($CdpPage.PageInfo['RuntimeUniqueId'])"
        if ($AwaitPromise) { $Command.params.awaitPromise = $true }
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpPage.PageInfo['EvaluateResult'] = $Response.result.result
        $CdpPage.PageInfo['EvaluateResponse'] = $Response

        $_
    }
}

function New-CdpPage {
    <#
        .SYNOPSIS
        Creates a new tab target and enables Page events, PageLifeCycle events, and Runtime.
        .PARAMETER NewWindow
        Creates a new browser context and tab.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [Parameter(ParameterSetName = 'ByPage')]
        [CdpPage]$CdpPage,
        [Parameter(ValueFromPipeline, Position = 0)]
        [Parameter(ParameterSetName = 'ByServer')]
        [CdpServer]$CdpServer,
        [string]$Url = 'about:blank',
        [switch]$NewWindow
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByPage') { $CdpServer = $CdpPage.CdpServer }

        if ($NewWindow) {
            $Command = Get-Target.createBrowserContext
            $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        }

        $Command = Get-Target.createTarget $Url
        if ($NewWindow) {
            $Command.params.newWindow = $true
            $Command.params.browserContextId = $Response.result.browserContextId
        } else {
            $Command.params.browserContextId = $CdpPage.TargetInfo['BrowserContextId']
        }

        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
        $CdpPage = $CdpServer.GetPageByTargetId($Response.result.targetId)

        $CdpServer.SetupNewPage($CdpPage)

        $CdpPage
    }
}

function Start-CdpServer {
    <#
        .SYNOPSIS
        Starts the CdpServer by launching the browser process, initializing the event handlers, and starting the message reader, processor, and writer threads.
        .PARAMETER StartPage
        The URL of the page to load when the browser starts.
        .PARAMETER UserDataDir
        The directory to use for the browser's user data profile. This should be a unique directory for each instance of the server to avoid conflicts.
        .PARAMETER BrowserArgs
        Commandline args for chromium.
        Must NOT include --user-data-dir=. This is added by UserDataDir parameter.
        Must NOT include --remote-debugging-pipe and --remote-debugging-io-pipe if using pipes.
        .PARAMETER BrowserPath
        The path to the browser executable to launch
        .PARAMETER AdditionalThreads
        Sets the max runspaces the pool can use + 3.
        Default runspacepool uses 3min and 3max threads for MessageReader, MessageProcessor, MessageWriter
        A number higher than 0 increases the maximum runspaces for the pool.

        More MessageProcessor can be started with $CdpServer.MessageProcessor()
        These will be queued forever if the max number of runspaces are exhausted in the pool.
        .PARAMETER Callbacks
        A hashtable of scriptblocks to be invoked for specific events. The keys should be the event names without the domain prefix and preceeded by 'On'. For example:
        @{
            OnLoadEventFired = { param($Response) $Response.params }
        }
        .PARAMETER DisableDefaultEvents
        This stops targets from being auto attached and auto discovered.
        .PARAMETER StreamOutput
        This is the (Get-Host)/$Host Console which runspacepool streams will output to.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'DefaultArgs')]
        [string]$StartPage,
        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'DefaultArgs')]
        [Parameter(ParameterSetName = 'UserArgs')]
        [ValidateScript({ Test-Path $_ -PathType Container -IsValid })]
        [string]$UserDataDir,
        [Parameter(ParameterSetName = 'UserArgs')]
        [string[]]$BrowserArgs,
        [Parameter(ParameterSetName = 'UserArgs')]
        [System.Management.Automation.Runspaces.InitialSessionState]$State,
        [Parameter(Mandatory)]
        [string]$BrowserPath,
        [ValidateScript({ $_ -ge 0 })]
        [int]$AdditionalThreads = ([int]$env:NUMBER_OF_PROCESSORS * 2),
        [hashtable]$Callbacks,
        [switch]$DisableDefaultEvents,
        [object]$StreamOutput
    )

    $LockFile = Join-Path -Path $UserDataDir -ChildPath 'lockfile'
    if (Test-Path -Path $LockFile -PathType Leaf) { throw 'Browser is already open. Please close it and run Start-CdpServer again.' }

    if ($PSCmdlet.ParameterSetName -eq 'DefaultArgs') {
        $BrowserArgs = @(
            ('--user-data-dir="{0}"' -f $UserDataDir)
            '--no-first-run'
            $StartPage
        ) | Where-Object { $_ -ne '' -and $null -ne $_ }
    } else {
        $BrowserArgs += (' --user-data-dir="{0}"' -f $UserDataDir)
    }

    $ConsoleHost = if ($StreamOutput) { $StreamOutput } else { (Get-Host) }
    $CdpServer = New-UnboundClassInstance CdpServer -arguments $BrowserPath, $ConsoleHost, $BrowserArgs, $AdditionalThreads, $Callbacks, $State

    if ($PSBoundParameters.ContainsKey('Debug')) {
        $CdpServer.SharedState.DebugPreference = 'Continue'
    }

    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $CdpServer.SharedState.VerbosePreference = 'Continue'
    }

    $CdpServer.StartMessageReader()
    $CdpServer.StartMessageProcessor()
    $CdpServer.StartMessageWriter()

    if (!$DisableDefaultEvents) {
        $CdpServer.EnableDefaultEvents()
    }

    # Should only be used at startup since there is only one page
    do {
        foreach ($Target in $CdpServer.SharedState.Targets.GetEnumerator()) {
            break
        }
        Start-Sleep -Milliseconds 1
    } while (!$Target)
    $CdpPage = $CdpServer.SharedState.Targets[$Target.Value.TargetId]

    $CdpServer.SetupNewPage($CdpPage)

    $CdpPage
}

function Stop-CdpServer {
    <#
        .SYNOPSIS
        Disposes the Server Pipes, Threads, ChromeProcess, and RunspacePool
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [CdpPage]$CdpPage,
        [Parameter(ValueFromPipeline, Position = 0)]
        [CdpServer]$CdpServer
    )

    process {
        if ($CdpPage) { $CdpServer = $CdpPage.CdpServer }
        $CdpServer.Stop()
    }
}

function Test-CdpSelector {
    <#
        .SYNOPSIS
        Returns nodes for exploring if selectors are found.
        .PARAMETER FilterScript
        The scriptblock that will filter find valid nodes.
        Valid properties are:

        NodeId
        NodeType
        ParentId
        BackendNodeId
        NodeValue*
        NodeName*
        LocalName
        Attributes*
        FrameId
        AttributesString
        DocumentURL

        *The most common selectors
        NodeValue = any text on the page
        NodeName = element tag name
        Attributes = attributes for the tag such as:
            Name = id, Value = theId
            Name = autofocus

        .EXAMPLE
        $FilterScript = {
            $_.NodeName -eq '#text' -and
            $_.NodeValue -eq 'Woo woo'
        }

        $FilterScript = {
            $_.NodeName -eq 'a'
        }
        $Index = 5

        $FilterScript = {
            $_.NodeName -eq 'button'
        }
        $Index = 0

        $FilterScript = {
            $_.NodeValue -eq 'submit'
        }

        .PARAMETER Index
        The nth number of the Nodes found by FilterScript

        .PARAMETER All
        Returns all found nodes for viewing

        .PARAMETER EnableDomEvents
        Keeps DOM events active
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$CdpPage,
        [scriptblock]$FilterScript,
        [int]$Index = 0,
        [switch]$All,
        [switch]$EnableDomEvents,
        [int]$Timeout = 5000
    )

    begin {
        $PollInterval = 100
        $Sequence = 0
    }

    process {
        $CdpServer = $CdpPage.CdpServer
        $Command = Get-DOM.getDocument $CdpPage.TargetInfo.SessionId

        $EndTime = (Get-Date).AddMilliseconds($Timeout)

        while ($true) {
            $Sequence++

            $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
            $Root = $Response.result.root
            $Document = ConvertTo-FlatNode -Node $Root
            $Nodes = $Document | Where-Object { $_.TopParentName -ne 'HEAD' } | Where-Object -FilterScript $FilterScript

            if ($Nodes) {
                break
            } elseif (($EndTime - (Get-Date)).TotalMilliseconds -lt 0) {
                throw ('No node found in allotted time with FilterScript: {0}' -f $FilterScript)
            } else {
                Start-Sleep -Milliseconds ([math]::Min(($PollInterval * $Sequence), 1000))
            }
        }

        if (!$EnableDomEvents) {
            $Command = Get-DOM.disable $CdpPage.TargetInfo.SessionId
            $CdpServer.SendCommand($Command)
        }

        if ($Nodes -and $All) { $Nodes }
        else { $Nodes[$Index] }
    }
}

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

