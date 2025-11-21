Write-Host "Сброс Winsock..."
netsh winsock reset

Write-Host "Сброс IP..."
netsh int ip reset

Write-Host "Очистка DNS..."
ipconfig /flushdns
