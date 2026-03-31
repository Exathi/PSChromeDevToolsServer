# PSChromeDevToolsServer - Powershell Browser Automation
[![Static Badge](https://img.shields.io/badge/Powershell%20Gallery-0.2.1-blue)](https://www.powershellgallery.com/packages/PSChromeDevToolsServer/)


Automate any Chromium browser with Powershell with `--remote-debugging-pipe` and `--remote-debugging-io-pipe`. I still couldn't find any examples in 2026 that made use of these switches with dotnet without tapping into WinApi functions.

This uses only what's available by default in powershell. No external dependencies.

Two goals in making this:

1. Light browser automation without external dependencies and be a potential step up from VBA. Only a small subset of Cdp commands are currently implemented.

2. Use it as a local frontend for powershell without opening ports.

## Commands

Start-CdpServer - Launch browser and returns `[CdpServer]`.

Stop-CdpServer - Close browser and dispose pipes, processes, runspace pool.

New-CdpPage - Create new page/tab and returns `[CdpPage]`.

Invoke-CdpPageNavigate - Navigate page and waits for the page to load and the unique javascript context to update for the new page.

Invoke-CdpInputClickElement - Find element with javascript selector and click element via DOM.

Invoke-CdpInputSendKeys - Sends keys to browser.

Invoke-CdpRuntimeEvaluate - Run javascript on browser and return raw result.

Invoke-CdpRuntimeAddBinding - Add binding object to enable browser communication to the `[CdpEventHandler]`.

ConvertTo-Delegate - Used to convert PSMethods to delegates for Windows Powershell. See `Example Async.ps1`.

## Classes

`Start-CdpServer` returns a `[CdpServer]` object. Pass this into every function as they internally call `$CdpServer.SendCommand()` to send commands to the browser.

``` Powershell
# Basic information about a tab target.
[CdpPage]

# Basic information about a frame. Resides in $Target.Frames
[CdpFrame]

# Responsible for providing methods to process each event response
[CdpEventHandler]

# Each method follows Cdp naming without the prefix.
# Base methods are setup to provide basic tab and session/context handling.
$CdpEventHandler.DomContentEventFired() = Page.DomContentEventFired

# This is where additional scriptblocks are held for each event to process for each event.
# Can be added to with `Start-CdpServer -Callbacks @{OnEventName = {}}`
# Events must be the same as the respective method name preceeded by 'On'
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
# MessageProcessor is responsible for processing the events such as setting the CdpPage with a SessionId.
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

## Todo/Considerations

Break up the file into smaller pieces.

ValueFromPipeline/ValueFromPipelineByPropertyName support.
