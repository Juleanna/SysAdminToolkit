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

Write-Host "Виконую команду на $ComputerName..."

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    Write-Host "Команду завершено." -ForegroundColor Green
} catch {
    Write-Error "Помилка віддаленого виконання: $($_.Exception.Message)"
    exit 1
}
