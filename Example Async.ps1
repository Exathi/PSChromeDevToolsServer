Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

# If there are not enough runspaces in the pool they will be queued.
# If all runspaces are exhausted with StartMessageProcessor/StartMessageWriter the $Async will never run.
$Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -AdditionalThreads 4

$TestClickType = {
    param($Server)
    # MUST BE WINDOWED NOT FULLSCREENED
    # We use -NewWindow because sometimes inputs do not register to a tab that is not active.
    # It works if tabs are on separate windows.
    # Alternatively use javascript.click()
    $CdpPage = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/single_text_input.html' -NewWindow
    Invoke-CdpPageNavigate -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
    Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("[id=textInput]")' -Click 1
    Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'Hello World'
    Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("#textInput")' -Click 3 -TopLeft
    Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'PSChromeDevToolsServer'
    'Finished TestClickType'

    $CdpPage2 = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/click_frames.html' -BrowserContextId $CdpPage.BrowserContextId
    Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage2.TargetInfo.SessionId -Selector 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]")' -Click 1
    'Finished TestClickFrame'
}.Ast.GetScriptBlock()

$Async1 = [powershell]::Create().AddScript($TestClickType).AddParameter('Server', $Server)
$Async2 = [powershell]::Create().AddScript($TestClickType).AddParameter('Server', $Server)
$Async3 = [powershell]::Create().AddScript($TestClickType).AddParameter('Server', $Server)
$Async4 = [powershell]::Create().AddScript($TestClickType).AddParameter('Server', $Server)
$Async1.RunspacePool = $Server.Runspacepool
$Async2.RunspacePool = $Server.Runspacepool
$Async3.RunspacePool = $Server.Runspacepool
$Async4.RunspacePool = $Server.Runspacepool

$Handle1 = $Async1.BeginInvoke()
$Handle2 = $Async2.BeginInvoke()
$Handle3 = $Async3.BeginInvoke()
$Handle4 = $Async4.BeginInvoke()

# For Windows Powershell compatability.
# Newer versions have InvokeAsync() that return a task.
$EndInvokeDelegate1 = ConvertTo-Delegate -Method $Async1.EndInvoke -Target $Async1
$EndInvokeDelegate2 = ConvertTo-Delegate -Method $Async2.EndInvoke -Target $Async2
$EndInvokeDelegate3 = ConvertTo-Delegate -Method $Async3.EndInvoke -Target $Async3
$EndInvokeDelegate4 = ConvertTo-Delegate -Method $Async4.EndInvoke -Target $Async4

$Task1 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle1, $EndInvokeDelegate1)
$Task2 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle2, $EndInvokeDelegate2)
$Task3 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle3, $EndInvokeDelegate3)
$Task4 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle4, $EndInvokeDelegate4)

$WaitAll = [System.Threading.Tasks.Task]::WhenAll($Task1, $Task2, $Task3, $Task4)
while (!$WaitAll.GetAwaiter().IsCompleted) {
    Start-Sleep -Milliseconds 1 # for ctrl + c
}
$WaitAll.GetAwaiter().GetResult()

# $Server.ShowMessageHistory() | Format-Table -AutoSize

# $Server.Threads.MessageReader.Streams
# $Server.Threads.MessageProcessor.Streams
# $Server.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
