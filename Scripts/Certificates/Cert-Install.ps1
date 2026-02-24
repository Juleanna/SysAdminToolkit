<#
.SYNOPSIS
    Встановлює PFX-сертифікат у вказане сховище.
.DESCRIPTION
    Імпортує PFX-файл сертифіката до заданого сховища (за замовчуванням LocalMachine\My).
    Використовує X509Certificate2 та X509Store для безпечного встановлення.
    Потребує прав адміністратора.
.PARAMETER PfxPath
    Шлях до PFX-файлу сертифіката. Обов'язковий параметр.
.PARAMETER Password
    Пароль для PFX-файлу. Обов'язковий параметр.
.PARAMETER StoreName
    Назва сховища сертифікатів. За замовчуванням 'My'.
.PARAMETER StoreLocation
    Розташування сховища. За замовчуванням 'LocalMachine'.
.EXAMPLE
    .\Cert-Install.ps1 -PfxPath "C:\certs\mycert.pfx" -Password "P@ssw0rd"
    Встановлює сертифікат у LocalMachine\My.
.EXAMPLE
    .\Cert-Install.ps1 -PfxPath "C:\certs\mycert.pfx" -Password "P@ssw0rd" -StoreName "Root" -StoreLocation "CurrentUser"
    Встановлює сертифікат у CurrentUser\Root.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$PfxPath,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [string]$StoreName = 'My',

    [ValidateSet('LocalMachine','CurrentUser')]
    [string]$StoreLocation = 'LocalMachine'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

# Перевірка прав адміністратора
Assert-Administrator

Write-TkLog "Запуск встановлення сертифіката: $PfxPath -> $StoreLocation\$StoreName" -Level INFO

# Перевірка наявності файлу
if (-not (Test-Path $PfxPath)) {
    $msg = "PFX-файл не знайдено: $PfxPath"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Перевірка розширення файлу
$ext = [System.IO.Path]::GetExtension($PfxPath).ToLower()
if ($ext -notin '.pfx', '.p12') {
    $msg = "Непідтримуваний формат файлу: $ext. Очікується .pfx або .p12"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

$cert = $null
$store = $null

try {
    # Завантаження сертифіката з PFX
    Write-Host "Завантаження сертифіката з файлу..." -ForegroundColor Cyan
    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        $PfxPath,
        $securePassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bor
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )

    Write-Host "Сертифікат завантажено:" -ForegroundColor Cyan
    Write-Host "  Subject:    $($cert.Subject)"
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  NotBefore:  $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  NotAfter:   $($cert.NotAfter.ToString('yyyy-MM-dd HH:mm:ss'))"

    # Відкриття сховища та додавання сертифіката
    Write-Host "`nВстановлення у сховище $StoreLocation\$StoreName..." -ForegroundColor Cyan
    $storeLocationEnum = [System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $storeLocationEnum)
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($cert)
    $store.Close()

    $msg = "Сертифікат успішно встановлено: $($cert.Subject) [Thumbprint: $($cert.Thumbprint)]"
    Write-Host $msg -ForegroundColor Green
    Write-TkLog $msg -Level INFO
} catch {
    $msg = "Не вдалося встановити сертифікат: $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
} finally {
    if ($cert) {
        try { $cert.Dispose() } catch {}
    }
    if ($store -and $store.IsOpen) {
        try { $store.Close() } catch {}
    }
}
