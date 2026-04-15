# PSChromeDevToolsServer - PowerShell Browser Automation
[![Static Badge](https://img.shields.io/badge/Powershell%20Gallery-0.5.3-blue)](https://www.powershellgallery.com/packages/PSChromeDevToolsServer/)


Automate any Chromium browser with Windows PowerShell and Pwsh with `--remote-debugging-pipe` and `--remote-debugging-io-pipe`. Still couldn't find any examples in 2026 that made use of these switches with dotnet without tapping into WinApi functions.

 * Zero Dependencies: Pure PowerShell and .NET.
 * This is NOT a wrapper around playwright/puppeteer/selenium.
 * Only a small subset of Cdp commands are currently implemented.

Two goals in making this:

1. Light browser automation without external dependencies and be a potential step up from VBA.

2. Use it as a local frontend for powershell without opening ports.

## Quick Start

``` Powershell
Import-Module '.\PSChromeDevToolsServer'

$StartParams = @{
    UserDataDir = 'D:\Non-Default\UserData\Folder' # Reminder to change this to your own folder!
    StartPage = [System.UriBuilder]::new('about:blank').Uri.AbsoluteUri
    BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
}

$CdpPage = Start-CdpServer @StartParams

$CdpPage |
    Invoke-CdpPageNavigate -Url 'https://www.github.com' |
    Invoke-CdpRuntimeEvaluate -Expression 'document.title' |
    Out-Null

$CdpPage.PageInfo['EvaluateResult'].value

# Stop-CdpServer -CdpPage $CdpPage
```

## Commands

| Function | Description |
|-|-|
| Start-CdpServer | Launch browser and returns the first `[CdpPage]`. |
| Stop-CdpServer | Close browser and dispose pipes, processes, and the runspace pool. |
| Get-CdpFrame | Tries to find a frame matching the provided url to be used with `Wait-CdpPageLifecycleEvent`. Returns a pscustomobject with `[CdpPage]` and `[CdpFrame]` |
| Invoke-CdpCommand | Helper function to invoke any cdp command not yet implemented. |
| Invoke-CdpInputClickElement | Find element with a selector and click element via DOM. If navigation is expected, use `Test-CdpSelector` to wait for the new url/element then follow with `Wait-CdpPageLifecycleEvent` NetworkIdle. |
| Invoke-CdpInputSendKeys | Sends keys to browser. If navigation is expected, use `Test-CdpSelector` to wait for the new url/element then follow with `Wait-CdpPageLifecycleEvent` NetworkIdle. |
| Invoke-CdpPageCaptureScreenshot | Takes a screenshot of the current page. |
| Invoke-CdpPageNavigate | Navigate page and waits for the page to load and the unique javascript context to update for the new page. |
| Invoke-CdpPagePrintToPdf | Prints page to pdf. |
| Invoke-CdpRuntimeAddBinding | Add binding object to enable browser communication to run provided callbacks in `[CdpEventHandler]`. |
| Invoke-CdpRuntimeEvaluate | Run javascript on browser and return result in `[CdpPage].PageInfo['EvaluateResult']` and the response in `[CdpPage].PageInfo['EvaluateResponse']`. |
| New-CdpPage | Create new page/tab and returns `[CdpPage]`. |
| Send-CdpDomFileUpload | Uploads files to the input element found by filterscript. |
| Test-CdpSelector | Wait until a valid selector is found or timed out. |
| Wait-CdpPageLifecycleEvent | `[CdpPage]` or output from `Get-CdpFrame` to wait for a LifecycleEvent. |
| ConvertTo-Delegate | Used to convert PSMethods to delegates for Windows Powershell. See `Examples\Async.ps1`. |

## Classes

Basic information on internal classes.

`Start-CdpServer` returns a `[CdpPage]`. Pass this into every function as it internally calls `$CdpPage.CdpServer.SendCommand()` to send commands to the browser.

``` Powershell
# Basic information about a tab.
[CdpPage]

# Basic information about a frame. Resides in $CdpPage.Frames
[CdpFrame]

# Responsible for providing methods to process each event response
[CdpEventHandler]

# Each method follows Cdp naming without the prefix.
# Methods are setup to provide basic tab and session/context handling.
$CdpEventHandler.DomContentEventFired() = Page.DomContentEventFired

# This is where additional scriptblocks are held for each event to process for each event.
# Can be added to with `Start-CdpServer -Callbacks @{OnEventName = {}}`
# Events must be the same as the respective method name preceded by 'On'
# Ex - OnDomContentEventFired
$CdpEventHandler.EventHandlers['OnDomContentEventFired'] = {'do stuff'}

# This is responsible for starting the browser, starting message processing and sending commands to the browser.
[CdpServer]

# This property holds all variables that are available across runspaces.
$CdpServer.SharedState

# This method sends the command as json converted into bytes and increments the CommandId.
$CdpServer.SendCommand()

# These methods are responsible for starting runspaces to read and write to the pipes of the browser.
# MessageReader is responsible for reading output from the browser.
# MessageProcessor is responsible for processing the events such as setting the CdpPage with a SessionId. Multiple can be started for handling long duration OnBindingCalled.
# MessageWriter is responsible for writing commands to the browser.
$CdpServer.StartMessageReader()
$CdpServer.StartMessageProcessor()
$CdpServer.StartMessageWriter()

# Classes with static methods do not work well in runspaces in Windows Powershell.
# Previous version's classes are replaced with private functions with name Get-Domain.methodName
# Ex Get-Dom.describeNode


```

## Notes

If the terminal closes or pipes lose connection, the browser will close. The browser is tied to the terminal.

`Start-CdpServer -Verbose -Debug` will enable respective runspacepool stream outputs to the main console.

`AnonymousPipeServerStream.Write()` requires a null byte to be sent at the end of the string to signal end of write.

`AnonymousPipeServerStream.Read()` locks the terminal on reading an empty pipe. This is offloaded to a dedicated runspace.

Some events such as `Target.targetCreated` `Target.attachedToTarget` `Target.detachedFromTarget` `Target.targetInfoChanged` are by default turned on to manage active pages. Only pages are attached. Types such as `service_worker` or `background_page` are excluded by default.

Page events and Javascript are on by default for the first tab.

`[System.Threading.Interlocked]::Add([ref]$Int)` does not work across runspaces. `ConcurrentDictionary.AddOrUpdate()` and relevant other ConcurrentDictionary threadsafe methods are used for all atomic operations.
