Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$Server = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath

$FirstTab = $Server.SharedState.Targets[0]
Invoke-CdpPageNavigate -Server $Server -SessionId $FirstTab.SessionId -Url 'https://www.google.com'
Invoke-CdpInputClickElement -Server $Server -SessionId $FirstTab.SessionId -Selector 'document.querySelector("[name=q]")' -Click 1
Invoke-CdpInputSendKeys -Server $Server -SessionId $FirstTab.SessionId -Keys 'Hello World'
Invoke-CdpInputClickElement -Server $Server -SessionId $FirstTab.SessionId -Selector 'document.querySelector("[name=q]")' -Click 3 -TopLeft
Invoke-CdpInputSendKeys -Server $Server -SessionId $FirstTab.SessionId -Keys 'PSChromeDevToolsServer'

$SecondTab = New-CdpPage -Server $Server -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
Invoke-CdpInputClickElement -Server $Server -SessionId $SecondTab.SessionId -Selector 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]")' -Click 1

$Server.ShowMessageHistory() | Format-Table -AutoSize

$Server.Threads.MessageReader.Streams
$Server.Threads.MessageProcessor.Streams
$Server.Threads.MessageWriter.Streams

# Stop-CdpServer -Server $Server
