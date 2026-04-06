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
        if (!$this.SharedState.Sessions.TryGetValue($SessionId, [ref]$CdpPage)) {
            $CdpPageReady = $this.SharedState.EventHandler.NewSessions.GetOrAdd($SessionId, [System.Threading.ManualResetEventSlim]::new($false))
            $CdpPageReady.Wait()
        }
        return $this.SharedState.Sessions[$SessionId]
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
        $AvailableTargetId = $null
        do {
            $TargetCreatedEvents = $this.SharedState.MessageHistory.GetEnumerator() | Sort-Object -Property Key | Where-Object {
                $_.Value.method -eq 'Target.targetCreated'
            }

            $AvailableTargetId = foreach ($TargetId in $TargetCreatedEvents.Value.params.targetInfo.targetId) {
                $Target = $this.SharedState.Targets.GetEnumerator() | Where-Object { $_.Value.TargetId -eq $TargetId }
                if ($Target) {
                    $TargetId
                    break
                }
            }
        } while (!$AvailableTargetId)
        return $this.SharedState.Targets[$AvailableTargetId]
    }

    [void]WaitForPageLoad([CdpPage]$CdpPage) {
        [System.Threading.SpinWait]::SpinUntil({
                $CdpPage.LoadingState['Load'] -and
                $CdpPage.LoadingState['FrameStoppedLoading']
            }
        )

        # Wait for all child frames to have executioncontext
        if ($CdpPage.Frames.Count -gt 0) {
            $CdpPage.Frames.Values.RuntimeReady.Wait()
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

        if ($CdpPage.Frames.Count -gt 0) {
            $CdpPage.Frames.Values.RuntimeReady.Wait()
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
