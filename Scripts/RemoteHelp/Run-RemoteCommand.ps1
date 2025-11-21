param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true, ParameterSetName="ScriptBlock")]
    [ScriptBlock]$ScriptBlock,

    [Parameter(Mandatory=$true, ParameterSetName="CommandText")]
    [string]$CommandText,

    [Parameter(ParameterSetName="ScriptBlock")]
    [Parameter(ParameterSetName="CommandText")]
    [object[]]$ArgumentList = @()
)

if ($PSCmdlet.ParameterSetName -eq 'CommandText') {
    $ScriptBlock = [ScriptBlock]::Create($CommandText)
}

Write-Host "Выполняю команду на $ComputerName..."

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    Write-Host "Команда завершена."
} catch {
    Write-Error "Ошибка удалённого выполнения: $($_.Exception.Message)"
    exit 1
}
