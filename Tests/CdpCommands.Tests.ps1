BeforeAll {
    Import-Module '.\PSChromeDevToolsServer'
    $StartPage = 'about:blank'
    $UriBuilder = [System.UriBuilder]::new($StartPage)
    $UserDataDir = 'D:\The Testing Folder\Edge\TestUserData'
    $BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $global:CdpPage = Start-CdpServer -StartPage $UriBuilder.Uri.AbsoluteUri -UserDataDir $UserDataDir -BrowserPath $BrowserPath -Debug
    $global:CdpServer = $CdpPage.CdpServer
}

AfterAll {
    Stop-CdpServer -CdpPage $CdpPage
}

Describe 'Invoke-CdpNavigate' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'navigates the page' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html'
    }
}

Describe 'Wait-CdpPageLifeCycleEvent' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'sets up testing for Wait-CdpPageLifeCycleEvent' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html'
    }

    It 'waited for NetworkIdle' {
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle -Timeout 5000
        $CdpPage.LoadingState['NetworkIdle'].IsSet | Should -Be $true
    }

    It 'waited for FirstPaint' {
        # Not all sites will have a firstpaint event.
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events FirstPaint -Timeout 5000
        $CdpPage.LoadingState['FirstPaint'].IsSet | Should -Be $true
    }
}

Describe 'Invoke-CdpInputSendKeys' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'sets up testing for Test-CdpSelector' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle, FirstPaint -Timeout 5000
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html'
        $CdpPage.LoadingState['NetworkIdle'].IsSet | Should -Be $true
        $CdpPage.LoadingState['FirstPaint'].IsSet | Should -Be $true
    }

    It 'sent enter to the textbox and navigated' {
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys $([char]13)
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.DocumentURL -eq 'https://www.selenium.dev/selenium/web/single_text_input.html?#' }
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html?#'
        $Node.DocumentURL | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html?#'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle, FirstPaint -Timeout 5000
    }

    It 'sent keys to textbox' {
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'PSChromeDevToolsServer'
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'PSChromeDevToolsServer' }
        $Node.NodeValue | Should -Be 'PSChromeDevToolsServer'
    }
}

Describe 'Test-CdpSelector' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'sets up testing for Test-CdpSelector' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/single_text_input.html'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle, FirstPaint -Timeout 5000
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/single_text_input.html'
        $CdpPage.LoadingState['NetworkIdle'].IsSet | Should -Be $true
        $CdpPage.LoadingState['FirstPaint'].IsSet | Should -Be $true

        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'PSChromeDevToolsServer'
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'PSChromeDevToolsServer' }
        $Node.NodeValue | Should -Be 'PSChromeDevToolsServer'
    }

    It 'found shadowroot keys' {
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'PSChromeDevToolsServer' }
        $Node.NodeValue | Should -Be 'PSChromeDevToolsServer'
    }

    It 'found element by attribute' {
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.Attributes.Name -eq 'autofocus' }
        $Node.Attributes.Name | Should -Contain 'autofocus'
        $Node.NodeName | Should -Be 'input'
    }

    It 'found element by tag name' {
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeName -eq 'input' }
        $Node.NodeName | Should -Be 'input'
    }

    It 'throws when a node is not found after timeout' {
        { Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeName -eq 'invalid node name' } -Timeout 1 } | Should -Throw
    }
}

Describe 'Invoke-CdpInputClickElement' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'sets up testing for Invoke-CdpInputClickElement' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/click_tests/html5_submit_buttons.html'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle, FirstPaint -Timeout 5000
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/click_tests/html5_submit_buttons.html'
        $CdpPage.LoadingState['NetworkIdle'].IsSet | Should -Be $true
        $CdpPage.LoadingState['FirstPaint'].IsSet | Should -Be $true

        Invoke-CdpInputClickElement -CdpPage $CdpPage -FilterScript { $_.Attributes.Name -eq 'id' -and $_.Attributes.Value -eq 'name' } -Click 1
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'PSChromeDevToolsServer'
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'PSChromeDevToolsServer' }
        $Node.NodeValue | Should -Be 'PSChromeDevToolsServer'
    }

    It 'triple clicked and selected all text and replaced the text' {
        Invoke-CdpInputClickElement -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'PSChromeDevToolsServer' } -Click 3 -TopLeft
        Invoke-CdpInputSendKeys -CdpPage $CdpPage -Keys 'ReplacedText!'
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'ReplacedText!' }
        $Node.NodeValue | Should -Be 'ReplacedText!'
    }

    It 'clicked submit and navigated' {
        Invoke-CdpInputClickElement -CdpPage $CdpPage -FilterScript { $_.NodeValue -eq 'Spanned Submit' } -Click 1
        $Node = Test-CdpSelector -CdpPage $CdpPage -FilterScript { $_.DocumentURL -eq 'https://www.selenium.dev/selenium/web/click_tests/submitted_page.html?name=ReplacedText%21' }
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/click_tests/submitted_page.html?name=ReplacedText%21'
        $Node.DocumentURL | Should -Be 'https://www.selenium.dev/selenium/web/click_tests/submitted_page.html?name=ReplacedText%21'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle, FirstPaint -Timeout 5000
    }
}

Describe 'Invoke-CdpRuntimeEvaluate' {
    AfterEach {
        $CdpServer.ShowMessageHistory().error | Where-Object { $null -ne $_ } | Should -Be $null
    }

    It 'sets up testing for Invoke-CdpRuntimeEvaluate' {
        Invoke-CdpPageNavigate -CdpPage $CdpPage -Url 'https://www.selenium.dev/selenium/web/click_frames.html'
        Wait-CdpPageLifeCycleEvent -InputObject $CdpPage -Events NetworkIdle -Timeout 5000
        $CdpPage.LoadingState['NetworkIdle'].IsSet | Should -Be $true
        $CdpPage.TargetInfo['Url'] | Should -Be 'https://www.selenium.dev/selenium/web/click_frames.html'
        $null = $CdpPage | Get-CdpFrame -Url 'https://www.selenium.dev/selenium/web/click_source.html' | Wait-CdpPageLifeCycleEvent -Events NetworkIdle, FirstPaint -Timeout 5000
    }

    It 'can run javascript' {
        Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage -Expression 'document.querySelector("frameset frame").contentDocument.querySelector("[id=bubblesFrom]").innerText'
        $CdpPage.PageInfo['EvaluateResult'].value | Should -BeExactly 'I bubble'
    }

    It 'can await javascript' {
        $Expression = @'
function timedPromise(name, delay) {
    return new Promise(resolve => {
        setTimeout(() => {
            resolve(`${name} resolved`);
        }, delay);
    });
}

async function awaitMultiplePromises() {
    const promise1 = timedPromise("Promise 1", 100);
    const promise2 = timedPromise("Promise 2", 100);
    const promise3 = timedPromise("Promise 3", 100);

    const results = await Promise.all([promise1, promise2, promise3]);

    return 'Promise was awaited.'
}

awaitMultiplePromises();
'@
        Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage -Expression $Expression -AwaitPromise
        $CdpPage.PageInfo['EvaluateResult'].value | Should -BeExactly 'Promise was awaited.'
    }
}
