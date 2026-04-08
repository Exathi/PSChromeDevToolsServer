Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'about:blank'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug
$CdpServer = $CdpPage.CdpServer

$null = $CdpPage | Invoke-CdpPageNavigate -Url 'https://www.selenium.dev/selenium/web/single_text_input.html' |
Wait-CdpPageLifecycleEvent -Events NetworkIdle, FirstPaint -Timeout 5000 |
Invoke-CdpInputSendKeys -Keys 'Hello World'
Start-Sleep 1
$null = $CdpPage | Invoke-CdpInputClickElement -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'textInput' } -Click 3 -TopLeft |
Invoke-CdpInputSendKeys -Keys 'PSChromeDevToolsServer'

$CdpPage2 = $CdpPage | New-CdpPage -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
$CdpContext = Get-CdpFrame -CdpPage $CdpPage2 -Url 'clicks.html'
Wait-CdpPageLifecycleEvent -InputObject $CdpContext -Events NetworkIdle, FirstPaint -Timeout 5000
$null = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage2 -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=source]").contentDocument.querySelector("[id=otherframe]").click()'

$null = $CdpPage | Invoke-CdpPageNavigate -Url 'https://www.selenium.dev/selenium/web/click_frames.html' |
Get-CdpFrame -Url 'clicks.html' |
Wait-CdpPageLifecycleEvent -Events NetworkIdle -Timeout 5000 |
Invoke-CdpInputClickElement -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'otherframe' } -Click 1 -BringToFront

$CdpServer.ShowMessageHistory() | Format-Table -AutoSize

$CdpServer.Threads.MessageReader.Streams
$CdpServer.Threads.MessageProcessor.Streams
$CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -CdpPage $CdpPage
