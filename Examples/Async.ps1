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
    $null = $CdpPage | Invoke-CdpPageNavigate -Url 'https://www.selenium.dev/selenium/web/single_text_input.html' |
    Wait-CdpPageLifecycleEvent -Events NetworkIdle, FirstPaint -Timeout 5000 |
    Invoke-CdpInputSendKeys -Keys 'Hello World'
    $null = $CdpPage | Invoke-CdpInputClickElement -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'textInput' } -Click 3 -TopLeft |
    Invoke-CdpInputSendKeys -Keys 'PSChromeDevToolsServer'
    'Finished TestClickType'

    $CdpPage2 = $CdpPage | New-CdpPage -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
    $CdpContext = Get-CdpFrame -CdpPage $CdpPage2 -Url 'clicks.html'
    Wait-CdpPageLifecycleEvent -InputObject $CdpContext -Events NetworkIdle, FirstPaint -Timeout 5000
    $null = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage2 -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]").click()'
    'Finished TestClickFrame'
}.Ast.GetScriptBlock()

$Async1 = [powershell]::Create().AddScript($TestClickType).AddParameter('CdpServer', $CdpServer)
$Async2 = [powershell]::Create().AddScript($TestClickType).AddParameter('CdpServer', $CdpServer)
$Async3 = [powershell]::Create().AddScript($TestClickType).AddParameter('CdpServer', $CdpServer)
$Async4 = [powershell]::Create().AddScript($TestClickType).AddParameter('CdpServer', $CdpServer)
$Async1.RunspacePool = $CdpServer.Runspacepool
$Async2.RunspacePool = $CdpServer.Runspacepool
$Async3.RunspacePool = $CdpServer.Runspacepool
$Async4.RunspacePool = $CdpServer.Runspacepool

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

# $CdpServer.ShowMessageHistory() | Format-Table -AutoSize

# $CdpServer.Threads.MessageReader.Streams
# $CdpServer.Threads.MessageProcessor.Streams
# $CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -CdpPage $CdpPage
