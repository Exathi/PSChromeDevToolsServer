function Invoke-CdpRuntimeEvaluate {
    <#
		.SYNOPSIS
		Run javascript on the browser and return the responses in:
		$CdpPage.PageInfo['EvaluateResult'] = $Response.result.result
		$CdpPage.PageInfo['EvaluateResponse'] = $Response
		.PARAMETER Expression
		The javascript expression to run.
		.PARAMETER AwaitPromise
		Use if the Expression includes a promise that needs to be awaited.

		.EXAMPLE
		This returns after ~3-4 seconds rather than 2+2+2=6 seconds
		If AwaitPromise was not used, Invoke-CdpRuntimeEvaluate will return immediately with $Result.result.result = javascript promise object.

		$Expression = @'
function timedPromise(name, delay) {
	return new Promise(resolve => {
		setTimeout(() => {
			resolve(`${name} resolved`);
		}, delay);
	});
}

async function awaitMultiplePromises() {
	const promise1 = timedPromise("Promise 1", 2000);
	const promise2 = timedPromise("Promise 2", 2000);
	const promise3 = timedPromise("Promise 3", 2000);

	const results = await Promise.all([promise1, promise2, promise3]);

	const displayBox = document.querySelector("[id=textInput]");
	displayBox.value = results;

	return 'Promise was awaited.'
}

awaitMultiplePromises();
'@
	$StartTime = Get-Date
	$Result = Invoke-CdpRuntimeEvaluate -CdpPage $CdpPage -Expression $Expression -AwaitPromise
	$EndTime = Get-Date
	($EndTime - $StartTime).TotalSeconds
	$Result.result.result

	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [CdpPage]$CdpPage,
        [Parameter(Mandatory)]
        [string]$Expression,
        [switch]$AwaitPromise
    )

    process {
        $CdpServer = $CdpPage.CdpServer
        $SessionId = $CdpPage.TargetInfo['SessionId']
        $Command = Get-Runtime.evaluate $SessionId $Expression
        $Command.params.uniqueContextId = "$($CdpPage.PageInfo['RuntimeUniqueId'])"
        if ($AwaitPromise) { $Command.params.awaitPromise = $true }
        $Response = $CdpServer.SendCommand($Command, [WaitForResponse]::Message)

        $CdpPage.PageInfo['EvaluateResult'] = $Response.result.result
        $CdpPage.PageInfo['EvaluateResponse'] = $Response

        $_
    }
}
