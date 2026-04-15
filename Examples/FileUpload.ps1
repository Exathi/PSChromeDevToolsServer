Import-Module '.\PSChromeDevToolsServer'

$StartPage = 'https://the-internet.herokuapp.com/upload'
$UriBuilder = [System.UriBuilder]::new($StartPage)
$UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug

$Files = 'D:\a.txt'
Send-CdpDomUploadFile -CdpPage $CdpPage -Files $Files -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'file-upload' }
Invoke-CdpInputClickElement -CdpPage $CdpPage -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'file-submit' } -Click 1

# Stop-CdpServer -CdpPage $CdpPage
