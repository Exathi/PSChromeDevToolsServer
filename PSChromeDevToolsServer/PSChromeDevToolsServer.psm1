# $global:DebugPreference = 'Continue'

$script:Powershell = $null

function Initialize {
	$script:Powershell = [powershell]::Create()
	$script:Powershell.AddScript( {
			function New-UnboundClassInstance ([Type] $type, [object[]] $arguments) {
				[activator]::CreateInstance($type, $arguments)
			}
		}.Ast.GetScriptBlock()
	).Invoke()
	$script:Powershell.Commands.Clear()
}

function New-UnboundClassInstance ([Type] $type, [object[]] $arguments = $null) {
	if ($null -eq $script:Powershell) { Initialize }

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


class CdpPage {
	[string]$TargetId
	[string]$Url
	[string]$Title
	[string]$SessionId
	[int]$ProcessId

	CdpPage() {}

	CdpPage($TargetId, $Url, $Title) {
		$this.TargetId = $TargetId
		$this.Url = $Url
		$this.Title = $Title
	}

	CdpPage($TargetId, $Url, $Title, $SessionId) {
		$this.SessionId = $SessionId
		$this.TargetId = $TargetId
		$this.Url = $Url
		$this.Title = $Title
	}

	[bool]$IsLoading = $false
	[int]$DomContentEventFired = 0
	[int]$LoadEventFired = 0
	[int]$FrameStoppedLoading = 0
	[int]$FrameStartedLoading = 0
	[System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Frames = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
	[string]$RuntimeUniqueId
	[string]$ObjectId
	[object]$Node
	[object]$BoxModel
}


# [NoRunspaceAffinity()]
class CdpEventHandler {
	[System.Collections.Generic.Dictionary[string, object]]$SharedState
	[hashtable]$EventHandlers

	CdpEventHandler([System.Collections.Generic.Dictionary[string, object]]$SharedState) {
		$this.SharedState = $SharedState
		$this.InitializeHandlers()
	}

	hidden [void]InitializeHandlers() {
		$this.EventHandlers = @{
			'Page.domContentEventFired' = $this.DomContentEventFired
			'Page.frameAttached' = $this.FrameAttached
			'Page.frameDetached' = $this.FrameDetached
			'Page.frameNavigated' = $this.FrameNavigated
			'Page.loadEventFired' = $this.LoadEventFired
			'Page.frameRequestedNavigation' = $this.FrameRequestedNavigation
			'Page.frameStartedLoading' = $this.FrameStartedLoading
			'Page.frameStartedNavigating' = $this.FrameStartedNavigating
			'Page.frameStoppedLoading' = $this.FrameStoppedLoading
			'Page.navigatedWithinDocument' = $this.NavigatedWithinDocument
			'Target.targetCreated' = $this.TargetCreated
			'Target.targetDestroyed' = $this.TargetDestroyed
			'Target.targetInfoChanged' = $this.TargetInfoChanged
			'Target.attachedToTarget' = $this.AttachedToTarget
			'Target.detachedFromTarget' = $this.DetachedFromTarget
			'Runtime.bindingCalled' = $this.BindingCalled
			'Runtime.executionContextsCleared' = $this.ExecutionContextsCleared
			'Runtime.executionContextCreated' = $this.ExecutionContextCreated
		}
	}

	[void]ProcessEvent($Response) {
		if ($null -eq $Response.method) { return }
		$handler = $this.EventHandlers[$Response.method]
		if ($handler) {
			$handler.Invoke($Response)
		}
		# else {
		# 	Write-Debug ('Unprocessed Event: ({0})' -f $Response.method)
		# }
	}

	hidden [void]DomContentEventFired($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		$CdpPage.DomContentEventFired++
		if ($CdpPage.LoadEventFired -eq $CdpPage.DomContentEventFired) {
			$CdpPage.IsLoading = $false
		}

		$Callback = $this.SharedState.Callbacks['OnDomContentEventFired']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameAttached($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage) {
			$CdpPage.Frames.TryAdd($Response.params.frameId,
				[pscustomobject]@{
					FrameStartedLoading = 0
					FrameStoppedLoading = 0
					FrameId = $Response.params.frameId
					ParentFrameId = $Response.params.parentFrameId
					SessionId = $Response.sessionId
					IsLoading = $false
				}
			)
		}

		$Callback = $this.SharedState.Callbacks['OnFrameAttached']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameDetached($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage -and $Response.params.reason -eq 'remove') {
			$null = $CdpPage.Frames.TryRemove($Response.params.frameId, [ref]$null)
		}

		$Callback = $this.SharedState.Callbacks['OnFrameDetached']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameNavigated($Response) {
		# Write-Debug ('Frame Navigated: ({0})' -f ($Response | ConvertTo-Json -Depth 10))

		$Callback = $this.SharedState.Callbacks['OnFrameNavigated']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]LoadEventFired($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		$CdpPage.LoadEventFired++
		if ($CdpPage.LoadEventFired -eq $CdpPage.DomContentEventFired) {
			$CdpPage.IsLoading = $false
		}
		$Callback = $this.SharedState.Callbacks['OnLoadEventFired']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameRequestedNavigation($Response) {
		# Write-Debug ('Frame Requested Navigation: ({0})' -f ($Response | ConvertTo-Json -Depth 10))

		$Callback = $this.SharedState.Callbacks['OnFrameRequestedNavigation']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameStartedLoading($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage.TargetId -eq $Response.params.frameId) {
			$CdpPage.FrameStartedLoading++
		} else {
			$Frame = $null
			if ($CdpPage.Frames.TryGetValue($Response.params.frameId, [ref]$Frame)) {
				$Frame.IsLoading = $true
				$Frame.FrameStartedLoading++
			}
			# Write-Debug ('Start CdpPage: ({0})' -f ($CdpPage | ConvertTo-Json -Depth 10))
			# Write-Debug ('Start Frame: ({0})' -f ($Frame | ConvertTo-Json -Depth 10))
		}

		$Callback = $this.SharedState.Callbacks['OnFrameStartedLoading']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameStartedNavigating($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		$CdpPage.IsLoading = $true
		# Write-Debug ('Frame Started Navigating: ({0})' -f ($Response | ConvertTo-Json -Depth 10))

		$Callback = $this.SharedState.Callbacks['OnFrameStartedNavigating']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]FrameStoppedLoading($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage.TargetId -eq $Response.params.frameId) {
			$CdpPage.FrameStoppedLoading++
		} else {
			$Frame = $null
			if ($CdpPage.Frames.TryGetValue($Response.params.frameId, [ref]$Frame)) {
				$Frame.FrameStoppedLoading++
				$Frame.IsLoading = $false
			}
			# Write-Debug ('Stop CdpPage: ({0})' -f ($CdpPage | ConvertTo-Json -Depth 10))
			# Write-Debug ('Stop Frame: ({0})' -f ($Frame | ConvertTo-Json -Depth 10))
		}

		$Callback = $this.SharedState.Callbacks['OnFrameStoppedLoading']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]NavigatedWithinDocument($Response) {
		# Write-Debug ('Navigated Within Document: ({0})' -f ($Response | ConvertTo-Json -Depth 10))

		$Callback = $this.SharedState.Callbacks['OnNavigatedWithinDocument']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]TargetCreated($Response) {
		$Target = $Response.params.targetInfo
		$CdpPage = [CdpPage]::new($Target.targetId, $Target.Url, $Target.Title, $Response.params.sessionId)
		$this.SharedState.Targets.Add($CdpPage)

		$Callback = $this.SharedState.Callbacks['OnTargetCreated']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]TargetDestroyed($Response) {
		$CdpPage = $this.GetPageByTargetId($Response.params.targetId)
		if ($CdpPage) {
			$null = $this.SharedState.Targets.Remove($CdpPage)
		}

		$Callback = $this.SharedState.Callbacks['OnTargetDestroyed']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]TargetInfoChanged($Response) {
		$Target = $Response.params.targetInfo
		$CdpPage = $this.GetPageByTargetId($Target.targetId)
		if ($CdpPage) {
			$CdpPage.Url = $Target.Url
			$CdpPage.Title = $Target.Title
			$CdpPage.ProcessId = $Target.pid
			# $CdpPage.Frames.Clear()
		}

		$Callback = $this.SharedState.Callbacks['OnTargetInfoChanged']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]AttachedToTarget($Response) {
		$Target = $Response.params.targetInfo
		$CdpPage = $this.GetPageByTargetId($Target.targetId)
		$CdpPage.sessionId = $Response.params.sessionId

		$Callback = $this.SharedState.Callbacks['OnAttachedToTarget']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]DetachedFromTarget($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.params.sessionId)
		$CdpPage.sessionId = $null

		$Callback = $this.SharedState.Callbacks['OnDetachedFromTarget']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]BindingCalled($Response) {
		$Callback = $this.SharedState.Callbacks['OnBindingCalled']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]ExecutionContextsCleared($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage) {
			$CdpPage.RuntimeUniqueId = $null
		}

		$Callback = $this.SharedState.Callbacks['OnExecutionContextsCleared']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [void]ExecutionContextCreated($Response) {
		$CdpPage = $this.GetPageBySessionId($Response.sessionId)
		if ($CdpPage) {
			$CdpPage.RuntimeUniqueId = $Response.params.context.uniqueId
		}

		$Callback = $this.SharedState.Callbacks['OnExecutionContextCreated']
		if ($Callback) {
			$Callback.Invoke($Response)
		}
	}

	hidden [CdpPage]GetPageBySessionId([string]$SessionId) {
		return $this.SharedState.Targets.Find({ param($Page) $Page.SessionId -eq $SessionId })
	}

	hidden [CdpPage]GetPageByTargetId([string]$TargetId) {
		return $this.SharedState.Targets.Find({ param($Page) $Page.TargetId -eq $TargetId })
	}
}

# [NoRunspaceAffinity()]
class CdpServer {
	[System.Collections.Generic.Dictionary[string, object]]$SharedState = [System.Collections.Generic.Dictionary[string, object]]::new()
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

	CdpServer($StartPage, $UserDataDir, $BrowserPath, $StreamOutput) {
		$this.Init($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, 0, $null)
	}

	CdpServer($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, $AdditionalThreads) {
		$this.Init($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, 0, $null)
	}

	CdpServer($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, $AdditionalThreads, $Callbacks) {
		$this.Init($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, $AdditionalThreads, $Callbacks)
	}

	hidden [void]Init($StartPage, $UserDataDir, $BrowserPath, $StreamOutput, $AdditionalThreads, $Callbacks) {
		$this.SharedState = [System.Collections.Generic.Dictionary[string, object]]::new()

		$this.SharedState.IO = @{
			PipeWriter = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::Out, [System.IO.HandleInheritability]::Inheritable)
			PipeReader = [System.IO.Pipes.AnonymousPipeServerStream]::new([System.IO.Pipes.PipeDirection]::In, [System.IO.HandleInheritability]::Inheritable)
			UnprocessedResponses = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
			CommandQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
		}

		$this.SharedState.MessageHistory = [System.Collections.Concurrent.ConcurrentDictionary[version, object]]::new()
		$this.SharedState.CommandId = [ref]::new([int]0)
		$this.SharedState.Targets = [System.Collections.Generic.List[CdpPage]]::new()
		$this.SharedState.Callbacks = [System.Collections.Generic.Dictionary[string, scriptblock]]::new()

		foreach ($Key in $Callbacks.Keys) {
			$this.SharedState.Callbacks[$Key] = $Callbacks[$Key]
		}

		$this.SharedState.Commands = @{
			SendRuntimeEvaluate = $this.CreateDelegate($this.SendRuntimeEvaluate)
			GetPageBySessionId = $this.CreateDelegate($this.GetPageBySessionId)
			GetPageByTargetId = $this.CreateDelegate($this.GetPageByTargetId)
		}

		$this.SharedState.EventHandler = New-UnboundClassInstance -type ([CdpEventHandler]) -arguments @($this.SharedState) #[CdpEventHandler]::new($this.SharedState)

		$State = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
		$State.ImportPSModule("$PSScriptRoot\PSChromeDevToolsServer")
		$RunspaceSharedState = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new('SharedState', $this.SharedState, $null)
		$State.Variables.Add($RunspaceSharedState)
		$State.ThrowOnRunspaceOpenError = $true
		$this.RunspacePool = [RunspaceFactory]::CreateRunspacePool(3, 3 + $AdditionalThreads, $State, $StreamOutput)
		$this.RunspacePool.Open()

		$BrowserArgs = @(
			('--user-data-dir="{0}"' -f $UserDataDir)
			'--no-first-run'
			'--remote-debugging-pipe'
			('--remote-debugging-io-pipes={0},{1}' -f $this.SharedState.IO.PipeWriter.GetClientHandleAsString(), $this.SharedState.IO.PipeReader.GetClientHandleAsString())
			$StartPage
		) | Where-Object { $_ -ne '' -and $_ -ne $null }

		$StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$StartInfo.FileName = $BrowserPath
		$StartInfo.Arguments = $BrowserArgs
		$StartInfo.UseShellExecute = $false

		$this.ChromeProcess = [System.Diagnostics.Process]::Start($StartInfo)

		while (!$this.SharedState.IO.PipeWriter.IsConnected -and !$this.SharedState.IO.PipeReader.IsConnected) {
			Start-Sleep -Milliseconds 50
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
								$SharedState.IO.UnprocessedResponses.Enqueue($_)
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

				$Response = $null
				$IdleTime = 1
				$ResponseIndex = 1

				while ($SharedState.IO.PipeReader.IsConnected -and $SharedState.IO.PipeWriter.IsConnected) {
					while ($SharedState.IO.UnprocessedResponses.TryDequeue([ref]$Response)) {

						$LastCommandId = [System.Threading.Interlocked]::Read([ref]$SharedState.CommandId)
						do {
							$SucessfullyAdded = if ($Response.id) {
								$SharedState.MessageHistory.TryAdd([version]::new($Response.id, 0), $Response)
							} else {
								$SharedState.MessageHistory.TryAdd([version]::new($LastCommandId, $ResponseIndex++), $Response)
							}
						} while (!$SucessfullyAdded)

						# $Start = Get-Date
						$SharedState.EventHandler.ProcessEvent($Response)
						# $End = Get-Date
						# Write-Debug ('{0} {1} Processing Time: {2} ms' -f $Response.id, $Response.method, ($End - $Start).TotalMilliseconds)
					}
					Start-Sleep -Seconds $IdleTime
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

				$CommandBytes = $null
				$IdleTime = 1
				while ($SharedState.IO.PipeReader.IsConnected -and $SharedState.IO.PipeWriter.IsConnected) {
					while ($SharedState.IO.CommandQueue.TryDequeue([ref]$CommandBytes)) {
						$SharedState.IO.PipeWriter.Write($CommandBytes, 0, $CommandBytes.Length)
					}
					Start-Sleep -Seconds $IdleTime
				}
			}
		)
		$this.Threads.MessageWriterHandle = $this.Threads.MessageWriter.BeginInvoke()
	}

	[void]Stop() {
		$this.SharedState.IO.PipeReader.Dispose()
		$this.SharedState.IO.PipeWriter.Dispose()
		while ($this.SharedState.IO.PipeReader.IsConnected -or $this.SharedState.IO.PipeWriter.IsConnected) {
			Start-Sleep -Milliseconds 50
		}
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
		$this.ChromeProcess.Dispose()
		$this.RunspacePool.Dispose()
	}

	[void]SendCommand([hashtable]$Command) {
		$this.SendCommand($Command, $false)
	}

	[object]SendCommand([hashtable]$Command, [bool]$WaitForResponse) {
		# This should be the only place where $this.SharedState.CommandId is incremented.
		$Command.id = [System.Threading.Interlocked]::Increment([ref]$this.SharedState.CommandId)
		$JsonCommand = $Command | ConvertTo-Json -Depth 10 -Compress
		$CommandBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonCommand) + 0
		$this.SharedState.IO.CommandQueue.Enqueue($CommandBytes)
		if ($WaitForResponse) {
			# while (!$this.SharedState.MessageHistory.ContainsKey([version]::new($Command.id, 0))) {
			$AwaitedMessage = $null
			while (!$this.SharedState.MessageHistory.TryGetValue([version]::new($Command.id, 0), [ref]$AwaitedMessage)) {
				Start-Sleep -Milliseconds 50
			}
			return $AwaitedMessage
		}
		return $null
	}

	[CdpPage]GetPageBySessionId([string]$SessionId) {
		return $this.SharedState.Targets.Find({ param($Page) $Page.SessionId -eq $SessionId })
	}

	[CdpPage]GetPageByTargetId([string]$TargetId) {
		return $this.SharedState.Targets.Find({ param($Page) $Page.TargetId -eq $TargetId })
	}

	[void]SendPageEnable([string]$SessionId) {
		$JsonCommand = [CdpCommandPage]::enable($SessionId)
		$this.SendCommand($JsonCommand)
	}

	[void]SendRuntimeEnable([string]$SessionId) {
		$JsonCommand = [CdpCommandRuntime]::enable($SessionId)
		$this.SendCommand($JsonCommand)
	}

	[void]SendRuntimeEvaluate([string]$SessionId, [string]$Expression) {
		$JsonCommand = [CdpCommandRuntime]::evaluate($SessionId, $Expression)
		$this.SendCommand($JsonCommand)
	}

	[void]SendRuntimeAddBinding([string]$SessionId, [string]$Name) {
		$JsonCommand = [CdpCommandRuntime]::addBinding($SessionId, $Name)
		$this.SendCommand($JsonCommand)
	}

	[void]EnableDefaultEvents() {
		$JsonCommand = [CdpCommandTarget]::setDiscoverTargets()
		$this.SendCommand($JsonCommand)

		$JsonCommand = [CdpCommandTarget]::setAutoAttach()
		$this.SendCommand($JsonCommand)

		while (!$this.SharedState.Targets[0].SessionId) {
			Start-Sleep -Milliseconds 50
		}

		$this.SendPageEnable($this.SharedState.Targets[0].SessionId)
		$this.SendRuntimeEnable($this.SharedState.Targets[0].SessionId)
		# $this.SendRuntimeAddBinding($this.SharedState.Targets[0].SessionId, 'PowershellServer')
	}

	[object]ShowMessageHistory() {
		return $this.SharedState.MessageHistory.GetEnumerator() | Sort-Object -Property Key | Select-Object -Property @(
			@{Name = 'id'; Expression = { $_.Value.id } },
			@{Name = 'method'; Expression = { $_.Value.method } },
			@{Name = 'error'; Expression = { $_.Value.error } },
			@{Name = 'sessionId'; Expression = { $_.Value.sessionId } },
			@{Name = 'result'; Expression = { $_.Value.result } },
			@{Name = 'params'; Expression = { $_.Value.params } }
		)
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

class CdpCommandDom {
	static [hashtable]describeNode($SessionId, $ObjectId) {
		return @{
			method = 'DOM.describeNode'
			sessionId = $SessionId
			params = @{
				objectId = "$ObjectId"
			}
		}
	}
	static [hashtable]getBoxModel($SessionId, $ObjectId) {
		return @{
			method = 'DOM.getBoxModel'
			sessionId = $SessionId
			params = @{
				objectId = "$ObjectId"
			}
		}
	}
}

class CdpCommandInput {
	static [hashtable]dispatchKeyEvent($SessionId, $Text) {
		return @{
			method = 'Input.dispatchKeyEvent'
			sessionId = $SessionId
			params = @{
				type = 'char'
				text = $Text
			}
		}
	}
	static [hashtable]dispatchMouseEvent($SessionId, $Type, $Button) {
		return @{
			method = 'Input.dispatchMouseEvent'
			sessionId = $SessionId
			params = @{
				type = $Type
				button = $Button
				clickCount = 0
				x = 0
				y = 0
			}
		}
	}
}

class CdpCommandPage {
	static [hashtable]enable($SessionId) {
		return @{
			method = 'Page.enable'
			sessionId = $SessionId
		}
	}
	static [hashtable]navigate($SessionId, $Url) {
		return @{
			method = 'Page.navigate'
			sessionId = $SessionId
			params = @{
				url = $Url
			}
		}
	}
}

class CdpCommandRuntime {
	static [hashtable]addBinding($SessionId, $Name) {
		return @{
			method = 'Runtime.addBinding'
			sessionId = $SessionId
			params = @{
				name = $Name
			}
		}
	}
	static [hashtable]enable($SessionId) {
		return @{
			method = 'Runtime.enable'
			sessionId = $SessionId
		}
	}
	static [hashtable]evaluate($SessionId, $Expression) {
		return @{
			method = 'Runtime.evaluate'
			sessionId = $SessionId
			params = @{
				expression = $Expression
			}
		}
	}
}

class CdpCommandTarget {
	static [hashtable]createTarget($Url) {
		return @{
			method = 'Target.createTarget'
			params = @{
				url = $Url
			}
		}
	}
	static [hashtable]setAutoAttach() {
		return @{
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
	static [hashtable]setDiscoverTargets() {
		return @{
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
}

# if ($PSVersionTable.PSVersion -lt 7.4) {
# 	. "$PSScriptRoot\CdpEventHandlerWindowsPowershell.ps1"
# } else {
# 	. "$PSScriptRoot\CdpEventHandlerPowershell.ps1"
# }

# . "$PSScriptRoot\CdpServer.ps1"
# . "$PSScriptRoot\Functions.ps1"

function Start-CdpServer {
	<#
		.SYNOPSIS
		Starts the CdpServer by launching the browser process, initializing the event handlers, and starting the message reader, processor, and writer threads
		.PARAMETER StartPage
		The URL of the page to load when the browser starts
		.PARAMETER UserDataDir
		The directory to use for the browser's user data profile. This should be a unique directory for each instance of the server to avoid conflicts
		.PARAMETER BrowserPath
		The path to the browser executable to launch
		.PARAMETER AdditionalThreads
		Sets the max runspaces the pool can use + 3.
		Default runspacepool uses 3min and 3max threads for MessageReader, MessageProcessor, MessageWriter
		A number higher than 0 increases the maximum runspaces for the pool.
		.PARAMETER Callbacks
		A hashtable of scriptblocks to be invoked for specific events. The keys should be the event names without the domain prefix and preceeded by 'On'. For example:
		@{
			OnLoadEventFired = { param($Response) $Response.params }
		}
		.PARAMETER DisableDefaultEvents
		This stops targets from being auto attached and auto discovered.
		.PARAMETER StreamOutput
		This is the $Host/Console which runspace streams will output to.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$StartPage,
		[Parameter(Mandatory)]
		[ValidateScript({ Test-Path $_ -PathType Container -IsValid })]
		[string]$UserDataDir,
		[Parameter(Mandatory)]
		[string]$BrowserPath,
		[ValidateScript({ $_ -ge 0 })]
		[int]$AdditionalThreads = 0,
		[hashtable]$Callbacks,
		[switch]$DisableDefaultEvents,
		[object]$StreamOutput
	)

	# $Server = [CdpServer]::new($StartPage, $UserDataDir, $BrowserPath, $AdditionalThreads, $Callbacks)
	$ConsoleHost = if ($StreamOutput) { $StreamOutput } else { (Get-Host) }
	$Server = New-UnboundClassInstance CdpServer -arguments $StartPage, $UserDataDir, $BrowserPath, $ConsoleHost, $AdditionalThreads, $Callbacks
	if ($PSBoundParameters.ContainsKey('Debug')) {
		$Server.SharedState.DebugPreference = 'Continue'
	}
	if ($PSBoundParameters.ContainsKey('Verbose')) {
		$Server.SharedState.VerbosePreference = 'Continue'
	}
	$Server.StartMessageReader()
	$Server.StartMessageProcessor()
	$Server.StartMessageWriter()

	if (!$DisableDefaultEvents) {
		$Server.EnableDefaultEvents()
	}

	while ($Server.SharedState.Targets.Count -eq 0 -or $null -eq $Server.SharedState.Targets[0].RuntimeUniqueId -or $null -eq $Server.SharedState.Targets[0].SessionId) {
		Start-Sleep -Seconds 1
	}

	$Server
}

function Stop-CdpServer {
	<#
		.SYNOPSIS
		Disposes the Server Pipes, Threads, ChromeProcess, and RunspacePool
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[CdpServer]$Server
	)

	$Server.Stop()
}

function New-CdpPage {
	<#
		.SYNOPSIS
		Creates a new target and returns the corresponding CdpPage object from the server's SharedState.Targets list
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[CdpServer]$Server,
		[string]$Url = 'about:blank',
		[switch]$NewWindow
	)
	$Command = [CdpCommandTarget]::createTarget($Url)
	if ($NewWindow) { $Command.params.newWindow = $true }
	$Response = $Server.SendCommand($Command, $true)

	$CdpPage = $Server.GetPageByTargetId($Response.result.targetId)

	$Command = [CdpCommandPage]::enable($CdpPage.SessionId)
	$Server.SendCommand($Command)
	$Command = [CdpCommandRuntime]::enable($CdpPage.SessionId)
	$null = $Server.SendCommand($Command, $true)

	$CdpPage
}

function Invoke-CdpPageNavigate {
	<#
		.SYNOPSIS
		Navigates and automatically waits for the page to load with LoadEventFired and FrameStoppedLoading
		Also waits for frames to load if they are present
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[CdpServer]$Server,
		[Parameter(Mandatory)]
		[string]$SessionId,
		[Parameter(Mandatory)]
		[string]$Url
	)

	$Command = [CdpCommandPage]::navigate($SessionId, $Url)
	$CdpPage = $Server.GetPageBySessionId($SessionId)
	$OldRuntimeUniqueId = $CdpPage.RuntimeUniqueId

	$Server.SendCommand($Command)

	if ($null -ne $OldRuntimeUniqueId) {
		while ($CdpPage.RuntimeUniqueId -eq $OldRuntimeUniqueId) {
			Start-Sleep -Milliseconds 50
		}
	}

	while ($CdpPage.IsLoading) {
		Start-Sleep -Milliseconds 50
	}

	if ($CdpPage.Frames.Count -eq 0) { return }
	while ([System.Linq.Enumerable]::Sum([int[]]@($CdpPage.Frames.Values.IsLoading)) -eq $CdpPage.Frames.Count) {
		Start-Sleep -Milliseconds 50
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
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[CdpServer]$Server,
		[Parameter(Mandatory)]
		[string]$SessionId,
		[Parameter(Mandatory)]
		[string]$Selector,
		[Parameter(ParameterSetName = 'Click')]
		[int]$Click = 0,
		[Parameter(ParameterSetName = 'Click')]
		[int]$OffsetX = 0,
		[Parameter(ParameterSetName = 'Click')]
		[int]$OffsetY = 0,
		[Parameter(ParameterSetName = 'Click')]
		[switch]$TopLeft
	)

	$CdpPage = $Server.GetPageBySessionId($SessionId)

	$Command = [CdpCommandRuntime]::evaluate($SessionId, $Selector)
	$Command.params.uniqueContextId = "$($CdpPage.RuntimeUniqueId)"
	$Response = $Server.SendCommand($Command, $true)
	$CdpPage.ObjectId = $Response.result.result.objectId

	if ($Click -le 0) { return }

	$Command = [CdpCommandDom]::describeNode($SessionId, $CdpPage.ObjectId)
	$Command.params.objectId = $CdpPage.ObjectId
	$Response = $Server.SendCommand($Command, $true)

	if ($Response.error) {
		throw ('Error describing node: {0}' -f $Response.error.message)
	}

	$CdpPage.Node = $Response.result.node

	$Command = [CdpCommandDom]::getBoxModel($SessionId, $CdpPage.ObjectId)
	$Command.params.objectId = $CdpPage.ObjectId
	$Response = $Server.SendCommand($Command, $true)
	$CdpPage.BoxModel = $Response.result.model

	$Command = [CdpCommandInput]::dispatchMouseEvent($CdpPage.SessionId, 'mousePressed', 'left')
	$Command.params.clickCount = $Click
	if ($TopLeft) {
		$Command.params.X = $CdpPage.BoxModel.content[0] + $OffsetX
		$Command.params.Y = $CdpPage.BoxModel.content[1] + $OffsetY
	} else {
		$Command.params.X = $CdpPage.BoxModel.content[0] + ($CdpPage.BoxModel.width / 2) + $OffsetX
		$Command.params.Y = $CdpPage.BoxModel.content[1] + ($CdpPage.BoxModel.height / 2) + $OffsetY
	}
	$Server.SendCommand($Command)
	$Command.params.type = 'mouseReleased'
	$Server.SendCommand($Command)
}

function Invoke-CdpInputSendKeys {
	<#
		.SYNOPSIS
		Sends keys to a session
		.PARAMETER Keys
		String to send
		.EXAMPLE
		Invoke-CdpInputSendKeys -Server $Server -SessionId $SessionId -Keys 'Hello World'
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[CdpServer]$Server,
		[Parameter(Mandatory)]
		[string]$SessionId,
		[Parameter(Mandatory)]
		[string]$Keys
	)

	$Command = [CdpCommandInput]::dispatchKeyEvent($SessionId, $null)
	$Keys.ToCharArray().ForEach({
			$Command.params.text = $_
			$Server.SendCommand($Command)
		}
	)
}
