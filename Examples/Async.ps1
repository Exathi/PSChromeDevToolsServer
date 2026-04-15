Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

# If there are not enough runspaces in the pool, the scriptblocks in $Async will be queued.
# If all runspaces are exhausted with StartMessageProcessor/StartMessageWriter, the $Async will never run.
$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -AdditionalThreads 4
$CdpServer = $CdpPage.CdpServer

$TestClickType = {
    param($CdpServer)
    # MUST BE WINDOWED NOT FULLSCREENED
    # We use -NewWindow because sometimes inputs do not register to a tab that is not active.
    # It works if tabs are on separate windows.
    # Alternatively use javascript.click()/value
    $CdpPage = New-CdpPage -CdpServer $CdpServer -Url 'about:blank' -NewWindow

    # Navigate and fill in textbox then replace the text.
    $null = $CdpPage | Invoke-CdpPageNavigate -Url 'https://www.selenium.dev/selenium/web/single_text_input.html' |
    Wait-CdpPageLifecycleEvent -Events NetworkIdle, FirstPaint |
    Invoke-CdpInputSendKeys -Keys 'Hello World'

    # Pause so we can see it typed then replace the text
    Start-Sleep 2
    $null = $CdpPage | Invoke-CdpInputClickElement -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'textInput' } -Click 3 -TopLeft |
    Invoke-CdpInputSendKeys -Keys 'PSChromeDevToolsServer'
    'Finished TestClickType'

    # Navigate and wait for frames then click element with javascript.
    $CdpPage2 = $CdpPage | New-CdpPage -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
    $CdpContext = Get-CdpFrame -CdpPage $CdpPage2 -Url 'clicks.html'
    Wait-CdpPageLifecycleEvent -InputObject $CdpContext -Events NetworkIdle, FirstPaint
    $null = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage2 -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]").click()'

    # Click element in frame
    $CdpContext = Get-CdpFrame -CdpPage $CdpPage2 -Url 'https://www.selenium.dev/selenium/web/simpleTest.html'
    Wait-CdpPageLifecycleEvent -InputObject $CdpContext -Events NetworkIdle, FirstPaint
    Invoke-CdpInputClickElement -CdpPage $CdpPage2 -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'checkbox1' } -Click 1

    'Finished TestClickFrame'
}.Ast.GetScriptBlock()

$Asyncs = 1..4 | ForEach-Object {
    $Powershell = [powershell]::Create().AddScript($TestClickType).AddParameter('CdpServer', $CdpServer)
    $Powershell.RunspacePool = $CdpServer.Runspacepool
    $Powershell
}

$Tasks = $Asyncs | ForEach-Object {
    # For Windows Powershell compatability.
    # Newer versions have InvokeAsync() that return a task.
    $EndInvokeDelegate = ConvertTo-Delegate -Method $_.EndInvoke -Target $_
    [System.Threading.Tasks.Task]::Factory.FromAsync($_.BeginInvoke(), $EndInvokeDelegate)
}

$WaitAll = [System.Threading.Tasks.Task]::WhenAll($Tasks)
while (!$WaitAll.GetAwaiter().IsCompleted) {
    Start-Sleep -Milliseconds 1 # for ctrl + c
}
$WaitAll.GetAwaiter().GetResult()

$Asyncs | ForEach-Object {
    $_.Dispose()
}

# $CdpServer.ShowMessageHistory() | Format-Table -AutoSize

# $CdpServer.Threads.MessageReader.Streams
# $CdpServer.Threads.MessageProcessor.Streams
# $CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -CdpPage $CdpPage
