
function Get-DOM.describeNode {
    param($SessionId)
    @{
        method = 'DOM.describeNode'
        sessionId = $SessionId
        params = @{}
    }
}
function Get-DOM.disable {
    param($SessionId)
    @{
        method = 'DOM.disable'
        sessionId = $SessionId
    }
}
function Get-DOM.getBoxModel {
    param($SessionId)
    @{
        method = 'DOM.getBoxModel'
        sessionId = $SessionId
        params = @{}
    }
}
function Get-DOM.getDocument {
    param($SessionId)
    @{
        method = 'DOM.getDocument'
        sessionId = $SessionId
        params = @{
            depth = -1
            pierce = $true
        }
    }
}
function Get-DOM.setFileInputFiles {
    param($SessionId, $Files, $BackendNodeId)
    @{
        method = 'DOM.setFileInputFiles'
        sessionId = $SessionId
        params = @{
            files = @($Files)
            backendNodeId = $BackendNodeId
        }
    }
}

function Get-Input.dispatchKeyEvent {
    param($SessionId, $Text)
    @{
        method = 'Input.dispatchKeyEvent'
        sessionId = $SessionId
        params = @{
            type = 'char'
            text = $Text
        }
    }
}
function Get-Input.dispatchMouseEvent {
    param($SessionId, $Type, $X, $Y, $Button)
    @{
        method = 'Input.dispatchMouseEvent'
        sessionId = $SessionId
        params = @{
            type = $Type
            button = $Button
            clickCount = 0
            x = $X
            y = $Y
        }
    }
}

function Get-Page.bringToFront {
    param($SessionId)
    @{
        method = 'Page.bringToFront'
        sessionId = $SessionId
    }
}
function Get-Page.enable {
    param($SessionId)
    @{
        method = 'Page.enable'
        sessionId = $SessionId
    }
}
function Get-Page.navigate {
    param($SessionId, $Url)
    @{
        method = 'Page.navigate'
        sessionId = $SessionId
        params = @{
            url = $Url
        }
    }
}
function Get-Page.getFrameTree {
    param($SessionId)
    @{
        method = 'Page.getFrameTree'
        sessionId = $SessionId
    }
}
function Get-Page.setLifecycleEventsEnabled {
    param($SessionId, [bool]$Enabled)
    @{
        method = 'Page.setLifecycleEventsEnabled'
        sessionId = $SessionId
        params = @{
            enabled = $Enabled
        }
    }
}

function Get-Runtime.addBinding {
    param($SessionId, $Name)
    @{
        method = 'Runtime.addBinding'
        sessionId = $SessionId
        params = @{
            name = $Name
        }
    }
}
function Get-Runtime.enable {
    param($SessionId)
    @{
        method = 'Runtime.enable'
        sessionId = $SessionId
    }
}
function Get-Runtime.evaluate {
    param($SessionId, $Expression)
    @{
        method = 'Runtime.evaluate'
        sessionId = $SessionId
        params = @{
            expression = $Expression
        }
    }
}

function Get-Target.createTarget {
    param($Url)
    @{
        method = 'Target.createTarget'
        params = @{
            url = $Url
        }
    }
}

function Get-Target.createBrowserContext {
    param()
    @{
        method = 'Target.createBrowserContext'
        params = @{
            disposeOnDetach = $true
        }
    }
}

function Get-Target.setAutoAttach {
    param()
    @{
        method = 'Target.setAutoAttach'
        params = @{
            autoAttach = $true
            waitForDebuggerOnStart = $false
            filter = @(
                @{
                    type = 'service_worker'
                    exclude = $true
                },
                @{
                    type = 'worker'
                    exclude = $true
                },
                @{
                    type = 'browser'
                    exclude = $true
                },
                @{
                    type = 'tab'
                    exclude = $true
                },
                # @{
                #     type = 'other'
                #     exclude = $true
                # },
                @{
                    type = 'background_page'
                    exclude = $true
                },
                @{}
            )
            flatten = $true
        }
    }
}

function Get-Target.setDiscoverTargets {
    param($Url)
    @{
        method = 'Target.setDiscoverTargets'
        params = @{
            discover = $true
            filter = @(
                @{
                    type = 'service_worker'
                    exclude = $true
                },
                @{
                    type = 'worker'
                    exclude = $true
                },
                @{
                    type = 'browser'
                    exclude = $true
                },
                @{
                    type = 'tab'
                    exclude = $true
                },
                # @{
                #     type = 'other'
                #     exclude = $true
                # },
                @{
                    type = 'background_page'
                    exclude = $true
                },
                @{}
            )
        }
    }
}
