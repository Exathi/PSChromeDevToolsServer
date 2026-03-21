$ModulePath = "$PSScriptRoot\PSChromeDevToolsServer"
Publish-Module -Path $ModulePath -NuGetApiKey $Env:APIKEY
