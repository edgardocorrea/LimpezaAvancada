# --- Início da Instalação ---

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Instalação Completa - Limpeza Avançada by EdyOne" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

# --- Passo 1: Configurar a Política de Execução ---

Write-Host " [1/3] Verificando a política de execução do PowerShell..." -ForegroundColor Yellow

$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue

if ($currentPolicy -eq 'Restricted') {
    Write-Host "   Política 'Restricted' detectada. Alterando para 'RemoteSigned'..." -ForegroundColor Yellow
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "    Política de execução alterada com sucesso!" -ForegroundColor Green
} else {
    Write-Host "    Política de execução já está configurada como '$currentPolicy'." -ForegroundColor Green
}
Write-Host ""

# --- Passo 2: Criar o Alias no Perfil do PowerShell ---

Write-Host " [2/3] Configurando o alias 'limpeza' no seu perfil do PowerShell..." -ForegroundColor Yellow

if (-not (Test-Path $PROFILE)) {
    Write-Host "   Arquivo de perfil não encontrado. Criando um novo em: $PROFILE" -ForegroundColor Yellow
    New-Item -Path $PROFILE -ItemType File -Force | Out-Null
}

$functionCode = @'

# Função e Alias para a Limpeza Avançada by EdyOne
function LimpezaAvancada {
    irm "https://raw.githubusercontent.com/edgardocorrea/LimpezaAvancada/refs/heads/main/LimpezaAvancada.ps1" | iex
}

Set-Alias -Name limpeza -Value LimpezaAvancada
'@

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -notmatch 'Set-Alias -Name limpeza') {
    Add-Content -Path $PROFILE -Value $functionCode
    Write-Host "    Alias 'limpeza' adicionado ao perfil com sucesso!" -ForegroundColor Green
} else {
    Write-Host "   (!) Alias 'limpeza' já existe no seu perfil. Nenhuma alteração necessária." -ForegroundColor Cyan
}
Write-Host ""

# --- Passo 3: Criar Atalho na Área de Trabalho ---

Write-Host " [3/3] Criando atalho na área de trabalho..." -ForegroundColor Yellow

$desktopPath = [System.Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath "Limpeza Avançada.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)

# Remove -NoProfile e eleva como Admin automaticamente
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -Command `"Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -Command limpeza'`""
$shortcut.WorkingDirectory = "%windir%"
$shortcut.Description = "Executa a Limpeza Avançada do Windows by EdyOne"
$shortcut.IconLocation = "%SystemRoot%\System32\shell32.dll, 266"

$shortcut.Save()

Write-Host " Atalho criado com sucesso em: $shortcutPath" -ForegroundColor Green
Write-Host ""

# --- Finalização e Instruções ---
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " INSTALAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Você agora tem DUAS formas de executar a limpeza:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. NO TERMINAL (PowerShell):" -ForegroundColor White
Write-Host "   Abra uma NOVA janela do PowerShell e digite:" -ForegroundColor Gray
Write-Host "   limpeza" -ForegroundColor Yellow -BackgroundColor DarkGray
Write-Host ""
Write-Host "2. PELA ÁREA DE TRABALHO:" -ForegroundColor White
Write-Host "   Dê um duplo-clique no ícone 'Limpeza Avançada' 🪄" -ForegroundColor Gray
Write-Host "   (O atalho pedirá permissões de Administrador automaticamente)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " NOTAS IMPORTANTES:" -ForegroundColor Yellow
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "• O alias 'limpeza' só funciona em NOVAS janelas do PowerShell" -ForegroundColor Gray
Write-Host "• O atalho sempre baixa a versão mais recente do GitHub" -ForegroundColor Gray
Write-Host "• Sempre execute como Administrador para limpeza completa" -ForegroundColor Gray
Write-Host ""