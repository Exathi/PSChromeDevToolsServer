Import-Module '.\PSChromeDevToolsServer'

$StartPage = "$PSScriptRoot\Front End\Index.html"
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

# Javascript calls `window.PowershellServer(payload);` and $Server.MessageProcessor receives the BindingCalled event.
# The $Server.MessageProcessor invokes $EventHandler.BindingCalled() which then runs the added callback below in Callbacks['OnBindingCalled']
$OnBindingCalled = {
	param($Response)
	if ($Response.params.name -ne 'PowershellServer') { return }

	$Payload = $Response.params.payload | ConvertFrom-Json
	if ($Payload.Sender.StartsWith('First')) {
		$StringBuilder = [System.Text.StringBuilder]::new()

		$null = $StringBuilder.Append('<thead><tr><th>Name</th><th>Id</th><th>Memory KB</th><th>Start Time</th></tr></thead><tbody>')

		$Data = Get-Process
		$Data | ForEach-Object {
			$null = $StringBuilder.Append("<tr><td>$($_.Name)</td><td>$($_.Id)</td><td>$($_.WorkingSet64 / 1KB)</td><td>$($_.StartTime)</td></tr>")
		}

		$null = $StringBuilder.Append('</tbody>')

		$SharedState.Commands.SendRuntimeEvaluate.Invoke($Response.sessionId,
			("p = document.getElementById('powershellResponseTable');
				p.innerHTML = '{0}';" -f $StringBuilder.ToString()
			)
		)

		$null = $StringBuilder.Clear()
	}

	Write-Host ('Received callback from browser with payload: ({0}) Processed at: ({1})' -f $Response.params.payload, (Get-Date).DateTime) -ForegroundColor Cyan
	$SharedState.Commands.SendRuntimeEvaluate.Invoke($Response.sessionId, 'enableButton("{0}")' -f $Payload.Sender)
}.Ast.GetScriptBlock()

# Reenable buttons on page refresh after Runtime is enabled again.
$OnExecutionContextCreated = {
	param($Response)
	Write-Verbose "Testing access: This.SharedState=$($null -ne $this.SharedState), This.EventHandler=$($null -ne $this.SharedState.EventHandler)"
	Write-Debug "Testing access: SharedState=$($null -ne $SharedState), SharedState.EventHandler=$($null -ne $SharedState.EventHandler)"

	$CurrentPage = $SharedState.Commands.GetPageBySessionId.Invoke($Response.sessionId)

	if ($CurrentPage.Url.StartsWith('file:///', [System.StringComparison]::OrdinalIgnoreCase)) {
		$SharedState.Commands.SendRuntimeEvaluate.Invoke($Response.sessionId, 'enableAllButtons()')
	}
}.Ast.GetScriptBlock()

$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Callbacks @{
	OnBindingCalled = $OnBindingCalled
	OnExecutionContextCreated = $OnExecutionContextCreated
}# -Verbose -Debug
$CdpServer = $CdpPage.CdpServer

# Optionally start more threads to process messages if there is something that will run for a while.
# $Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Callbacks @{
# 	OnBindingCalled = $OnBindingCalled
# 	OnExecutionContextCreated = $OnExecutionContextCreated
# } -AdditionalThreads 1

# Add 'PowershellServer' through addBinding. When a button is clicked, it calls window.PowershellServer(payload); configured in script.js
# $OnBindingCalled is invoked and ran when a button is clicked.
Invoke-CdpRuntimeAddBinding -CdpPage $CdpPage -Name 'PowershellServer'
$null = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage -Expression 'enableAllButtons()'

$CdpServer.ShowMessageHistory() | Format-Table -AutoSize

$CdpServer.Threads.MessageReader.Streams
$CdpServer.Threads.MessageProcessor.Streams
$CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
