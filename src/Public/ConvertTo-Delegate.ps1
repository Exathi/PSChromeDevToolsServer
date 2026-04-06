function ConvertTo-Delegate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [System.Management.Automation.PSMethod[]]$Method,
        [Parameter(Mandatory)]
        [object]$Target
    )

    process {
        $reflectionMethod = if ($Target.GetType().Name -eq 'PSCustomObject') {
            $Target.psobject.GetType().GetMethod($Method.Name)
        } else {
            $Target.GetType().GetMethod($Method.Name)
        }
        $parameterTypes = [System.Linq.Enumerable]::Select($reflectionMethod.GetParameters(), [func[object, object]] { $args[0].parametertype })
        $concatMethodTypes = $parameterTypes + $reflectionMethod.ReturnType
        $delegateType = [System.Linq.Expressions.Expression]::GetDelegateType($concatMethodTypes)
        $delegate = [delegate]::CreateDelegate($delegateType, $Target, $reflectionMethod.Name)
        $delegate
    }
}
