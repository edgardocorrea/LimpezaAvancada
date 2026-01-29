#Requires -RunAsAdministrator

# Oculta a janela do PowerShell (CMD)
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# ==============================================================================
# CONFIGURAÇÕES E INICIALIZAÇÃO
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"

# Configurações globais
$script:Config = @{
    ServiceTimeout = 10          # Timeout para parar serviços (segundos)
    ProcessKillTimeout = 3       # Timeout para fechar processos (segundos)
    RetryAttempts = 3           # Tentativas de retry
    RetryDelayMs = 1000         # Delay inicial entre retries (ms)
    DryRun = $false             # Modo simulação (não deleta nada)
    MaxConcurrentJobs = 3       # Jobs paralelos máximos
}

# Cores para console
$script:Colors = @{
    Header  = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "White"
    Stat    = "Magenta"
}

# Estatísticas globais
$script:Stats = @{
    TotalFiles = 0
    TotalSize = 0
    DeletedFiles = 0
    DeletedSize = 0
    FailedOperations = 0
    SkippedOperations = 0
    StartTime = Get-Date
    Operations = [System.Collections.ArrayList]@()
    Warnings = [System.Collections.ArrayList]@()
}

# Controle de cancelamento
$script:CancelRequested = $false
$script:RunningJobs = [System.Collections.ArrayList]@()

# ==============================================================================
# FUNÇÕES AUXILIARES DE SISTEMA
# ==============================================================================

function Test-FileInUse {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) { return $false }
    
    try {
        $file = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
        $file.Close()
        return $false
    } catch {
        return $true
    }
}

function Get-LockedFiles {
    param([string]$FolderPath)
    
    if (-not (Test-Path $FolderPath)) { return @() }
    
    $lockedFiles = @()
    Get-ChildItem -Path $FolderPath -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-FileInUse -Path $_.FullName) {
            $lockedFiles += $_.FullName
        }
    }
    
    return $lockedFiles
}

function Stop-ServiceWithTimeout {
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 10
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        if ($service.Status -eq 'Stopped') {
            return @{Success = $true; Message = "Serviço já estava parado"}
        }
        
        # Tenta parar o serviço de forma assíncrona
        $job = Start-Job -ScriptBlock {
            param($svcName)
            Stop-Service -Name $svcName -Force -ErrorAction Stop
        } -ArgumentList $ServiceName
        
        # Aguarda com timeout
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        
        if ($completed) {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            
            # Verifica se realmente parou
            $service.Refresh()
            if ($service.Status -eq 'Stopped') {
                return @{Success = $true; Message = "Serviço parado com sucesso"}
            } else {
                return @{Success = $false; Message = "Serviço não respondeu"}
            }
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            return @{Success = $false; Message = "Timeout ao parar serviço"}
        }
    } catch {
        return @{Success = $false; Message = "Erro: $($_.Exception.Message)"}
    }
}

function Stop-ProcessWithTimeout {
    param(
        [string]$ProcessName,
        [int]$TimeoutSeconds = 3
    )
    
    try {
        $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        
        if (-not $processes) {
            return @{Success = $true; Message = "Processo não estava em execução"; Count = 0}
        }
        
        $processCount = $processes.Count
        
        # Tenta fechar graciosamente primeiro
        $processes | ForEach-Object { 
            $_.CloseMainWindow() | Out-Null
        }
        
        Start-Sleep -Seconds 1
        
        # Verifica se fechou
        $remainingProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        
        if (-not $remainingProcesses) {
            return @{Success = $true; Message = "Processos fechados graciosamente"; Count = $processCount}
        }
        
        # Force kill se necessário
        $remainingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        
        Start-Sleep -Milliseconds 500
        
        # Verificação final
        $finalCheck = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        
        if (-not $finalCheck) {
            return @{Success = $true; Message = "Processos finalizados com força"; Count = $processCount}
        } else {
            return @{Success = $false; Message = "Alguns processos não puderam ser fechados"; Count = $finalCheck.Count}
        }
    } catch {
        return @{Success = $false; Message = "Erro: $($_.Exception.Message)"; Count = 0}
    }
}

function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [int]$InitialDelayMs = 1000
    )
    
    $attempt = 1
    $delay = $InitialDelayMs
    
    while ($attempt -le $MaxAttempts) {
        try {
            $result = & $ScriptBlock
            return @{Success = $true; Result = $result; Attempts = $attempt}
        } catch {
            if ($attempt -eq $MaxAttempts) {
                return @{Success = $false; Error = $_.Exception.Message; Attempts = $attempt}
            }
            
            Start-Sleep -Milliseconds $delay
            $delay *= 2  # Backoff exponencial
            $attempt++
        }
    }
}

# ==============================================================================
# FUNÇÕES DE INTERFACE GRÁFICA
# ==============================================================================

function Show-ProgressWindow {
    param([string]$Title = "Limpeza Avançada do Windows - by EdyOne")
    
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = $Title
    $script:Form.Size = New-Object System.Drawing.Size(650, 500)
    $script:Form.StartPosition = "CenterScreen"
    $script:Form.FormBorderStyle = "FixedDialog"
    $script:Form.MaximizeBox = $false
    $script:Form.TopMost = $true
    $script:Form.BackColor = [System.Drawing.Color]::White
    
    # Previne fechamento acidental
    $script:Form.Add_FormClosing({
        param($sender, $e)
        if ($script:ProgressBar.Value -lt 100 -and -not $script:CancelRequested) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "A limpeza ainda está em andamento. Deseja realmente cancelar?",
                "Confirmação",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                $e.Cancel = $true
            } else {
                $script:CancelRequested = $true
                # Cancela jobs em execução
                $script:RunningJobs | ForEach-Object {
                    Stop-Job -Job $_ -ErrorAction SilentlyContinue
                    Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
                }
            }
        }
    })
    
    # Header com logo
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Location = New-Object System.Drawing.Point(0, 0)
    $headerPanel.Size = New-Object System.Drawing.Size(650, 80)
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $script:Form.Controls.Add($headerPanel)
    
    # Label de título
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(15, 10)
    $titleLabel.Size = New-Object System.Drawing.Size(620, 28)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Text = "LIMPEZA AVANÇADA DO WINDOWS"
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($titleLabel)
    
    # Créditos
    $creditsLabel = New-Object System.Windows.Forms.Label
    $creditsLabel.Location = New-Object System.Drawing.Point(15, 40)
    $creditsLabel.Size = New-Object System.Drawing.Size(620, 20)
    $creditsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $creditsLabel.Text = "Desenvolvido by EdyOne =D"
    $creditsLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $creditsLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($creditsLabel)
    
    # Modo DryRun
    if ($script:Config.DryRun) {
        $dryRunLabel = New-Object System.Windows.Forms.Label
        $dryRunLabel.Location = New-Object System.Drawing.Point(15, 58)
        $dryRunLabel.Size = New-Object System.Drawing.Size(620, 18)
        $dryRunLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $dryRunLabel.Text = "(!) MODO SIMULAÇÃO ATIVO - Nenhum arquivo será deletado"
        $dryRunLabel.ForeColor = [System.Drawing.Color]::Yellow
        $dryRunLabel.BackColor = [System.Drawing.Color]::Transparent
        $headerPanel.Controls.Add($dryRunLabel)
    }
    
    # Label de status
    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Location = New-Object System.Drawing.Point(20, 95)
    $script:StatusLabel.Size = New-Object System.Drawing.Size(610, 25)
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $script:StatusLabel.Text = "Iniciando análise do sistema..."
    $script:Form.Controls.Add($script:StatusLabel)
    
    # Barra de progresso principal
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point(20, 130)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(610, 35)
    $script:ProgressBar.Style = "Continuous"
    $script:Form.Controls.Add($script:ProgressBar)
    
    # Label de percentual
    $script:PercentLabel = New-Object System.Windows.Forms.Label
    $script:PercentLabel.Location = New-Object System.Drawing.Point(20, 170)
    $script:PercentLabel.Size = New-Object System.Drawing.Size(610, 20)
    $script:PercentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $script:PercentLabel.Text = "0% Concluído"
    $script:PercentLabel.TextAlign = "MiddleCenter"
    $script:Form.Controls.Add($script:PercentLabel)
    
    # TextBox de detalhes
    $script:DetailsBox = New-Object System.Windows.Forms.TextBox
    $script:DetailsBox.Location = New-Object System.Drawing.Point(20, 200)
    $script:DetailsBox.Size = New-Object System.Drawing.Size(610, 200)
    $script:DetailsBox.Multiline = $true
    $script:DetailsBox.ScrollBars = "Vertical"
    $script:DetailsBox.ReadOnly = $true
    $script:DetailsBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $script:DetailsBox.BackColor = [System.Drawing.Color]::Black
    $script:DetailsBox.ForeColor = [System.Drawing.Color]::LimeGreen
    $script:Form.Controls.Add($script:DetailsBox)
    
    # Label de tempo estimado
    $script:TimeLabel = New-Object System.Windows.Forms.Label
    $script:TimeLabel.Location = New-Object System.Drawing.Point(20, 410)
    $script:TimeLabel.Size = New-Object System.Drawing.Size(610, 20)
    $script:TimeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:TimeLabel.Text = ">> Tempo estimado: Calculando..."
    $script:Form.Controls.Add($script:TimeLabel)
    
    # Estatísticas em tempo real
    $script:StatsLabel = New-Object System.Windows.Forms.Label
    $script:StatsLabel.Location = New-Object System.Drawing.Point(20, 435)
    $script:StatsLabel.Size = New-Object System.Drawing.Size(610, 20)
    $script:StatsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:StatsLabel.Text = "💾 Espaço liberado: 0 MB | ⚠️ Falhas: 0 | ⏭️ Ignorados: 0"
    $script:Form.Controls.Add($script:StatsLabel)
    
    $script:Form.Show()
    $script:Form.Refresh()
}

function Update-Progress {
    param(
        [int]$Percent,
        [string]$Status,
        [string]$Detail,
        [switch]$IsWarning,
        [switch]$IsError
    )
    
    if ($script:Form) {
        if ($Percent -ge 0) {
            $script:ProgressBar.Value = [Math]::Min($Percent, 100)
            $script:PercentLabel.Text = "$Percent% Concluído"
        }
        
        if ($Status) {
            $script:StatusLabel.Text = $Status
        }
        
        if ($Detail) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $icon = if ($IsError) { "❌" } elseif ($IsWarning) { "⚠️" } else { "✔️" }
            $script:DetailsBox.AppendText("[$timestamp] $icon $Detail`r`n")
            $script:DetailsBox.SelectionStart = $script:DetailsBox.Text.Length
            $script:DetailsBox.ScrollToCaret()
        }
        
# Atualiza tempo estimado
 $elapsed = (Get-Date) - $script:Stats.StartTime
if ($Percent -gt 5) {
    $totalSeconds = $elapsed.TotalSeconds / ($Percent / 100)
    $remainingSeconds = $totalSeconds - $elapsed.TotalSeconds
    
    if ($remainingSeconds -gt 0) {
        if ($remainingSeconds -lt 60) {
            $script:TimeLabel.Text = ">> Tempo restante: $([Math]::Floor($remainingSeconds))s"
        } else {
            $minutes = [Math]::Floor($remainingSeconds / 60)
            $seconds = [Math]::Floor($remainingSeconds % 60)
            $script:TimeLabel.Text = ">> Tempo restante: ${minutes}m ${seconds}s"
        }
    } else {
        $script:TimeLabel.Text = ">> Tempo restante: Calculando..."
    }
} else {
    $script:TimeLabel.Text = ">> Tempo decorrido: $([Math]::Floor($elapsed.TotalSeconds))s"
}
        
        # Atualiza estatísticas
        $spaceMB = [Math]::Round($script:Stats.DeletedSize, 2)
        $script:StatsLabel.Text = "Espaço liberado: $spaceMB MB | Falhas: $($script:Stats.FailedOperations) | Ignorados: $($script:Stats.SkippedOperations)"
        
        $script:Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ==============================================================================
# FUNÇÕES DE LIMPEZA
# ==============================================================================

function Get-FolderSize {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) { return 0 }
    
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [Math]::Round(($size / 1MB), 2)
    } catch {
        return 0
    }
}

function Format-FileSize {
    param([double]$SizeMB)
    
    if ($SizeMB -eq 0) { return "0 KB" }
    if ($SizeMB -lt 0.01) { return "<10 KB" }
    if ($SizeMB -lt 1) { return "$([Math]::Round($SizeMB * 1024, 2)) KB" }
    if ($SizeMB -lt 1024) { return "$([Math]::Round($SizeMB, 2)) MB" }
    return "$([Math]::Round($SizeMB / 1024, 2)) GB"
}

function Clean-FolderWithRobocopy {
    param(
        [string]$Path,
        [string]$Description
    )
    
    # Verificação robusta no início para evitar o erro "path is null"
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $script:Stats.SkippedOperations++
        $script:Stats.Operations.Add([PSCustomObject]@{
            Location = $Description
            Path = "CAMINHO INVÁLIDO"
            Deleted = "0 MB"
            Status = "⚠️ Erro: Caminho da pasta não foi informado"
        }) | Out-Null
        Update-Progress -Percent -1 -Status "" -Detail "$Description - Erro de configuração: caminho inválido" -IsWarning
        return
    }
    
    if (-not (Test-Path $Path)) {
        $script:Stats.SkippedOperations++
        $script:Stats.Operations.Add([PSCustomObject]@{
            Location = $Description
            Path = $Path
            Deleted = "0 MB"
            Status = "⏭️ Ignorado (pasta não existe)"
        }) | Out-Null
        return
    }
    
    try {
        $sizeBefore = Get-FolderSize -Path $Path
        
        if ($sizeBefore -eq 0) {
            $script:Stats.SkippedOperations++
            $script:Stats.Operations.Add([PSCustomObject]@{
                Location = $Description
                Path = $Path
                Deleted = "0 MB"
                Status = "⏭️ Ignorado (já estava vazio)"
            }) | Out-Null
            Update-Progress -Percent -1 -Status "" -Detail "$Description - Pasta já vazia" -IsWarning
            return
        }
        
        $script:Stats.TotalSize += $sizeBefore
        
        # Verifica arquivos bloqueados
        $lockedFiles = Get-LockedFiles -Path $Path
        if ($lockedFiles.Count -gt 0) {
            $script:Stats.Warnings.Add([PSCustomObject]@{
                Location = $Description
                Issue = "$($lockedFiles.Count) arquivo(s) em uso"
            }) | Out-Null
            Update-Progress -Percent -1 -Status "" -Detail "$Description - $($lockedFiles.Count) arquivo(s) bloqueado(s)" -IsWarning
        }
        
        if ($script:Config.DryRun) {
            $script:Stats.DeletedSize += $sizeBefore
            $script:Stats.Operations.Add([PSCustomObject]@{
                Location = $Description
                Path = $Path
                Deleted = Format-FileSize $sizeBefore
                Status = "🔍 SIMULADO"
            }) | Out-Null
            Update-Progress -Percent -1 -Status "" -Detail "$Description - [SIMULADO] $(Format-FileSize $sizeBefore)"
            return
        }
        
        # Cria pasta temporária vazia
        $emptyFolder = Join-Path $env:TEMP "EmptyFolder_$(Get-Random)"
        New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null
        
        # Usa Robocopy com retry
        $robocopyResult = Invoke-WithRetry -MaxAttempts $script:Config.RetryAttempts -InitialDelayMs $script:Config.RetryDelayMs -ScriptBlock {
            $robocopyArgs = @(
                $emptyFolder,
                $Path,
                '/MIR',
                '/R:1',
                '/W:1',
                '/NJH',
                '/NJS',
                '/NDL',
                '/NFL',
                '/NC',
                '/NS',
                '/NP'
            )
            
            $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
            return $process.ExitCode
        }
        
        # Remove pasta temporária
        Remove-Item -Path $emptyFolder -Force -Recurse -ErrorAction SilentlyContinue
        
        $sizeAfter = Get-FolderSize -Path $Path
        $deleted = $sizeBefore - $sizeAfter
        
        $script:Stats.DeletedSize += $deleted
        
        $status = if ($sizeAfter -eq 0) {
            "✅ Limpo"
        } elseif ($deleted -gt 0) {
            "⚠️ $(Format-FileSize $sizeAfter) restante"
        } else {
            "❌ Falhou"
            $script:Stats.FailedOperations++
        }
        
        $script:Stats.Operations.Add([PSCustomObject]@{
            Location = $Description
            Path = $Path
            Deleted = Format-FileSize $deleted
            Status = $status
        }) | Out-Null
        
        Update-Progress -Percent -1 -Status "" -Detail "$Description - Liberados: $(Format-FileSize $deleted)"
        
    } catch {
        $script:Stats.FailedOperations++
        # <<< MENSAGEM DE ERRO MELHORADA AQUI >>>
        $script:Stats.Operations.Add([PSCustomObject]@{
            Location = $Description
            Path = $Path
            Deleted = "0 MB"
            Status = "❌ Erro de Acesso: Verifique as permissões da pasta"
        }) | Out-Null
        Update-Progress -Percent -1 -Status "" -Detail "$Description - Erro ao acessar o local. O script continuará." -IsError
    }
}



function Clean-TempFolders {
    Update-Progress -Percent 5 -Status "Limpando arquivos temporários..." -Detail "Iniciando limpeza de pastas temporárias"
    
    $tempPaths = @(
        @{Path = "$env:TEMP"; Desc = "Temp do Usuário Atual"},
        @{Path = "$env:LOCALAPPDATA\Temp"; Desc = "Temp Local do Usuário"},
        @{Path = "$env:WINDIR\Temp"; Desc = "Temp do Sistema Windows"},
        @{Path = "$env:WINDIR\Prefetch"; Desc = "Prefetch do Windows"},
        @{Path = "$env:LOCALAPPDATA\CrashDumps"; Desc = "Crash Dumps"},
        @{Path = "$env:WINDIR\SoftwareDistribution\DeliveryOptimization"; Desc = "Delivery Optimization"}
    )
    
    foreach ($item in $tempPaths) {
        if ($script:CancelRequested) { break }
        Clean-FolderWithRobocopy -Path $item.Path -Description $item.Desc
    }
}

function Clean-WindowsUpdate {
    Update-Progress -Percent 20 -Status "Limpando cache do Windows Update..." -Detail "Verificando serviço Windows Update"
    
    if ($script:CancelRequested) { return }
    
    try {
        # Para o serviço com timeout
        Update-Progress -Percent -1 -Status "" -Detail "Parando serviço wuauserv (timeout: $($script:Config.ServiceTimeout)s)..."
        
        $stopResult = Stop-ServiceWithTimeout -ServiceName "wuauserv" -TimeoutSeconds $script:Config.ServiceTimeout
        
        if ($stopResult.Success) {
            Update-Progress -Percent -1 -Status "" -Detail "✅ $($stopResult.Message)"
            
            $updatePaths = @(
                "$env:WINDIR\SoftwareDistribution\Download",
                "$env:WINDIR\SoftwareDistribution\DataStore\Logs"
            )
            
            foreach ($path in $updatePaths) {
                if ($script:CancelRequested) { break }
                Clean-FolderWithRobocopy -Path $path -Description "Windows Update - $(Split-Path $path -Leaf)"
            }
            
            # Reinicia o serviço
            if (-not $script:Config.DryRun) {
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
                Update-Progress -Percent -1 -Status "" -Detail "✅ Serviço wuauserv reiniciado"
            }
        } else {
            $script:Stats.FailedOperations++
            $script:Stats.Warnings.Add([PSCustomObject]@{
                Location = "Windows Update"
                Issue = $stopResult.Message
            }) | Out-Null
            Update-Progress -Percent -1 -Status "" -Detail "⚠️ $($stopResult.Message) - Pulando limpeza" -IsWarning
        }
    } catch {
        $script:Stats.FailedOperations++
        Update-Progress -Percent -1 -Status "" -Detail "❌ Erro ao limpar Windows Update: $($_.Exception.Message)" -IsError
    }
}

function Clean-RecycleBin {
    Update-Progress -Percent 30 -Status "Esvaziando Lixeira..." -Detail "Verificando itens na lixeira"
    
    if ($script:CancelRequested) { return }
    
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0xA)
        $itemCount = $recycleBin.Items().Count
        
        if ($itemCount -gt 0) {
            if ($script:Config.DryRun) {
                Update-Progress -Percent -1 -Status "" -Detail "[SIMULADO] $itemCount itens seriam removidos da lixeira"
            } else {
                Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
                Update-Progress -Percent -1 -Status "" -Detail "✅ Lixeira esvaziada - $itemCount itens removidos"
            }
        } else {
            Update-Progress -Percent -1 -Status "" -Detail "Lixeira já estava vazia"
        }
    } catch {
        $script:Stats.FailedOperations++
        Update-Progress -Percent -1 -Status "" -Detail "⚠️ Erro ao esvaziar lixeira: $($_.Exception.Message)" -IsWarning
    }
}

function Clean-BrowserCache {
    param([string]$BrowserName, [string]$BasePath, [int]$Progress)
    
    if ($script:CancelRequested) { return }
    
    Update-Progress -Percent $Progress -Status "Limpando cache do $BrowserName..." -Detail "Analisando perfis do $BrowserName"
    
    if (-not (Test-Path $BasePath)) {
        $script:Stats.SkippedOperations++
        Update-Progress -Percent -1 -Status "" -Detail "ℹ️ $BrowserName não encontrado"
        return
    }
    
    # Fecha o navegador com timeout
    $processName = switch ($BrowserName) {
        "Microsoft Edge" { "msedge" }
        "Google Chrome" { "chrome" }
        "Mozilla Firefox" { "firefox" }
        "Brave" { "brave" }
        "Vivaldi" { "vivaldi" }
        default { $BrowserName.Split(" ")[0].ToLower() }
    }
    
    $killResult = Stop-ProcessWithTimeout -ProcessName $processName -TimeoutSeconds $script:Config.ProcessKillTimeout
    
    if ($killResult.Success -and $killResult.Count -gt 0) {
        Update-Progress -Percent -1 -Status "" -Detail "✅ $($killResult.Message) ($($killResult.Count) processo(s))"
        Start-Sleep -Milliseconds 1000  # Aguarda handles serem liberados
    }
    
    $profiles = @("Default", "Guest Profile")
    for ($i = 1; $i -le 5; $i++) { $profiles += "Profile $i" }
    
    foreach ($profile in $profiles) {
        if ($script:CancelRequested) { break }
        
        $cachePaths = @(
            "$BasePath\$profile\Cache\Cache_Data",
            "$BasePath\$profile\GPUCache",
            "$BasePath\$profile\Code Cache\js",
            "$BasePath\$profile\Code Cache\wasm",
            "$BasePath\$profile\Service Worker\CacheStorage",
            "$BasePath\$profile\Service Worker\ScriptCache"
        )
        
        foreach ($path in $cachePaths) {
            if ($script:CancelRequested) { break }
            if (Test-Path $path) {
                Clean-FolderWithRobocopy -Path $path -Description "$BrowserName - $profile"
            }
        }
    }
}

function Clean-AllBrowsers {
    $browsers = @(
        @{Name = "Microsoft Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; Progress = 40},
        @{Name = "Google Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data"; Progress = 50},
        @{Name = "Mozilla Firefox"; Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"; Progress = 60},
        @{Name = "Brave"; Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Progress = 65},
        @{Name = "Vivaldi"; Path = "$env:LOCALAPPDATA\Vivaldi\User Data"; Progress = 70},
        @{Name = "Opera"; Path = "$env:APPDATA\Opera Software\Opera Stable"; Progress = 72}
    )
    
    foreach ($browser in $browsers) {
        if ($script:CancelRequested) { break }
        Clean-BrowserCache -BrowserName $browser.Name -BasePath $browser.Path -Progress $browser.Progress
    }
}

function Clean-WindowsLogs {
    Update-Progress -Percent 75 -Status "Limpando logs do sistema..." -Detail "Removendo arquivos de log"
    
    if ($script:CancelRequested) { return }
    
    $logPaths = @(
        "$env:WINDIR\Logs\CBS",
        "$env:WINDIR\Logs\MoSetup",
        "$env:WINDIR\Logs\DISM",
        "$env:WINDIR\Panther",
        "$env:WINDIR\Logs\WindowsUpdate",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    )
    
    foreach ($path in $logPaths) {
        if ($script:CancelRequested) { break }
        if (Test-Path $path) {
            Clean-FolderWithRobocopy -Path $path -Description "Logs - $(Split-Path $path -Leaf)"
        }
    }
    
    # Limpa Event Viewer (requer privilégios elevados)
    Update-Progress -Percent 78 -Status "Limpando Event Viewer..." -Detail "Tentando limpar logs de eventos"
    
    if (-not $script:Config.DryRun) {
        try {
            $clearedCount = 0
            $failedCount = 0
            
            wevtutil el | ForEach-Object {
                if ($script:CancelRequested) { return }
                
                try {
                    wevtutil cl $_ 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $clearedCount++
                    } else {
                        $failedCount++
                    }
                } catch {
                    $failedCount++
                }
            }
            
            if ($clearedCount -gt 0) {
                Update-Progress -Percent -1 -Status "" -Detail "✅ Event Viewer - $clearedCount log(s) limpos, $failedCount protegidos"
            } else {
                Update-Progress -Percent -1 -Status "" -Detail "⚠️ Event Viewer - Nenhum log pôde ser limpo (permissões)" -IsWarning
            }
        } catch {
            $script:Stats.FailedOperations++
            Update-Progress -Percent -1 -Status "" -Detail "⚠️ Erro ao limpar Event Viewer" -IsWarning
        }
    } else {
        Update-Progress -Percent -1 -Status "" -Detail "🔍 [SIMULADO] Event Viewer seria limpo"
    }
}

function Clean-SystemCache {
    Update-Progress -Percent 82 -Status "Limpando cache do sistema..." -Detail "Removendo arquivos de cache do sistema"
    
    if ($script:CancelRequested) { return }
    
    $cachePaths = @(
        @{Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Desc = "Internet Explorer Cache"},
        @{Path = "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"; Desc = "Windows WebCache"},
        @{Path = "$env:LOCALAPPDATA\Microsoft\Windows\Caches"; Desc = "Windows Caches"},
        @{Path = "$env:WINDIR\Installer\$PatchCache$"; Desc = "Installer Patch Cache"},
        @{Path = "$env:LOCALAPPDATA\Temp\Diagnostic"; Desc = "Windows Diagnostic Cache"}
    )
    
    foreach ($item in $cachePaths) {
        if ($script:CancelRequested) { break }
        if (Test-Path $item.Path) {
            Clean-FolderWithRobocopy -Path $item.Path -Description $item.Desc
        }
    }
}

function Clean-ThumbnailCache {
    Update-Progress -Percent 85 -Status "Limpando cache de miniaturas..." -Detail "Removendo thumbcache"
    
    if ($script:CancelRequested) { return }
    
    $thumbPaths = @(
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:LOCALAPPDATA\IconCache.db"
    )
    
    foreach ($path in $thumbPaths) {
        if ($script:CancelRequested) { break }
        if (Test-Path $path) {
            try {
                if ($script:Config.DryRun) {
                    $size = Get-FolderSize -Path $path
                    Update-Progress -Percent -1 -Status "" -Detail "🔍 [SIMULADO] Thumbnail Cache - $(Format-FileSize $size)"
                } else {
                    # Para o Windows Explorer para liberar locks
                    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                    
                    if (Test-Path $path -PathType Container) {
                        Clean-FolderWithRobocopy -Path $path -Description "Thumbnail Cache"
                    } else {
                        Remove-Item -Path $path -Force -ErrorAction Stop
                        Update-Progress -Percent -1 -Status "" -Detail "✅ IconCache.db removido"
                    }
                    
                    # Reinicia o Explorer
                    Start-Process explorer.exe
                }
            } catch {
                Update-Progress -Percent -1 -Status "" -Detail "⚠️ Erro ao limpar cache de miniaturas" -IsWarning
            }
        }
    }
}

function Clean-MemoryDumps {
    Update-Progress -Percent 88 -Status "Limpando dumps de memória..." -Detail "Removendo arquivos de dump"
    
    if ($script:CancelRequested) { return }
    
    $dumpPaths = @(
        "$env:WINDIR\Minidump",
        "$env:WINDIR\Memory.dmp",
        "$env:LOCALAPPDATA\CrashDumps"
    )
    
    foreach ($path in $dumpPaths) {
        if ($script:CancelRequested) { break }
        if (Test-Path $path) {
            if (Test-Path $path -PathType Container) {
                Clean-FolderWithRobocopy -Path $path -Description "Memory Dumps - $(Split-Path $path -Leaf)"
            } else {
                try {
                    if ($script:Config.DryRun) {
                        $size = (Get-Item $path).Length / 1MB
                        Update-Progress -Percent -1 -Status "" -Detail "🔍 [SIMULADO] $path - $(Format-FileSize $size)"
                    } else {
                        $size = (Get-Item $path).Length / 1MB
                        Remove-Item -Path $path -Force -ErrorAction Stop
                        $script:Stats.DeletedSize += $size
                        Update-Progress -Percent -1 -Status "" -Detail "✅ $(Split-Path $path -Leaf) removido - $(Format-FileSize $size)"
                    }
                } catch {
                    Update-Progress -Percent -1 -Status "" -Detail "⚠️ Erro ao remover dump: $path" -IsWarning
                }
            }
        }
    }
}

function Optimize-Drives {
    Update-Progress -Percent 90 -Status "🚀 Executando limpeza de disco do Windows..." -Detail "Iniciando Disk Cleanup"
    
    if ($script:CancelRequested) { return }
    
    # DESABILITADO: Desfragmentação (muito lenta)
    # HABILITADO: Windows Disk Cleanup (rápido e eficaz)
    
    try {
        if ($script:Config.DryRun) {
            Update-Progress -Percent -1 -Status "" -Detail "🔍 [SIMULADO] Disk Cleanup seria executado"
        } else {
            # Executa cleanmgr com argumentos automáticos
            $cleanmgrArgs = "/sagerun:1"
            
            # Configura perfil de limpeza (executa apenas uma vez)
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            $cacheKeys = @(
                "Temporary Files",
                "Temporary Setup Files",
                "Downloaded Program Files",
                "Recycle Bin",
                "Temporary Internet Files"
            )
            
            foreach ($key in $cacheKeys) {
                try {
                    Set-ItemProperty -Path "$regPath\$key" -Name "StateFlags0001" -Value 2 -ErrorAction SilentlyContinue
                } catch {}
            }
            
            Update-Progress -Percent -1 -Status "" -Detail "Executando Disk Cleanup (pode demorar alguns minutos)..."
            
            # Executa em job com timeout de 2 minutos
            $job = Start-Job -ScriptBlock {
                param($args)
                Start-Process -FilePath "cleanmgr.exe" -ArgumentList $args -NoNewWindow -Wait
            } -ArgumentList $cleanmgrArgs
            
            $script:RunningJobs.Add($job) | Out-Null
            
            $completed = Wait-Job -Job $job -Timeout 120
            
            if ($completed) {
                Update-Progress -Percent -1 -Status "" -Detail "Disk Cleanup concluído"
            } else {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Update-Progress -Percent -1 -Status "" -Detail "Disk Cleanup timeout - Processo finalizado" -IsWarning
            }
            
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $script:RunningJobs.Remove($job) | Out-Null
        }
    } catch {
        Update-Progress -Percent -1 -Status "" -Detail "Erro ao executar Disk Cleanup" -IsWarning
    }
    
    Update-Progress -Percent 93 -Status "" -Detail "Otimização de disco (desfragmentação) desabilitada para evitar travamentos"
}

function Invoke-FinalOptimizations {
    Update-Progress -Percent 95 -Status "Otimizações finais..." -Detail "Executando otimizações de sistema"
    
    if ($script:CancelRequested) { return }
    
    if ($script:Config.DryRun) {
        Update-Progress -Percent -1 -Status "" -Detail "[SIMULADO] Otimizações finais seriam aplicadas"
        return
    }
    
    try {
        # Limpa DNS Cache
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Update-Progress -Percent -1 -Status "" -Detail "✅ Cache DNS limpo"
        
        # Limpa ARP Cache (com timeout curto para não travar)
        try {
            $arpProcess = Start-Process -FilePath "arp" -ArgumentList "-d" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
            if ($arpProcess) {
                # Espera no máximo 3 segundos. Se não terminar, mata o processo e segue.
                if (-not $arpProcess.WaitForExit(3000)) {
                    $arpProcess.Kill() | Out-Null
                    Update-Progress -Percent -1 -Status "" -Detail "⚠️ Cache ARP limpo (após timeout)" -IsWarning
                } else {
                    Update-Progress -Percent -1 -Status "" -Detail "✅ Cache ARP limpo"
                }
            }
        } catch {
            Update-Progress -Percent -1 -Status "" -Detail "⚠️ Erro ao limpar cache ARP" -IsWarning
        }
        
        # Libera memória standby (executa em segundo plano para NÃO TRAVAR)
        if (Test-Path "$env:WINDIR\System32\rundll32.exe") {
            # IMPORTANTE: Removido o -Wait para não travar o script
            Start-Process -FilePath "rundll32.exe" -ArgumentList "advapi32.dll,ProcessIdleTasks" -NoNewWindow -WindowStyle Hidden -ErrorAction SilentlyContinue
            Update-Progress -Percent -1 -Status "" -Detail "✅ Otimização de memória iniciada em segundo plano"
        }
        
    } catch {
        Update-Progress -Percent -1 -Status "" -Detail "⚠️ Algumas otimizações falharam" -IsWarning
    }
}

# ==============================================================================
# RELATÓRIO FINAL
# ==============================================================================

function Show-FinalReport {
    $elapsed = (Get-Date) - $script:Stats.StartTime
    $elapsedStr = "{0:mm}m {0:ss}s" -f $elapsed
    
    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Relatório Técnico v3.0 - by EdyOne"
    $reportForm.Size = New-Object System.Drawing.Size(900, 700)
    $reportForm.StartPosition = "CenterScreen"
    $reportForm.FormBorderStyle = "FixedDialog"
    $reportForm.MaximizeBox = $false
    $reportForm.BackColor = [System.Drawing.Color]::White
    
    # Header
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Location = New-Object System.Drawing.Point(0, 0)
    $headerPanel.Size = New-Object System.Drawing.Size(900, 80)
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $reportForm.Controls.Add($headerPanel)
    
    # Título
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 10)
    $titleLabel.Size = New-Object System.Drawing.Size(860, 30)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Text = "RELATÓRIO TÉCNICO - LIMPEZA CONCLUÍDA"
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($titleLabel)
    
    # Créditos
    $creditsLabel = New-Object System.Windows.Forms.Label
    $creditsLabel.Location = New-Object System.Drawing.Point(20, 42)
    $creditsLabel.Size = New-Object System.Drawing.Size(860, 20)
    $creditsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $creditsLabel.Text = "Desenvolvido by EdyOne - Versão 3.0"
    $creditsLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $creditsLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($creditsLabel)
    
    # Modo DryRun
    if ($script:Config.DryRun) {
        $dryRunLabel = New-Object System.Windows.Forms.Label
        $dryRunLabel.Location = New-Object System.Drawing.Point(20, 60)
        $dryRunLabel.Size = New-Object System.Drawing.Size(860, 18)
        $dryRunLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $dryRunLabel.Text = "⚠️ RELATÓRIO DE SIMULAÇÃO - Nenhum arquivo foi realmente deletado"
        $dryRunLabel.ForeColor = [System.Drawing.Color]::Yellow
        $dryRunLabel.BackColor = [System.Drawing.Color]::Transparent
        $headerPanel.Controls.Add($dryRunLabel)
    }
    
    # Resumo
    $summaryBox = New-Object System.Windows.Forms.TextBox
    $summaryBox.Location = New-Object System.Drawing.Point(20, 95)
    $summaryBox.Size = New-Object System.Drawing.Size(860, 120)
    $summaryBox.Multiline = $true
    $summaryBox.ReadOnly = $true
    $summaryBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $summaryBox.BackColor = [System.Drawing.Color]::WhiteSmoke
    
    $modeLabel = if ($script:Config.DryRun) { " [MODO SIMULAÇÃO]" } else { "" }
    
    $summary = "╔════════════════════════════════════════════════════════════════════╗`r`n" +
               "║  RESUMO EXECUTIVO$modeLabel`r`n" +
               "╠════════════════════════════════════════════════════════════════════╝`r`n" +
               "║  🕒 Tempo de Execução: $elapsedStr`r`n" +
               "║  💾 Espaço Liberado: $(Format-FileSize $script:Stats.DeletedSize)`r`n" +
               "║  📁 Operações Realizadas: $($script:Stats.Operations.Count)`r`n" +
               "║  ✅ Bem-sucedidas: $($script:Stats.Operations.Count - $script:Stats.FailedOperations)`r`n" +
               "║  ⚠️ Falhas: $($script:Stats.FailedOperations)`r`n" +
               "║  ⏭️ Ignoradas: $($script:Stats.SkippedOperations)`r`n" +
               "╚════════════════════════════════════════════════════════════════════`r`n"
    
    $summaryBox.Text = $summary
    $reportForm.Controls.Add($summaryBox)
    
    # Avisos
    if ($script:Stats.Warnings.Count -gt 0) {
        $warningsLabel = New-Object System.Windows.Forms.Label
        $warningsLabel.Location = New-Object System.Drawing.Point(20, 225)
        $warningsLabel.Size = New-Object System.Drawing.Size(860, 25)
        $warningsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $warningsLabel.Text = "⚠️ Avisos e Observações ($($script:Stats.Warnings.Count)):"
        $warningsLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        $reportForm.Controls.Add($warningsLabel)
        
        $warningsBox = New-Object System.Windows.Forms.ListBox
        $warningsBox.Location = New-Object System.Drawing.Point(20, 255)
        $warningsBox.Size = New-Object System.Drawing.Size(860, 60)
        $warningsBox.Font = New-Object System.Drawing.Font("Consolas", 8)
        
        foreach ($warning in $script:Stats.Warnings) {
            $warningsBox.Items.Add("$($warning.Location): $($warning.Issue)") | Out-Null
        }
        
        $reportForm.Controls.Add($warningsBox)
        $detailsTop = 325
    } else {
        $detailsTop = 225
    }
    
    # Detalhes (COM A CORREÇÃO AQUI)
    $detailsLabel = New-Object System.Windows.Forms.Label
    $detailsLabel.Location = New-Object System.Drawing.Point(20, $detailsTop)
    $detailsLabel.Size = New-Object System.Drawing.Size(860, 25)
    $detailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $detailsLabel.Text = "Detalhamento por Local:"
    $reportForm.Controls.Add($detailsLabel)
    
    $gridTop = $detailsTop + 30
    $gridHeight = 560 - $gridTop
    
    $detailsGrid = New-Object System.Windows.Forms.DataGridView
    $detailsGrid.Location = New-Object System.Drawing.Point(20, $gridTop)
    $detailsGrid.Size = New-Object System.Drawing.Size(860, $gridHeight)
    $detailsGrid.ReadOnly = $true
    $detailsGrid.AllowUserToAddRows = $false
    $detailsGrid.RowHeadersVisible = $false
    $detailsGrid.AutoSizeColumnsMode = "Fill"
    $detailsGrid.SelectionMode = "FullRowSelect"
    $detailsGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::AliceBlue
    
    # Ordena os dados (se houver)
    if ($script:Stats.Operations.Count -gt 0) {
        $sortedOps = $script:Stats.Operations | Sort-Object {
            $sizeStr = $_.Deleted
            $sizeMB = 0
            if ($sizeStr -match '([\d.]+)\s*(GB|MB|KB)') {
                $value = [double]$matches[1]
                $unit = $matches[2]
                switch ($unit) {
                    'GB' { $sizeMB = $value * 1024 }
                    'MB' { $sizeMB = $value }
                    'KB' { $sizeMB = $value / 1024 }
                }
            }
            return $sizeMB
        } -Descending
    } else {
        $sortedOps = @() # Garante que a lista não seja nula
    }

    # Habilita a geração automática de colunas
    $detailsGrid.AutoGenerateColumns = $true

    # Define o DataSource. O DataGridView criará as colunas automaticamente.
    $detailsGrid.DataSource = [System.Collections.ArrayList]$sortedOps

    # Opcional: Renomeia os cabeçalhos das colunas para um português mais amigável
    if ($detailsGrid.Columns.Count -ge 4) {
        $detailsGrid.Columns["Location"].HeaderText = "Localização"
        $detailsGrid.Columns["Path"].HeaderText = "Caminho"
        $detailsGrid.Columns["Deleted"].HeaderText = "Espaço Liberado"
        $detailsGrid.Columns["Status"].HeaderText = "Status"
    }
    
    $reportForm.Controls.Add($detailsGrid)
    
    # Painel de botões
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(0, 610)
    $buttonPanel.Size = New-Object System.Drawing.Size(900, 60)
    $buttonPanel.BackColor = [System.Drawing.Color]::WhiteSmoke
    $reportForm.Controls.Add($buttonPanel)
    
    # Botão Exportar TXT
    $exportTxtButton = New-Object System.Windows.Forms.Button
    $exportTxtButton.Location = New-Object System.Drawing.Point(280, 12)
    $exportTxtButton.Size = New-Object System.Drawing.Size(120, 35)
    $exportTxtButton.Text = "Exportar TXT"
    $exportTxtButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $exportTxtButton.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Arquivo de Texto (*.txt)|*.txt"
        $saveDialog.FileName = "Relatorio_Limpeza_$(Get-Date -Format 'ddMMyyyy_HHmmss').txt"
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $report = $summaryBox.Text + "`r`n`r`n"
            
            if ($script:Stats.Warnings.Count -gt 0) {
                $report += "AVISOS:`r`n"
                foreach ($w in $script:Stats.Warnings) {
                    $report += "- $($w.Location): $($w.Issue)`r`n"
                }
                $report += "`r`n"
            }
            
            $report += "DETALHAMENTO:`r`n"
            foreach ($op in $sortedOps) {
                $report += "- $($op.Location) | $($op.Deleted) | $($op.Status)`r`n"
            }
            
            $report | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Relatório exportado com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    $buttonPanel.Controls.Add($exportTxtButton)
    
    # Botão Exportar CSV
    $exportCsvButton = New-Object System.Windows.Forms.Button
    $exportCsvButton.Location = New-Object System.Drawing.Point(410, 12)
    $exportCsvButton.Size = New-Object System.Drawing.Size(120, 35)
    $exportCsvButton.Text = "Exportar CSV"
    $exportCsvButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $exportCsvButton.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Arquivo CSV (*.csv)|*.csv"
        $saveDialog.FileName = "Relatorio_Limpeza_$(Get-Date -Format 'ddMMyyyy_HHmmss').csv"
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $sortedOps | Export-Csv -Path $saveDialog.FileName -NoTypeInformation -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Relatório CSV exportado com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    $buttonPanel.Controls.Add($exportCsvButton)
    
    # Botão Fechar
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(540, 12)
    $closeButton.Size = New-Object System.Drawing.Size(110, 35)
    $closeButton.Text = "Fechar"
    $closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $closeButton.Add_Click({ $reportForm.Close() })
    $buttonPanel.Controls.Add($closeButton)
    
    [void]$reportForm.ShowDialog()
}

# ==============================================================================
# EXECUÇÃO PRINCIPAL
# ==============================================================================

# Mostra janela de configuração inicial
$configForm = New-Object System.Windows.Forms.Form
$configForm.Text = "⚙️ Configuração - Limpeza Avançada"
$configForm.Size = New-Object System.Drawing.Size(500, 320)
$configForm.StartPosition = "CenterScreen"
$configForm.FormBorderStyle = "FixedDialog"
$configForm.MaximizeBox = $false
$configForm.BackColor = [System.Drawing.Color]::White

# Header
$configHeader = New-Object System.Windows.Forms.Panel
$configHeader.Location = New-Object System.Drawing.Point(0, 0)
$configHeader.Size = New-Object System.Drawing.Size(500, 60)
$configHeader.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$configForm.Controls.Add($configHeader)

$configTitle = New-Object System.Windows.Forms.Label
$configTitle.Location = New-Object System.Drawing.Point(15, 10)
$configTitle.Size = New-Object System.Drawing.Size(470, 25)
$configTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$configTitle.Text = "LIMPEZA AVANÇADA DO WINDOWS"
$configTitle.ForeColor = [System.Drawing.Color]::White
$configTitle.BackColor = [System.Drawing.Color]::Transparent
$configHeader.Controls.Add($configTitle)

$configCredits = New-Object System.Windows.Forms.Label
$configCredits.Location = New-Object System.Drawing.Point(15, 35)
$configCredits.Size = New-Object System.Drawing.Size(470, 20)
$configCredits.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$configCredits.Text = "by EdyOne | versão:3.0"
$configCredits.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$configCredits.BackColor = [System.Drawing.Color]::Transparent
$configHeader.Controls.Add($configCredits)

# Descrição
$descLabel = New-Object System.Windows.Forms.Label
$descLabel.Location = New-Object System.Drawing.Point(20, 75)
$descLabel.Size = New-Object System.Drawing.Size(460, 60)
$descLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$descLabel.Text = "Este script executará uma limpeza profunda do sistema.`r`n`r`n✅ Operando de forma segura`r`n✅ Haverá um tempo limite atingido`n✅ Verificação de arquivos bloqueados"
$configForm.Controls.Add($descLabel)

# Checkbox Modo Simulação
$dryRunCheckbox = New-Object System.Windows.Forms.CheckBox
$dryRunCheckbox.Location = New-Object System.Drawing.Point(20, 145)
$dryRunCheckbox.Size = New-Object System.Drawing.Size(460, 25)
$dryRunCheckbox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$dryRunCheckbox.Text = "(*) Modo Simulação - Apenas simula e não deleta nada"
$dryRunCheckbox.Checked = $false
$configForm.Controls.Add($dryRunCheckbox)

# Aviso
$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Location = New-Object System.Drawing.Point(20, 180)
$warningLabel.Size = New-Object System.Drawing.Size(460, 40)
$warningLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$warningLabel.ForeColor = [System.Drawing.Color]::Red
$warningLabel.Text = "(!) ATENÇÃO: Certifique-se de ter um backup antes de continuar.`r`nSerão fechados automaticamente alguns navegadores."
$configForm.Controls.Add($warningLabel)

# Botões
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Location = New-Object System.Drawing.Point(0, 230)
$btnPanel.Size = New-Object System.Drawing.Size(500, 60)
$btnPanel.BackColor = [System.Drawing.Color]::WhiteSmoke
$configForm.Controls.Add($btnPanel)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Location = New-Object System.Drawing.Point(150, 12)
$startButton.Size = New-Object System.Drawing.Size(100, 35)
$startButton.Text = "Iniciar"
$startButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$startButton.Add_Click({
    $script:Config.DryRun = $dryRunCheckbox.Checked
    $configForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $configForm.Close()
})
$btnPanel.Controls.Add($startButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(260, 12)
$cancelButton.Size = New-Object System.Drawing.Size(100, 35)
$cancelButton.Text = "Cancelar"
$cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cancelButton.Add_Click({
    $configForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $configForm.Close()
})
$btnPanel.Controls.Add($cancelButton)

$result = $configForm.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    [System.Windows.Forms.MessageBox]::Show(
        "Operação cancelada pelo usuário.",
        "Cancelado",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    # Restaura a janela do console antes de sair
    [Console.Window]::ShowWindow($consolePtr, 5) | Out-Null
    exit
}

# Mostra janela de progresso
Show-ProgressWindow

# Executa limpezas
try {
    Update-Progress -Percent 1 -Status "Iniciando processo de limpeza..." -Detail "Sistema preparado para limpeza"
    Start-Sleep -Milliseconds 500
    
    if (-not $script:CancelRequested) { Clean-TempFolders }
    if (-not $script:CancelRequested) { Clean-WindowsUpdate }
    if (-not $script:CancelRequested) { Clean-RecycleBin }
    if (-not $script:CancelRequested) { Clean-AllBrowsers }
    if (-not $script:CancelRequested) { Clean-WindowsLogs }
    if (-not $script:CancelRequested) { Clean-SystemCache }
    if (-not $script:CancelRequested) { Clean-ThumbnailCache }
    if (-not $script:CancelRequested) { Clean-MemoryDumps }
    if (-not $script:CancelRequested) { Optimize-Drives }
    if (-not $script:CancelRequested) { Invoke-FinalOptimizations }
    
    if ($script:CancelRequested) {
        Update-Progress -Percent 100 -Status "❌ Limpeza cancelada pelo usuário" -Detail "Processo interrompido manualmente"
        Start-Sleep -Seconds 2
    } else {
        Update-Progress -Percent 98 -Status "✅ Finalizando processo..." -Detail "Compilando estatísticas finais"
        Start-Sleep -Milliseconds 800
        
        Update-Progress -Percent 100 -Status "✅ Limpeza concluída com sucesso!" -Detail "Processo finalizado sem erros críticos"
        Start-Sleep -Seconds 1
    }
    
} catch {
    $script:Stats.FailedOperations++
    Update-Progress -Percent 100 -Status "❌ Erro crítico durante a limpeza" -Detail "Erro: $($_.Exception.Message)" -IsError
    Start-Sleep -Seconds 3
} finally {
    # Garante que todos os jobs sejam finalizados
    $script:RunningJobs | ForEach-Object {
        Stop-Job -Job $_ -ErrorAction SilentlyContinue
        Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
    }
    
    $script:Form.Close()
    
    # Mostra relatório final apenas se não foi cancelado
    if (-not $script:CancelRequested) {
        Show-FinalReport
    } else {
        # Mostra resumo do cancelamento
        $canceledOps = $script:Stats.Operations.Count
        $canceledSize = Format-FileSize $script:Stats.DeletedSize
        
        [System.Windows.Forms.MessageBox]::Show(
            "Limpeza cancelada pelo usuário.`n`n" +
            "Operações concluídas antes do cancelamento: $canceledOps`n" +
            "Espaço liberado: $canceledSize",
            "Processo Cancelado",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    
    # Restaura a janela do console antes de sair
    [Console.Window]::ShowWindow($consolePtr, 5) | Out-Null
}

# ==============================================================================
# FIM DO SCRIPT
# ==============================================================================

# Mensagem final no console (caso seja visível)
Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  LIMPEZA AVANÇADA DO WINDOWS v3.0 - FINALIZADO       ║" -ForegroundColor Cyan
Write-Host "║  Desenvolvido by EdyOne                               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Estatísticas Finais:" -ForegroundColor Yellow
Write-Host "   💾 Espaço Liberado: $(Format-FileSize $script:Stats.DeletedSize)" -ForegroundColor Green
Write-Host "   📁 Operações: $($script:Stats.Operations.Count)" -ForegroundColor White
Write-Host "   ⚠️  Falhas: $($script:Stats.FailedOperations)" -ForegroundColor $(if ($script:Stats.FailedOperations -gt 0) { "Red" } else { "Green" })
Write-Host "   ⏭️  Ignoradas: $($script:Stats.SkippedOperations)" -ForegroundColor Gray
Write-Host ""
Write-Host "✅ Script finalizado com sucesso!" -ForegroundColor Green
Write-Host ""
