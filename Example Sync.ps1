Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug
$CdpServer = $CdpPage.CdpServer

$null = $CdpPage | Invoke-CdpPageNavigate -Url 'https://www.selenium.dev/selenium/web/single_text_input.html' |
Invoke-CdpInputClickElement -Selector 'document.querySelector("[id=textInput]").value="H"' |
Invoke-CdpInputSendKeys -Keys 'ello World'
Start-Sleep 1
$null = $CdpPage | Invoke-CdpInputClickElement -Selector 'document.querySelector("#textInput")' -Click 3 -TopLeft |
Invoke-CdpInputSendKeys -Keys 'PSChromeDevToolsServer'

$CdpPage2 = $CdpPage | New-CdpPage -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
$null = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage2 -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]").click()'

$CdpServer.ShowMessageHistory() | Format-Table -AutoSize

$CdpServer.Threads.MessageReader.Streams
$CdpServer.Threads.MessageProcessor.Streams
$CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -CdpPage $CdpPage
