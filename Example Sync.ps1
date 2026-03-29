Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug

$CdpPage = New-CdpPage -Server $Server -Url 'about:blank' -BrowserContextId $Server.SharedState.BrowserContexts[0]
Invoke-CdpPageNavigate -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("[id=textInput]").value="H"'
Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'ello World'
Start-Sleep 1
Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("#textInput")' -Click 3 -TopLeft
Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'PSChromeDevToolsServer'
$CdpPage2 = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/click_frames.html' -BrowserContextId $CdpPage.BrowserContextId
$null = Invoke-CdpRuntimeEvaluate -Server $Server -SessionId $CdpPage2.TargetInfo.SessionId -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]").click()'

$Server.ShowMessageHistory() | Format-Table -AutoSize

$Server.Threads.MessageReader.Streams
$Server.Threads.MessageProcessor.Streams
$Server.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
