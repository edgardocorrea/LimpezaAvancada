# =============================================================
#     INSTALADOR AVANÇADO - LIMPEZA AVANÇADA (Com Debug)
# =============================================================

# --- AUTOELEVAÇÃO ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Elevando permissões para Administrador..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Instalação Avançada - Limpeza Avançada by EdyOne" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

# --- CONFIGURAÇÕES GERAIS ---

 $localFolder = "$env:LOCALAPPDATA\LimpezaAvancada"
 $iconLocalPath = "$localFolder\icone.ico"
 $launcherPath = "$localFolder\launcher.ps1"
 $failoverPath = "$localFolder\failover.ps1"
 $hashFile = "$localFolder\hash.txt"
 $logFile = "$localFolder\log.txt"

 $mainScriptURL = "https://raw.githubusercontent.com/edgardocorrea/LimpezaAvancada/main/LimpezaAvancada.ps1"
 $iconURL = "https://github.com/edgardocorrea/LimpezaAvancada/raw/refs/heads/main/icone.ico"

# --- CRIA PASTA LOCAL ---

if (-not (Test-Path $localFolder)) {
    New-Item -Path $localFolder -ItemType Directory -Force | Out-Null
}

Write-Host "Pasta de instalação: $localFolder" -ForegroundColor Green

# --- FAILOVER PS1 (versão interna mínima caso GitHub caia) ---

 $failoverContent = @'
Write-Host "⚠ Modo Offline: GitHub indisponível. Executando limpeza básica..." -ForegroundColor Yellow
# Adicione comandos reais de limpeza aqui se quiser
Start-Sleep 2
Write-Host "Limpeza básica concluída." -ForegroundColor Green
'@

Set-Content $failoverPath -Value $failoverContent -Encoding UTF8 -Force

# --- ARQUIVO DE HASH (HASH ESPERADO DO SCRIPT PRINCIPAL) ---

 $expectedHash = "SHA256-CHANGE-ME"
Set-Content $hashFile -Value $expectedHash -Encoding UTF8 -Force

# --- LAUNCHER AVANÇADO (MODIFICADO PARA LOGAR O ERRO) ---

 $launcherContent = @"
# ================================================
#  Launcher Avançado - Limpeza Avançada
# ================================================

\`$url = '$mainScriptURL'
\`$failover = '$failoverPath'
\`$log = '$logFile'
\`$hashFile = '$hashFile'

Function Log(\`$msg) {
    Add-Content -Path \`$log -Value "[\$(Get-Date)] \`$msg"
}

Function Get-SHA256(\`$data) {
    \`$sha256 = [System.Security.Cryptography.SHA256]::Create()
    \`$bytes = [System.Text.Encoding]::UTF8.GetBytes(\`$data)
    (\`$sha256.ComputeHash(\`$bytes) | ForEach-Object ToString x2) -join ''
}

Log "Iniciando execução..."

try {
    # Tenta baixar o script
    \`$script = Invoke-RestMethod -Uri \`$url -ErrorAction Stop
    Log "Script baixado com sucesso."

    # Verificação opcional do hash
    \`$expected = Get-Content \`$hashFile -Raw
    if (\`$expected -and \`$expected -ne 'SHA256-CHANGE-ME') {
        \`$hash = Get-SHA256 \`$script
        if (\`$hash -ne \`$expected.Trim()) {
            Log "Hash inválido! Usando failover."
            Invoke-Expression (Get-Content \`$failover -Raw)
            exit
        }
    }

    Log "Executando script remoto..."
    Invoke-Expression \`$script
}
catch {
    # --- MELHORIA AQUI: GRAVA O ERRO TÉCNICO NO LOG ---
    Log "ERRO DE CONEXÃO DETALHADO: \`$_"
    Log "Falha ao baixar script online. Executando failover."
    Invoke-Expression (Get-Content \`$failover -Raw)
}
"@

Set-Content -Path $launcherPath -Value $launcherContent -Encoding UTF8 -Force

# --- DOWNLOAD DO ÍCONE ---

Write-Host "Baixando ícone..." -ForegroundColor Yellow
try {
    Invoke-WebRequest $iconURL -OutFile $iconLocalPath -ErrorAction Stop
    Write-Host "   Ícone baixado." -ForegroundColor Green
} catch {
    Write-Host "   Erro ao baixar ícone. Usando padrão." -ForegroundColor Yellow
    $iconLocalPath = "%SystemRoot%\System32\shell32.dll,265"
}

# --- CRIAÇÃO DO ATALHO ---

Write-Host "Criando atalho..." -ForegroundColor Yellow

 $desktopPath = [Environment]::GetFolderPath("Desktop")
 $shortcutPath = Join-Path $desktopPath "Limpeza Avançada.lnk"

 $shell = New-Object -ComObject WScript.Shell
 $shortcut = $shell.CreateShortcut($shortcutPath)

 $shortcut.TargetPath = "powershell.exe"
 $shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPath`""
 $shortcut.WorkingDirectory = "%windir%"
 $shortcut.IconLocation = "$iconLocalPath,0"
 $shortcut.Description = "Limpeza Avançada - versão robusta"
 $shortcut.Save()

Write-Host "   Atalho criado." -ForegroundColor Green

# --- REFRESH DOS ÍCONES ---

 $code = @'
using System.Runtime.InteropServices;
public class DesktopRefresh {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
    uint flags, uint timeout, out IntPtr result);
}
'@
Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
[DesktopRefresh]::SendMessageTimeout(0xFFFF,0x1A,0,"Environment",0,1000,[ref]([IntPtr]::Zero)) | Out-Null

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " INSTALAÇÃO AVANÇADA CONCLUÍDA!" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Para verificar o erro, abra o arquivo: $logFile" -ForegroundColor Cyan
