$script:Powershell = $null

function New-UnboundClassInstance ([Type] $type, [object[]] $arguments = $null) {
    if ($null -eq $script:Powershell) {
        $script:Powershell = [powershell]::Create()
        $script:Powershell.AddScript({
                function New-UnboundClassInstance ([Type] $type, [object[]] $arguments) {
                    [activator]::CreateInstance($type, $arguments)
                }
            }.Ast.GetScriptBlock()
        ).Invoke()
        $script:Powershell.Commands.Clear()
    }

    try {
        if ($null -eq $arguments) { $arguments = @() }
        $result = $script:Powershell.AddCommand('New-UnboundClassInstance').
        AddParameter('type', $type).
        AddParameter('arguments', $arguments).
        Invoke()
        return $result
    } finally {
        $script:Powershell.Commands.Clear()
    }
}
