Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'https://www.selenium.dev/selenium/web/click_tests/html5_submit_buttons.html'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug
$CdpServer = $CdpPage.CdpServer

Write-Host 'By nth tag name'
Wait-CdpPageLifecycleEvent -InputObject $CdpPage -Events NetworkIdle
Invoke-CdpInputClickElement -CdpPage $CdpPage -Click 1 -Delay 1 -FilterScript { $_.NodeName -eq 'button' } -Index -1

Start-Sleep 1
Write-Host 'By id'
Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/click_tests/html5_submit_buttons.html'
Wait-CdpPageLifecycleEvent -InputObject $CdpPage -Events NetworkIdle
Invoke-CdpInputClickElement -CdpPage $CdpPage -Click 1 -Delay 1 -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'internal_implicit_submit' }

Start-Sleep 1
Write-Host 'By text'
Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/click_tests/html5_submit_buttons.html'
Wait-CdpPageLifecycleEvent -InputObject $CdpPage -Events NetworkIdle
$Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'Spanned Submit' }
Invoke-CdpInputClickElement -CdpPage $CdpPage -Click 1 -Delay 1 -FilterScript { $_.NodeValue -eq 'Spanned Submit' }

# $CdpServer.ShowMessageHistory() | Format-Table -AutoSize

# $CdpServer.Threads.MessageReader.Streams
# $CdpServer.Threads.MessageProcessor.Streams
# $CdpServer.Threads.MessageWriter.Streams

# Stop-CdpServer -CdpPage $CdpPage
