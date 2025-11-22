# --- INÍCIO DO SCRIPT DE INSTALAÇÃO ---

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Instalação - Limpeza Avançada by EdyOne" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

# --- BLOCO 1: AJUSTE DA POLÍTICA DE EXECUÇÃO DO POWERSHELL ---

Write-Host " [1/2] Verificando a política de execução do PowerShell..." -ForegroundColor Yellow

# Obtém a política de execução para o escopo do usuário atual, sem exibir erros se não existir.
 $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue

# Se a política for 'Restricted', ela impede a execução de scripts. Precisamos alterá-la.
if ($currentPolicy -eq 'Restricted') {
    Write-Host "   Política 'Restricted' detectada. Alterando para 'RemoteSigned' para permitir a execução de scripts locais..." -ForegroundColor Yellow
    # Define a política para 'RemoteSigned', que permite scripts locais e exige assinatura em scripts baixados da internet.
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "   ✅ Política de execução alterada com sucesso!" -ForegroundColor Green
} else {
    Write-Host "   ✅ Política de execução já está configurada como '$currentPolicy'." -ForegroundColor Green
}
Write-Host ""

# --- BLOCO 2: CRIAÇÃO DO ATALHO NA ÁREA DE TRABALHO COM ÍCONE PERSONALIZADO ---

Write-Host " [2/2] Configurando o atalho na área de trabalho..." -ForegroundColor Yellow

# Define o caminho para a área de trabalho do usuário atual.
 $desktopPath = [System.Environment]::GetFolderPath('Desktop')
 $shortcutPath = Join-Path $desktopPath "Limpeza Avançada.lnk"

# --- NOVA FUNCIONALIDADE: Download do Ícone Personalizado ---
Write-Host "   Baixando ícone personalizado..." -ForegroundColor Yellow

# Define a URL do ícone no seu repositório GitHub.
 $iconUrl = "https://github.com/edgardocorrea/LimpezaAvancada/raw/refs/heads/main/icone.ico"

# Define um caminho local para salvar o ícone, dentro da pasta de dados locais do usuário.
 $iconLocalPath = "$env:LOCALAPPDATA\LimpezaAvancada\icone.ico"
 $iconDir = Split-Path $iconLocalPath -Parent

# Cria o diretório se ele não existir.
if (-not (Test-Path $iconDir)) {
    New-Item -Path $iconDir -ItemType Directory -Force | Out-Null
}

# Baixa o ícone da URL e o salva no caminho local.
try {
    Invoke-WebRequest -Uri $iconUrl -OutFile $iconLocalPath -ErrorAction Stop
    Write-Host "   ✅ Ícone baixado com sucesso para: $iconLocalPath" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️ Falha ao baixar o ícone personalizado. Usando um ícone padrão do sistema." -ForegroundColor Yellow
    # Se o download falhar, usamos um ícone padrão do Windows como fallback.
    $iconLocalPath = "%SystemRoot%\System32\shell32.dll, 266"
}


# Cria o objeto COM do Shell para manipular o atalho.
 $shell = New-Object -ComObject WScript.Shell
 $shortcut = $shell.CreateShortcut($shortcutPath)

# Configura as propriedades do atalho.
 $shortcut.TargetPath = "powershell.exe"
 $shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList '-ExecutionPolicy Bypass -Command `$script = Invoke-RestMethod https://raw.githubusercontent.com/edgardocorrea/LimpezaAvancada/refs/heads/main/LimpezaAvancada.ps1; Invoke-Expression `$script'`""
 $shortcut.WorkingDirectory = "%windir%"
 $shortcut.Description = "Executa a Limpeza Avançada do Windows by EdyOne"
# Define o local do ícone para o nosso ícone personalizado baixado.
 $shortcut.IconLocation = "`"$iconLocalPath`", 0"

# Salva o atalho na área de trabalho.
 $shortcut.Save()

Write-Host "   ✅ Atalho criado com sucesso em: $shortcutPath" -ForegroundColor Green

# --- ALTERAÇÃO: Forçar atualização dos ícones da área de trabalho ---
Write-Host "   Atualizando os ícones da área de trabalho..." -ForegroundColor Yellow
try {
    # Define o código C# para chamar a API nativa do Windows
    $signature = @"
    using System;
    using System.Runtime.InteropServices;
    public class DesktopRefresh {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
        public static void Refresh() {
            // Envia uma mensagem de que as configurações do ambiente mudaram
            SendMessageTimeout(new IntPtr(0xFFFF), 0x1A, IntPtr.Zero, "Environment", 0, 100, out IntPtr result);
        }
    }
"@
    # Adiciona o código C# à sessão atual do PowerShell
    Add-Type -TypeDefinition $signature -ErrorAction Stop
    # Executa a função de atualização
    [DesktopRefresh]::Refresh()
    Write-Host "   ✅ Ícones da área de trabalho atualizados." -ForegroundColor Green
} catch {
    Write-Host "   (!) Não foi possível atualizar os ícones automaticamente. Tente atualizar a área de trabalho manualmente (tecla F5)." -ForegroundColor Yellow
}

Write-Host ""

# --- BLOCO 3: FINALIZAÇÃO E INSTRUÇÕES AO USUÁRIO ---
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " INSTALAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Para executar a limpeza, utilize o atalho na área de trabalho:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Dê um duplo-clique no ícone 'Limpeza Avançada' 🪄" -ForegroundColor Gray
Write-Host "   (O script sempre baixará a versão mais recente do GitHub)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " NOTAS IMPORTANTES:" -ForegroundColor Yellow
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "• Execute sempre como Administrador para uma limpeza completa." -ForegroundColor Gray
Write-Host "• A janela do PowerShell fica oculta durante a execução." -ForegroundColor Gray
Write-Host "• Um ícone personalizado foi baixado para o atalho." -ForegroundColor Gray
Write-Host "• Se o ícone não aparecer, pressione F5 na área de trabalho." -ForegroundColor Gray
