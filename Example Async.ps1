Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

# 2 additional threads to run each $Async in the runspacepool.
$Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -AdditionalThreads 2

$Async1 = [powershell]::Create().AddScript(
    {
        param($Server)
        $FirstTab = $Server.SharedState.Targets[0]
        Invoke-CdpPageNavigate -Server $Server -SessionId $FirstTab.SessionId -Url 'https://www.google.com'
        Invoke-CdpInputClickElement -Server $Server -SessionId $FirstTab.SessionId -Selector 'document.querySelector("[name=q]")' -Click 1
        Invoke-CdpInputSendKeys -Server $Server -SessionId $FirstTab.SessionId -Keys 'Hello World'
        Invoke-CdpInputClickElement -Server $Server -SessionId $FirstTab.SessionId -Selector 'document.querySelector("[name=q]")' -Click 3 -TopLeft
        Invoke-CdpInputSendKeys -Server $Server -SessionId $FirstTab.SessionId -Keys 'PSChromeDevToolsServer'

        'Finished from Async1'
    }.Ast.GetScriptBlock()
).AddParameter('Server', $Server)
$Async1.RunspacePool = $Server.Runspacepool
$Handle1 = $Async1.BeginInvoke()

$Async2 = [powershell]::Create().AddScript(
    {
        param($Server)
        # We use -NewWindow because inputs do not register to a tab that is not active.
        # It does work if tabs are on separate windows.
        # Alternatively use javascript.click()
        $SecondTab = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/click_frames.html' -NewWindow
        Invoke-CdpInputClickElement -Server $Server -SessionId $SecondTab.SessionId -Selector 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]")' -Click 1

        'Finished from Async2'
    }.Ast.GetScriptBlock()
).AddParameter('Server', $Server)
$Async2.RunspacePool = $Server.Runspacepool
$Handle2 = $Async2.BeginInvoke()

# For Windows Powershell compatability.
# Newer versions have InvokeAsync() that return a task.
$EndInvokeDelegate1 = ConvertTo-Delegate -Method $Async1.EndInvoke -Target $Async1
$EndInvokeDelegate2 = ConvertTo-Delegate -Method $Async2.EndInvoke -Target $Async2

$Task1 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle1, $EndInvokeDelegate1)
$Task2 = [System.Threading.Tasks.Task]::Factory.FromAsync($Handle2, $EndInvokeDelegate2)

$WaitAll = [System.Threading.Tasks.Task]::WhenAll($Task1, $Task2)
$WaitAll.GetAwaiter().GetResult()

$Server.ShowMessageHistory() | Format-Table -AutoSize

$Server.Threads.MessageReader.Streams
$Server.Threads.MessageProcessor.Streams
$Server.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
