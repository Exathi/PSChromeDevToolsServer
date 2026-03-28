Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug

$CdpPage = New-CdpPage -Server $Server -Url 'about:blank' -NewWindow
Invoke-CdpPageNavigate -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("[id=textInput]")' -Click 1
Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'Hello World'
Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Selector 'document.querySelector("#textInput")' -Click 3 -TopLeft
Invoke-CdpInputSendKeys -Server $Server -SessionId $CdpPage.TargetInfo.SessionId -Keys 'PSChromeDevToolsServer'
$CdpPage2 = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/click_frames.html' -BrowserContextId $CdpPage.BrowserContextId
Invoke-CdpInputClickElement -Server $Server -SessionId $CdpPage2.TargetInfo.SessionId -Selector 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]")' -Click 1

$Server.ShowMessageHistory() | Format-Table -AutoSize

$Server.Threads.MessageReader.Streams
$Server.Threads.MessageProcessor.Streams
$Server.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
