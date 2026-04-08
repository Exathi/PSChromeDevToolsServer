function Start-CdpServer {
    <#
        .SYNOPSIS
        Starts the CdpServer by launching the browser process, initializing the event handlers, and starting the message reader, processor, and writer threads.
        .PARAMETER StartPage
        The URL of the page to load when the browser starts.
        .PARAMETER UserDataDir
        The directory to use for the browser's user data profile. This should be a unique directory for each instance of the server to avoid conflicts.
        .PARAMETER BrowserArgs
        Commandline args for chromium.
        Must NOT include --user-data-dir=. This is added by UserDataDir parameter.
        Must NOT include --remote-debugging-pipe and --remote-debugging-io-pipe if using pipes.
        .PARAMETER BrowserPath
        The path to the browser executable to launch
        .PARAMETER AdditionalThreads
        Sets the max runspaces the pool can use + 3.
        Default runspacepool uses 3min and 3max threads for MessageReader, MessageProcessor, MessageWriter
        A number higher than 0 increases the maximum runspaces for the pool.

        More MessageProcessor can be started with $CdpServer.MessageProcessor()
        These will be queued forever if the max number of runspaces are exhausted in the pool.
        .PARAMETER Callbacks
        A hashtable of scriptblocks to be invoked for specific events. The keys should be the event names without the domain prefix and preceeded by 'On'. For example:
        @{
            OnLoadEventFired = { param($Response) $Response.params }
        }
        .PARAMETER DisableDefaultEvents
        This stops targets from being auto attached and auto discovered.
        .PARAMETER StreamOutput
        This is the (Get-Host)/$Host Console which runspacepool streams will output to.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'DefaultArgs')]
        [string]$StartPage,
        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'DefaultArgs')]
        [Parameter(ParameterSetName = 'UserArgs')]
        [ValidateScript({ Test-Path $_ -PathType Container -IsValid })]
        [string]$UserDataDir,
        [Parameter(ParameterSetName = 'UserArgs')]
        [string[]]$BrowserArgs,
        [Parameter(ParameterSetName = 'UserArgs')]
        [System.Management.Automation.Runspaces.InitialSessionState]$State,
        [Parameter(Mandatory)]
        [string]$BrowserPath,
        [ValidateScript({ $_ -ge 0 })]
        [int]$AdditionalThreads = 0,
        [hashtable]$Callbacks,
        [switch]$DisableDefaultEvents,
        [object]$StreamOutput
    )

    $LockFile = Join-Path -Path $UserDataDir -ChildPath 'lockfile'
    if (Test-Path -Path $LockFile -PathType Leaf) { throw 'Browser is already open. Please close it and run Start-CdpServer again.' }

    if ($PSCmdlet.ParameterSetName -eq 'DefaultArgs') {
        $BrowserArgs = @(
            ('--user-data-dir="{0}"' -f $UserDataDir)
            '--no-first-run'
            $StartPage
        ) | Where-Object { $_ -ne '' -and $null -ne $_ }
    } else {
        $BrowserArgs += (' --user-data-dir="{0}"' -f $UserDataDir)
    }

    $ConsoleHost = if ($StreamOutput) { $StreamOutput } else { (Get-Host) }
    $CdpServer = New-UnboundClassInstance CdpServer -arguments $BrowserPath, $ConsoleHost, $BrowserArgs, $AdditionalThreads, $Callbacks, $State

    if ($PSBoundParameters.ContainsKey('Debug')) {
        $CdpServer.SharedState.DebugPreference = 'Continue'
    }

    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $CdpServer.SharedState.VerbosePreference = 'Continue'
    }

    $CdpServer.StartMessageReader()
    $CdpServer.StartMessageProcessor()
    $CdpServer.StartMessageWriter()

    if (!$DisableDefaultEvents) {
        $CdpServer.EnableDefaultEvents()
    }

    $CdpServer.GetFirstAvailableCdpPage()
}
