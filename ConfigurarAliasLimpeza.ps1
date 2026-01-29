# =============================================================
#     INSTALADOR AVANÇADO
# =============================================================

# --- AUTOELEVAÇÃO ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Elevando permissões para Administrador..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Instalação Avançada - Limpeza Avançada by EdyOne" -ForegroundColor White
Write-Host "  (Versão Local com Arquivo .bat)" -ForegroundColor Gray
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

# --- CONFIGURAÇÕES GERAIS ---

 $localFolder = "$env:LOCALAPPDATA\LimpezaAvancada"
 $iconLocalPath = "$localFolder\icone.ico"
 $logFile = "$localFolder\log.txt"

# NOVOS CAMINHOS
 $localScriptPath = "$localFolder\LimpezaAvancada.ps1"  # O script será baixado e salvo aqui
 $batchFilePath = "$localFolder\ExecutarLimpeza.bat"    # O arquivo .bat será criado aqui

# URL CORRIGIDA (Branch MAIN)
 $mainScriptURL = "https://raw.githubusercontent.com/edgardocorrea/LimpezaAvancada/main/LimpezaAvancada.ps1"
 $iconURL = "https://github.com/edgardocorrea/LimpezaAvancada/raw/refs/heads/main/icone.ico"

# --- CRIA PASTA LOCAL ---
if (-not (Test-Path $localFolder)) {
    New-Item -Path $localFolder -ItemType Directory -Force | Out-Null
}

Write-Host "Pasta de instalação: $localFolder" -ForegroundColor Green

# --- CRIA LOG ---
Add-Content -Path $logFile -Value "Log iniciado pelo instalador em $(Get-Date)" -Encoding UTF8 -Force

# --- PASSO 1: BAIXAR O SCRIPT PRINCIPAL PARA USO LOCAL ---
Write-Host "Baixando script principal (LimpezaAvancada.ps1)..." -ForegroundColor Yellow
try {
    # Verifica se a pasta existe antes de tentar baixar
    Invoke-WebRequest -Uri $mainScriptURL -OutFile $localScriptPath -ErrorAction Stop
    Write-Host "   Script principal baixado com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "   ERRO FATAL: Não foi possível baixar o script principal: $_" -ForegroundColor Red
    Write-Host "   Verifique sua conexão com a internet ou a URL do GitHub." -ForegroundColor Red
    Pause
    exit
}

# --- PASSO 2: CRIAR O ARQUIVO DE LOTE (.BAT) ---
Write-Host "Criando arquivo de execução (.bat)..." -ForegroundColor Yellow

# Aqui está o conteúdo do seu arquivo de lote
 $batchContent = @"
@echo off
:: ============================================
:: Limpeza Avançada by EdyOne
:: Executa com privilégios de Administrador
:: ============================================

echo.
echo ================================================
echo   Limpeza Avancada do Windows by EdyOne
echo ================================================
echo.

:: Verifica se já está rodando como Admin
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Executando como Administrador...
    goto :ExecutarLimpeza
) else (
    echo [!] Solicitando privilegios de Administrador...
    echo.
    
    :: Solicita elevação e executa o script PowerShell local
    powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:ExecutarLimpeza
echo.
echo [1/2] Iniciando script de limpeza...
echo.

:: Executa o script PowerShell local (que está na mesma pasta)
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0LimpezaAvancada.ps1"

echo.
echo [2/2] Limpeza concluida!
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
exit
"@

Set-Content -Path $batchFilePath -Value $batchContent -Encoding ASCII -Force
Write-Host "   Arquivo .bat criado." -ForegroundColor Green

# --- PASSO 3: BAIXAR ÍCONE ---
Write-Host "Baixando ícone..." -ForegroundColor Yellow
try {
    Invoke-WebRequest $iconURL -OutFile $iconLocalPath -ErrorAction Stop
    Write-Host "   Ícone baixado." -ForegroundColor Green
} catch {
    Write-Host "   Erro ao baixar ícone. Usando padrão." -ForegroundColor Yellow
    $iconLocalPath = "%SystemRoot%\System32\shell32.dll,265"
}

# --- PASSO 4: CRIAR ATALHO (.LNK) ---
Write-Host "Criando atalho na Área de Trabalho..." -ForegroundColor Yellow

 $desktopPath = [Environment]::GetFolderPath("Desktop")
 $shortcutPath = Join-Path $desktopPath "Limpeza Avançada.lnk"

 $shell = New-Object -ComObject WScript.Shell
 $shortcut = $shell.CreateShortcut($shortcutPath)

# O atalho agora aponta para o arquivo .bat
 $shortcut.TargetPath = $batchFilePath
 $shortcut.WorkingDirectory = $localFolder
 $shortcut.IconLocation = "$iconLocalPath,0"
 $shortcut.Description = "Limpeza Avançada - by EdyOne"
 $shortcut.Save()

Write-Host "   Atalho criado apontando para o .bat" -ForegroundColor Green

# --- REFRESH DOS ÍCONES ---
Write-Host "Atualizando ícones..." -ForegroundColor Yellow
 $code = @'
using System.Runtime.InteropServices;
public class DesktopRefresh {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
    uint flags, uint timeout, out IntPtr result);
}
'@
if (-not ("DesktopRefresh" -as [type])) {
    try { Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue } catch {}
}
try { [DesktopRefresh]::SendMessageTimeout(0xFFFF,0x1A,0,"Environment",0,1000,[ref]([IntPtr]::Zero)) | Out-Null } catch {}

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " INSTALAÇÃO AVANÇADA CONCLUÍDA (Modo OFFLINE)!" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivos criados:" -ForegroundColor Cyan
Write-Host "  1. Script: $localScriptPath" -ForegroundColor White
Write-Host "  2. Lote:   $batchFilePath" -ForegroundColor White
Write-Host "  3. Atalho: $shortcutPath" -ForegroundColor White
Write-Host ""
Write-Host "O programa agora funciona sem internet após a instalação." -ForegroundColor Gray
