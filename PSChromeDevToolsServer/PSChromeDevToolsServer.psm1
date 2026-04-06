
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
        MessageProcessor = $null
        MessageProcessorHandle = $null
        MessageWriter = $null
        MessageWriterHandle = $null
    }
    [System.Collections.Concurrent.ConcurrentDictionary[string, string]]$CommandHistory = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()

    CdpServer([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks) {
        $this.Init($BrowserPath, $StreamOutput, $BrowserArgs, $AdditionalThreads, $Callbacks, $null)
    }

    CdpServer([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks, [System.Management.Automation.Runspaces.InitialSessionState]$State) {
        $this.Init($BrowserPath, $StreamOutput, $BrowserArgs, $AdditionalThreads, $Callbacks, $State)
    }

    hidden [void]Init([string]$BrowserPath, [object]$StreamOutput, [string[]]$BrowserArgs, [int]$AdditionalThreads, [hashtable]$Callbacks, [System.Management.Automation.Runspaces.InitialSessionState]$State) {
        $this.SharedState = [System.Collections.Generic.Dictionary[string, object]]::new()

        $this.SharedState.IO = @{
            PipeWriter = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::Out, [System.IO.HandleInheritability]::Inheritable)
            PipeReader = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::In, [System.IO.HandleInheritability]::Inheritable)
            UnprocessedResponses = [System.Collections.Concurrent.BlockingCollection[object]]::new()
            CommandQueue = [System.Collections.Concurrent.BlockingCollection[object]]::new()
        }

        $this.SharedState.CdpServer = $this
        $this.SharedState.MessageHistory = [System.Collections.Concurrent.ConcurrentDictionary[version, object]]::new()
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
            GetPageBySessionId = $this.CreateDelegate($this.GetPageBySessionId)
            GetPageByTargetId = $this.CreateDelegate($this.GetPageByTargetId)
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
                        $SplitResponse.ForEach({
                                $SharedState.IO.UnprocessedResponses.Add($_)
                            }
                        )
                        $StringBuilder.Clear()
                    }
                }
            }
        )
        $this.Threads.MessageReaderHandle = $this.Threads.MessageReader.BeginInvoke()
    }

    [void]StartMessageProcessor() {
        $this.Threads.MessageProcessor = [powershell]::Create()
        $this.Threads.MessageProcessor.RunspacePool = $this.RunspacePool
        $null = $this.Threads.MessageProcessor.AddScript({
                if ($SharedState.DebugPreference) { $DebugPreference = $SharedState.DebugPreference }
                if ($SharedState.VerbosePreference) { $VerbosePreference = $SharedState.VerbosePreference }

                $ResponseIndex = 1

                foreach ($Response in $SharedState.IO.UnprocessedResponses.GetConsumingEnumerable()) {
                    $LastCommandId = if ($Response.id) {
                        $Response.id
                    } else {
                        $SharedState.CommandId
                    }

                    do {
                        $SucessfullyAdded = if ($Response.id) {
                            $SharedState.MessageHistory.TryAdd([version]::new($LastCommandId, 0), $Response)
                        } else {
                            $SharedState.MessageHistory.TryAdd([version]::new($LastCommandId, $ResponseIndex++), $Response)
                        }
                    } while (!$SucessfullyAdded)

                    # $Start = Get-Date
                    $SharedState.EventHandler.ProcessEvent($Response)
                    # $End = Get-Date
                    # Write-Debug ('{0} {1} Processing Time: {2} ms' -f $Response.id, $Response.method, ($End - $Start).TotalMilliseconds)
                }
            }
        )
        $this.Threads.MessageProcessorHandle = $this.Threads.MessageProcessor.BeginInvoke()
    }

    [void]StartMessageWriter() {
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
        if ($this.Threads.MessageProcessorHandle) {
            $this.Threads.MessageProcessor.EndInvoke($this.Threads.MessageProcessorHandle)
            $this.Threads.MessageProcessor.Dispose()
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
        $null = $this.CommandHistory.TryAdd($CommandId, $Command.method)
        $Command.id = $CommandId
        $JsonCommand = $Command | ConvertTo-Json -Depth 10 -Compress
        $CommandBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonCommand) + 0
        $this.SharedState.IO.CommandQueue.Add($CommandBytes)
        $Response = switch ($WaitForResponse) {
            ([WaitForResponse]::None) {
                $null
                break
            }
            ([WaitForResponse]::Message) {
                $AwaitedMessage = $null
                [System.Threading.SpinWait]::SpinUntil({ $this.SharedState.MessageHistory.TryGetValue([version]::new($CommandId, 0), [ref]$AwaitedMessage) })
                $AwaitedMessage
                break
            }
            ([WaitForResponse]::CommandId) {
                $CommandId
                break
            }
        }

        return $Response
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

        [System.Threading.SpinWait]::SpinUntil({ $this.SharedState.Targets.Count -ne 0 })

        $CdpPage = $this.GetFirstAvailableCdpPage()

        $this.SetupNewPage($CdpPage)
    }

    [object]ShowMessageHistory() {
        $CommandSnapshot = @{}
        $Commands = $this.CommandHistory.GetEnumerator()
        foreach ($Message in $Commands) {
            $CommandSnapshot[[int]$Message.Key] = $Message.Value
        }
        $Events = $this.SharedState.MessageHistory.GetEnumerator() | Sort-Object -Property Key | Select-Object -Property @(
            @{Name = 'id'; Expression = { $_.Value.id } },
            @{Name = 'method'; Expression = { if ($_.Value.method) { $_.Value.method } else { $CommandSnapshot[[int]$_.Value.id] } } },
            @{Name = 'error'; Expression = { $_.Value.error } },
            @{Name = 'sessionId'; Expression = { $_.Value.sessionId } },
            @{Name = 'params'; Expression = { $_.Value.params } },
            @{Name = 'result'; Expression = { $_.Value.result } }
        )
        return $Events
    }

    [CdpPage]GetFirstAvailableCdpPage() {
        $AvailableTarget = $null
        do {
            $TargetCreatedEvents = $this.SharedState.MessageHistory.GetEnumerator() | Sort-Object -Property Key | Where-Object {
                $_.Value.method -eq 'Target.targetCreated'
            }

            $AvailableTarget = foreach ($TargetId in $TargetCreatedEvents.Value.params.targetInfo.targetId) {
                $Target = $this.SharedState.Targets.GetEnumerator() | Where-Object { $_.Value.TargetId -eq $TargetId }
                $Target
                if ($Target) { break }
            }
        } while (!$AvailableTarget)
        return $this.GetPageByTargetId($AvailableTarget.Value.TargetId)
    }

    [void]WaitForPageLoad([CdpPage]$CdpPage) {
        if ($CdpPage.LoadingState['FrameNavigated']) {
            [System.Threading.SpinWait]::SpinUntil({
                    $CdpPage.LoadingState['FrameNavigated'] -or
                    $CdpPage.LoadingState['Page.frameStoppedLoading']
                }
            )
        }

        [System.Threading.SpinWait]::SpinUntil({
                $CdpPage.LoadingState['Load']
            }
        )

        # Wait for all child frames to have executioncontext
        if ($CdpPage.Frames.Count -gt 0) {
            [System.Threading.SpinWait]::SpinUntil({
                    $RuntimeUniqueIdSnapshot = $CdpPage.Frames.Values.PageInfo.RuntimeUniqueId
                    $null -notin $RuntimeUniqueIdSnapshot
                }
            )
        }
    }

    [void]SetupNewPage([CdpPage]$CdpPage) {
        $SessionId = $null
        [System.Threading.SpinWait]::SpinUntil({ $null = $CdpPage.TargetInfo.TryGetValue('SessionId', [ref]$SessionId); $null -ne $SessionId })

        $Command = Get-Runtime.enable $SessionId
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        $RuntimeUniqueId = $null
        [System.Threading.SpinWait]::SpinUntil({ $null = $CdpPage.PageInfo.TryGetValue('RuntimeUniqueId', [ref]$RuntimeUniqueId); $null -ne $RuntimeUniqueId })

        $Command = Get-Page.enable $SessionId
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        $Command = Get-Page.setLifecycleEventsEnabled $SessionId $true
        $null = $this.SendCommand($Command, [WaitForResponse]::Message)

        if ($CdpPage.Frames.Count -gt 0) {
            [System.Threading.SpinWait]::SpinUntil({
                    $RuntimeUniqueIdSnapshot = $CdpPage.Frames.Values.PageInfo.RuntimeUniqueId
                    $null -notin $RuntimeUniqueIdSnapshot
                }
            )
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


function Get-DOM.describeNode {
    param($SessionId, $ObjectId)
    @{
        method = 'DOM.describeNode'
        sessionId = $SessionId
        params = @{
            objectId = "$ObjectId"
        }
    }
}
function Get-DOM.getBoxModel {
    param($SessionId, $ObjectId)
    @{
        method = 'DOM.getBoxModel'
        sessionId = $SessionId
        params = @{
            objectId = "$ObjectId"
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
                # 	type = 'other'
                # 	exclude = $true
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
                # 	type = 'other'
                # 	exclude = $true
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

    process {
        $Start = Get-Date
        do {
            $Command = Get-Page.getFrameTree $CdpPage.TargetInfo.SessionId
            $Response = $CdpPage.CdpServer.SendCommand($Command, 1)
            $FramesTree = Get-CdpFrameTree $Response.result.frameTree
            $Match = $FramesTree.url | Select-String -Pattern $Url
            $MatchedFrame = $FramesTree | Where-Object { $_.url -eq $Match.Line }
            $CdpFrame = $CdpPage.Frames.Values | Where-Object { $_.FrameId -eq $MatchedFrame.id }
            if ($CdpFrame) { break }
            Start-Sleep 0
        } while (($Start.AddMilliseconds($Timeout) - (Get-Date)).Milliseconds -gt 0)

        if (!$CdpFrame) { throw ('No frame found using: {0}' -f $Url) }

        [pscustomobject]@{
            CdpPage = $CdpPage
            CdpFrame = $CdpFrame
        }
    }
}

function Invoke-CdpInputClickElement {
    <#
		.SYNOPSIS
		Finds and clicks with element in the center of the box. Clicks from the top left of the element when $TopLeft is switched on.
		.PARAMETER Selector
		Javascript that returns ONE node object
		For example:
		document.querySelectorAll('[name=q]')[0]
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
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Selector,
        [Parameter(ParameterSetName = 'Click')]
        [int]$Click = 0,
        [Parameter(ParameterSetName = 'Click')]
        [int]$OffsetX = 0,
        [Parameter(ParameterSetName = 'Click')]
        [int]$OffsetY = 0,
        [Parameter(ParameterSetName = 'Click')]
        [switch]$TopLeft,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']

        $Command = Get-Runtime.evaluate $SessionId $Selector
        $Command.params.uniqueContextId = "$($CdpPage.PageInfo['RuntimeUniqueId'])"
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpPage.PageInfo['ObjectId'] = $Response.result.result.objectId

        if ($Click -le 0) { return $_ }

        $Command = Get-DOM.describeNode $SessionId $CdpPage.PageInfo.ObjectId
        $Command.params.objectId = $CdpPage.PageInfo['ObjectId']
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        if ($Response.error) {
            throw ('Error describing node: {0}' -f $Response.error.message)
        }

        $CdpPage.PageInfo['Node'] = $Response.result.node
        if ($Response.result.node.nodeType -ne 1) { throw ('Node is not an element. {0}' -f $Response.result.node) }

        $Command = Get-DOM.getBoxModel $SessionId $CdpPage.PageInfo['ObjectId']
        $Command.params.objectId = $CdpPage.PageInfo['ObjectId']
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)
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

        $CommandIdWaiter = @(
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            $Command.params.type = 'mouseReleased'
            Start-Sleep -Milliseconds $Delay # if we send click too fast it will fail to register.
            $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
        )

        [System.Threading.SpinWait]::SpinUntil({
                $CommandResponse = $CommandIdWaiter.Where({ $CdpServer.SharedState.MessageHistory.ContainsKey([version]::new($_, 0)) })
                $CommandResponse.Count -eq 2
            }
        )

        $_
    }
}

function Invoke-CdpInputSendKeys {
    <#
		.SYNOPSIS
		Sends keys to a session
		.PARAMETER Keys
		String to send
		.EXAMPLE
		Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'Hello World'
		.PARAMETER BringToFront
		Attemps to brings page to front once before sending keys.
		.PARAMETER Delay
		Time in ms between sending each key command.
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Keys,
        [switch]$BringToFront,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Delay = 0
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Input.DispatchKeyEvent $SessionId $null

        if ($BringToFront) {
            $CommandFront = Get-Page.bringToFront $SessionId
            $null = $CdpServer.SendCommand($CommandFront, [WaitForResponse]::Message)
        }

        $CommandIdWaiter = $Keys.ToCharArray().ForEach({
                $Command.params.text = $_
                Start-Sleep -Milliseconds $Delay # if we send keys too fast it will fail to register.
                $CdpServer.SendCommand($Command, [WaitForResponse]::CommandId)
            }
        )

        $KeyCount = $Keys.ToCharArray().Count
        [System.Threading.SpinWait]::SpinUntil({
                $CommandResponse = $CommandIdWaiter.Where({ $CdpServer.SharedState.MessageHistory.ContainsKey([version]::new($_, 0)) })
                $CommandResponse.Count -eq $KeyCount
            }
        )

        $_
    }
}

function Invoke-CdpPageNavigate {
    <#
		.SYNOPSIS
		Navigates and automatically waits for the page to load with Page.lifecycleEvent.load and FrameStoppedLoading
		Also waits for frames to load if they are present
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Url
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $OldRuntimeUniqueId = $CdpPage.PageInfo['RuntimeUniqueId']

        $CdpPage.ResetLoadingState()
        $CdpPage.Frames.Values.ForEach({ $_.ResetLoadingState() })

        $Command = Get-Page.navigate $SessionId $Url
        $null = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $NewRuntimeUniqueId = $null
        if ($null -ne $OldRuntimeUniqueId) {
            [System.Threading.SpinWait]::SpinUntil({
                    $null = $CdpPage.PageInfo.TryGetValue('RuntimeUniqueId', [ref]$NewRuntimeUniqueId)
                    $NewRuntimeUniqueId -ne $OldRuntimeUniqueId
                }
            )
        }

        $CdpServer.WaitForPageLoad($CdpPage)

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
            $Command.params.browserContextId = $CdpPage.BrowserContextId
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
        [int]$AdditionalThreads = 0,
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

    $CdpServer.GetFirstAvailableCdpPage()
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
