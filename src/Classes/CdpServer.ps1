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

                    while ($SharedState.MessageHistory.Count -gt 300) {
                        $SharedState.MessageHistory.TryDequeue([ref]$null)
                    }
                    $SharedState.MessageHistory.Enqueue($Response)
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

    [void]WaitForPageLoad([CdpPage]$CdpPage) {
        $CdpPage.LoadingState['Load'].Wait()
        $CdpPage.LoadingState['FrameStoppedLoading'].Wait()
        $CdpPage.RuntimeReady.Wait()

        # Wait for all child frames to load and have executioncontext
        foreach ($CdpFrame in $CdpPage.Frames.GetEnumerator()) {
            $CdpFrame.Value.LoadingState['Load'].Wait()
            $CdpFrame.Value.LoadingState['FrameStoppedLoading'].Wait()
            $CdpFrame.Value.RuntimeReady.Wait()
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
