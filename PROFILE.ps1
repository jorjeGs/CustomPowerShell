# --- CONFIGURACIÓN DE PERSONALIZACIÓN Y DEPENDENCIAS (PLUG & PLAY) ---

function Initialize-TerminalPersonalization {
    # 1. Verificar oh-my-posh
    $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd) {
        Write-Host "La terminal no tiene personalizado el prompt con 'oh-my-posh'." -ForegroundColor Yellow
        if ([Environment]::UserInteractive) {
            $resp = Read-Host "¿Deseas instalar 'oh-my-posh' automáticamente usando winget? (s/n)"
            if ($resp -eq 's' -or $resp -eq 'S' -or $resp -eq 'y' -or $resp -eq 'Y') {
                Write-Host "Instalando oh-my-posh a través de winget..." -ForegroundColor Cyan
                # Intentar instalar usando winget
                winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] oh-my-posh instalado correctamente. Por favor, reinicia la terminal para aplicar los cambios." -ForegroundColor Green
                } else {
                    Write-Host "[ERROR] No se pudo instalar oh-my-posh de forma automática. Intenta instalarlo manualmente desde: https://ohmyposh.dev" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "[TIP] Para instalar oh-my-posh ejecuta: winget install JanDeDobbeleer.OhMyPosh" -ForegroundColor DarkYellow
        }
    } else {
        # Configuración de oh-my-posh y su tema
        $themeName = "craver.omp.json"
        $configDir = Join-Path -Path $HOME -ChildPath ".config\oh-my-posh"
        $configPath = Join-Path -Path $configDir -ChildPath $themeName
        
        $themeLoaded = $false
        
        # 1. Comprobar si existe en la carpeta local de configuración
        if (Test-Path -Path $configPath) {
            oh-my-posh init pwsh --config $configPath | Invoke-Expression
            $themeLoaded = $true
        }
        # 2. Comprobar en el PATH de temas oficial si existe la variable
        elseif ($env:POSH_THEMES_PATH -and (Test-Path -Path (Join-Path -Path $env:POSH_THEMES_PATH -ChildPath $themeName))) {
            $officialThemePath = Join-Path -Path $env:POSH_THEMES_PATH -ChildPath $themeName
            oh-my-posh init pwsh --config $officialThemePath | Invoke-Expression
            $themeLoaded = $true
        }
        # 3. Intentar descargarlo y guardarlo para uso futuro (offline)
        else {
            Write-Host "Descargando tema '$themeName' para oh-my-posh..." -ForegroundColor Cyan
            try {
                if (-not (Test-Path -Path $configDir)) {
                    $null = New-Item -ItemType Directory -Path $configDir -Force -ErrorAction SilentlyContinue
                }
                $themeUrl = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$themeName"
                Invoke-WebRequest -Uri $themeUrl -OutFile $configPath -TimeoutSec 10 -ErrorAction Stop
                oh-my-posh init pwsh --config $configPath | Invoke-Expression
                $themeLoaded = $true
                Write-Host "[OK] Tema descargado y configurado." -ForegroundColor Green
            } catch {
                Write-Host "[WARNING] No se pudo descargar el tema '$themeName' (sin conexión o error). Cargando tema por defecto." -ForegroundColor Yellow
                oh-my-posh init pwsh | Invoke-Expression
            }
        }
    }

    # 2. Verificar Terminal-Icons
    if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
        Write-Host "No se encontró el módulo 'Terminal-Icons' (necesario para mostrar iconos en directorios)." -ForegroundColor Yellow
        if ([Environment]::UserInteractive) {
            $resp = Read-Host "¿Deseas instalar 'Terminal-Icons' desde el repositorio PSGallery? (s/n)"
            if ($resp -eq 's' -or $resp -eq 'S' -or $resp -eq 'y' -or $resp -eq 'Y') {
                Write-Host "Instalando módulo Terminal-Icons para el usuario actual..." -ForegroundColor Cyan
                try {
                    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                    Install-Module -Name Terminal-Icons -Repository PSGallery -Force -Scope CurrentUser -ErrorAction Stop
                    Import-Module -Name Terminal-Icons -ErrorAction SilentlyContinue
                    Write-Host "[OK] Terminal-Icons instalado e importado correctamente." -ForegroundColor Green
                } catch {
                    Write-Host "[ERROR] Falló la instalación de Terminal-Icons: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "[TIP] Para instalar Terminal-Icons ejecuta: Install-Module -Name Terminal-Icons -Scope CurrentUser" -ForegroundColor DarkYellow
        }
    } else {
        Import-Module -Name Terminal-Icons -ErrorAction SilentlyContinue
    }

    # 3. Configurar PSReadLine
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Import-Module -Name PSReadLine -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
        Set-PSReadLineOption -EditMode Windows
    }
}

# Ejecutar inicialización de la terminal
Initialize-TerminalPersonalization

function GetDBSchema {
    <#
    .SYNOPSIS
    Obtiene el esquema de una base de datos o tabla específica de un servidor MySQL remoto.
    #>
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$DBName,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$Table = ""
    )

    # Limpiamos los prefijos "--"
    $DBName = $DBName -replace "^--", ""
    $Table  = $Table -replace "^--", ""

    # Verificación de variables de entorno
    $hostName = $env:MYSQL_REMOTE_HOST
    $user     = $env:MYSQL_REMOTE_USER
    $pass     = $env:MYSQL_REMOTE_PASS
    $port     = if ([string]::IsNullOrWhiteSpace($env:MYSQL_REMOTE_PORT)) { "3306" } else { $env:MYSQL_REMOTE_PORT }

    $missingVars = @()
    if ([string]::IsNullOrWhiteSpace($hostName)) { $missingVars += "MYSQL_REMOTE_HOST" }
    if ([string]::IsNullOrWhiteSpace($user))     { $missingVars += "MYSQL_REMOTE_USER" }
    if ([string]::IsNullOrWhiteSpace($pass))     { $missingVars += "MYSQL_REMOTE_PASS" }

    if ($missingVars.Count -gt 0) {
        Write-Host "[ERROR] Faltan variables de entorno necesarias para ejecutar GetDBSchema: $($missingVars -join ', ')." -ForegroundColor Red
        Write-Host "`nPara dar de alta estas variables de entorno en tu equipo de forma permanente:" -ForegroundColor Yellow
        Write-Host "Ejecuta los siguientes comandos en esta ventana de PowerShell (reemplazando con tus datos):" -ForegroundColor White
        foreach ($var in $missingVars) {
            $exampleVal = switch ($var) {
                "MYSQL_REMOTE_HOST" { "servidor.remoto.com o IP" }
                "MYSQL_REMOTE_USER" { "usuario_db" }
                "MYSQL_REMOTE_PASS" { "contraseña_db" }
            }
            Write-Host "  [System.Environment]::SetEnvironmentVariable('$var', '$exampleVal', 'User')" -ForegroundColor Cyan
        }
        Write-Host "`nUna vez ejecutados los comandos, reinicia tu terminal para aplicar los cambios." -ForegroundColor Yellow
        return
    }

    # Determinar el nombre del archivo de salida
    $fileName = "schema_$DBName.sql"
    if ($Table) {
        $fileName = "schema_${DBName}_${Table}.sql"
    }
    
    $outputPath = Join-Path -Path (Get-Location) -ChildPath $fileName

    # Argumentos optimizados para evitar errores de permisos y ahorrar tokens
    $mysqlArgs = @(
        "-h", $hostName,
        "-P", $port,
        "-u", $user,
        "-p$pass",
        "--no-data",
        "--compact",
        "--no-tablespaces",
        "--skip-lock-tables",
        $DBName
    )

    if ($Table) {
        $mysqlArgs += $Table
    }

    function Show-SpinnerStatus {
        param(
            [Parameter(Mandatory=$true)]
            [int]$Tick,
            [Parameter(Mandatory=$true)]
            [TimeSpan]$Elapsed,
            [string]$Status = "Procesando"
        )

        $frames = @('|', '/', '-', '\')
        $frame = $frames[$Tick % $frames.Count]
        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds

        Write-Host -NoNewline ("`r[{0}] {1}  ({2})" -f $frame, $Status, $elapsedText)
    }

    try {
        # Validar disponibilidad de mysqldump antes de ejecutar
        $mysqlDumpCmd = Get-Command -Name "mysqldump" -ErrorAction SilentlyContinue
        if (-not $mysqlDumpCmd) {
            Write-Host "[ERROR] No se encontró 'mysqldump' en el PATH." -ForegroundColor Red
            Write-Host "Para solucionar esto, puedes instalar MySQL CLI / Workbench, o instalarlo mediante winget/scoop:" -ForegroundColor Yellow
            Write-Host "  winget install Oracle.MySQL -s winget" -ForegroundColor Cyan
            Write-Host "O si usas scoop:" -ForegroundColor Yellow
            Write-Host "  scoop install mysql" -ForegroundColor Cyan
            Write-Host "Asegúrate de que la ruta al ejecutable 'mysqldump.exe' esté agregada al PATH del sistema." -ForegroundColor Yellow
            return
        }

        # 1. Mensaje y spinner en la siguiente línea con tiempo transcurrido
        Write-Host "GetDBSchema: Conectando al servidor y descargando esquema ($DBName)..."
        Show-SpinnerStatus -Tick 0 -Elapsed ([TimeSpan]::Zero) -Status "Descargando esquema"

        # 2. Ejecutar mysqldump en job para poder refrescar la barra de texto
        $tempErrPath = [System.IO.Path]::GetTempFileName()
        $job = Start-Job -ScriptBlock {
            param($argsList, $outPath, $errPath)
            & mysqldump @argsList 2> $errPath | Out-File -FilePath $outPath -Encoding UTF8
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
        } -ArgumentList (,$mysqlArgs), $outputPath, $tempErrPath

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tick = 1
        while ((Get-Job -Id $job.Id).State -eq "Running") {
            Show-SpinnerStatus -Tick $tick -Elapsed $stopwatch.Elapsed -Status "Descargando esquema"
            $tick++
            Start-Sleep -Milliseconds 120
        }

        $stopwatch.Stop()

        $result = Receive-Job -Id $job.Id -ErrorAction SilentlyContinue
        $exitCode = if ($result -and $result.ExitCode -ne $null) { [int]$result.ExitCode } else { 1 }
        Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue

        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$stopwatch.Elapsed.TotalHours, $stopwatch.Elapsed.Minutes, $stopwatch.Elapsed.Seconds
        Write-Host -NoNewline ("`r[OK] Descarga finalizada  ({0})" -f $elapsedText)
        Write-Host ""

        $stdErr = ""
        if (Test-Path $tempErrPath) {
            $stdErr = (Get-Content -Path $tempErrPath -Raw -ErrorAction SilentlyContinue).Trim()
        }

        if ($exitCode -eq 0) {
            Write-Host "[EXITO] Esquema guardado exitosamente para contexto de Copilot en:" -ForegroundColor Green
            Write-Host "-> $outputPath" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] Ocurrió un error al ejecutar mysqldump." -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stdErr)) {
                Write-Host "Detalle: $stdErr" -ForegroundColor DarkYellow
            } else {
                Write-Host "Verifica tus credenciales, conexión y permisos." -ForegroundColor DarkYellow
            }
            Remove-Item $outputPath -ErrorAction SilentlyContinue
        }

        Remove-Item $tempErrPath -ErrorAction SilentlyContinue
    } catch {
        Write-Host ""
        Write-Host "[ERROR] Falló GetDBSchema: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[TIP] Asegúrate de tener 'mysqldump' instalado y agregado al PATH de Windows." -ForegroundColor DarkYellow
    }
}

# Alias opcional para facilitar escritura
Set-Alias -Name Get-DBSchema -Value GetDBSchema

function GetDBLocalSchema {
    <#
    .SYNOPSIS
    Obtiene el esquema de una base de datos o tabla específica de tu servidor MySQL local.
    #>
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$DBName,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$Table = ""
    )

    # Limpiamos los prefijos "--"
    $DBName = $DBName -replace "^--", ""
    $Table  = $Table -replace "^--", ""

    # Verificación de variables de entorno locales
    # Si no defines HOST, por defecto asumirá 127.0.0.1
    $hostName = if ([string]::IsNullOrWhiteSpace($env:MYSQL_LOCAL_HOST)) { "127.0.0.1" } else { $env:MYSQL_LOCAL_HOST }
    $user     = $env:MYSQL_LOCAL_USER
    $pass     = $env:MYSQL_LOCAL_PASS
    $port     = if ([string]::IsNullOrWhiteSpace($env:MYSQL_LOCAL_PORT)) { "3306" } else { $env:MYSQL_LOCAL_PORT }

    $missingVars = @()
    if ([string]::IsNullOrWhiteSpace($user)) { $missingVars += "MYSQL_LOCAL_USER" }
    if ([string]::IsNullOrWhiteSpace($pass)) { $missingVars += "MYSQL_LOCAL_PASS" }

    if ($missingVars.Count -gt 0) {
        Write-Host "[ERROR] Faltan variables de entorno locales necesarias para ejecutar GetDBLocalSchema: $($missingVars -join ', ')." -ForegroundColor Red
        Write-Host "`nPara dar de alta estas variables de entorno en tu equipo de forma permanente:" -ForegroundColor Yellow
        Write-Host "Ejecuta los siguientes comandos en esta ventana de PowerShell (reemplazando con tus datos):" -ForegroundColor White
        foreach ($var in $missingVars) {
            $exampleVal = switch ($var) {
                "MYSQL_LOCAL_USER" { "root" }
                "MYSQL_LOCAL_PASS" { "tu_contraseña_local" }
            }
            Write-Host "  [System.Environment]::SetEnvironmentVariable('$var', '$exampleVal', 'User')" -ForegroundColor Cyan
        }
        Write-Host "`nUna vez ejecutados los comandos, reinicia tu terminal para aplicar los cambios." -ForegroundColor Yellow
        return
    }

    # Determinar el nombre del archivo de salida
    $fileName = "schema_local_$DBName.sql"
    if ($Table) {
        $fileName = "schema_local_${DBName}_${Table}.sql"
    }
    
    $outputPath = Join-Path -Path (Get-Location) -ChildPath $fileName

    # Argumentos optimizados para evitar errores de permisos y ahorrar tokens
    $mysqlArgs = @(
        "-h", $hostName,
        "-P", $port,
        "-u", $user,
        "-p$pass",
        "--no-data",
        "--compact",
        "--no-tablespaces",
        "--skip-lock-tables",
        $DBName
    )

    if ($Table) {
        $mysqlArgs += $Table
    }

    function Show-SpinnerStatus {
        param(
            [Parameter(Mandatory=$true)]
            [int]$Tick,
            [Parameter(Mandatory=$true)]
            [TimeSpan]$Elapsed,
            [string]$Status = "Procesando"
        )

        $frames = @('|', '/', '-', '\')
        $frame = $frames[$Tick % $frames.Count]
        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds

        Write-Host -NoNewline ("`r[{0}] {1}  ({2})" -f $frame, $Status, $elapsedText)
    }

    try {
        # Validar disponibilidad de mysqldump antes de ejecutar
        $mysqlDumpCmd = Get-Command -Name "mysqldump" -ErrorAction SilentlyContinue
        if (-not $mysqlDumpCmd) {
            Write-Host "[ERROR] No se encontró 'mysqldump' en el PATH." -ForegroundColor Red
            Write-Host "Para solucionar esto, puedes instalar MySQL CLI / Workbench, o instalarlo mediante winget/scoop:" -ForegroundColor Yellow
            Write-Host "  winget install Oracle.MySQL -s winget" -ForegroundColor Cyan
            Write-Host "O si usas scoop:" -ForegroundColor Yellow
            Write-Host "  scoop install mysql" -ForegroundColor Cyan
            Write-Host "Asegúrate de que la ruta al ejecutable 'mysqldump.exe' esté agregada al PATH del sistema." -ForegroundColor Yellow
            return
        }

        # 1. Mensaje y spinner en la siguiente línea con tiempo transcurrido
        Write-Host "GetDBLocalSchema: Conectando al entorno local y descargando esquema ($DBName)..."
        Show-SpinnerStatus -Tick 0 -Elapsed ([TimeSpan]::Zero) -Status "Descargando esquema"

        # 2. Ejecutar mysqldump en job para poder refrescar la barra de texto
        $tempErrPath = [System.IO.Path]::GetTempFileName()
        $job = Start-Job -ScriptBlock {
            param($argsList, $outPath, $errPath)
            & mysqldump @argsList 2> $errPath | Out-File -FilePath $outPath -Encoding UTF8
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
        } -ArgumentList (,$mysqlArgs), $outputPath, $tempErrPath

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tick = 1
        while ((Get-Job -Id $job.Id).State -eq "Running") {
            Show-SpinnerStatus -Tick $tick -Elapsed $stopwatch.Elapsed -Status "Descargando esquema"
            $tick++
            Start-Sleep -Milliseconds 120
        }

        $stopwatch.Stop()

        $result = Receive-Job -Id $job.Id -ErrorAction SilentlyContinue
        $exitCode = if ($result -and $result.ExitCode -ne $null) { [int]$result.ExitCode } else { 1 }
        Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue

        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$stopwatch.Elapsed.TotalHours, $stopwatch.Elapsed.Minutes, $stopwatch.Elapsed.Seconds
        Write-Host -NoNewline ("`r[OK] Descarga finalizada  ({0})" -f $elapsedText)
        Write-Host ""

        $stdErr = ""
        if (Test-Path $tempErrPath) {
            $stdErr = (Get-Content -Path $tempErrPath -Raw -ErrorAction SilentlyContinue).Trim()
        }

        if ($exitCode -eq 0) {
            Write-Host "[EXITO] Esquema LOCAL guardado exitosamente para contexto de Copilot en:" -ForegroundColor Green
            Write-Host "-> $outputPath" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] Ocurrió un error al ejecutar mysqldump en el entorno local." -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stdErr)) {
                Write-Host "Detalle: $stdErr" -ForegroundColor DarkYellow
            } else {
                Write-Host "Verifica que tu servidor local esté corriendo y tus credenciales sean correctas." -ForegroundColor DarkYellow
            }
            Remove-Item $outputPath -ErrorAction SilentlyContinue
        }

        Remove-Item $tempErrPath -ErrorAction SilentlyContinue
    } catch {
        Write-Host ""
        Write-Host "[ERROR] Falló GetDBLocalSchema: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[TIP] Asegúrate de tener 'mysqldump' instalado y agregado al PATH de Windows." -ForegroundColor DarkYellow
    }
}

# Alias opcional para facilitar escritura
Set-Alias -Name Get-DBLocalSchema -Value GetDBLocalSchema

function GetLocalDB {
    <#
    .SYNOPSIS
    Obtiene la base de datos completa (esquema, índices y DATOS) de tu servidor MySQL local, optimizada para LLMs.
    #>
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$DBName,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$Table = ""
    )

    # Limpiamos los prefijos "--"
    $DBName = $DBName -replace "^--", ""
    $Table  = $Table -replace "^--", ""

    # Verificación de variables de entorno locales
    $hostName = if ([string]::IsNullOrWhiteSpace($env:MYSQL_LOCAL_HOST)) { "127.0.0.1" } else { $env:MYSQL_LOCAL_HOST }
    $user     = $env:MYSQL_LOCAL_USER
    $pass     = $env:MYSQL_LOCAL_PASS
    $port     = if ([string]::IsNullOrWhiteSpace($env:MYSQL_LOCAL_PORT)) { "3306" } else { $env:MYSQL_LOCAL_PORT }

    $missingVars = @()
    if ([string]::IsNullOrWhiteSpace($user)) { $missingVars += "MYSQL_LOCAL_USER" }
    if ([string]::IsNullOrWhiteSpace($pass)) { $missingVars += "MYSQL_LOCAL_PASS" }

    if ($missingVars.Count -gt 0) {
        Write-Host "[ERROR] Faltan variables de entorno locales necesarias para ejecutar GetLocalDB: $($missingVars -join ', ')." -ForegroundColor Red
        Write-Host "`nPara dar de alta estas variables de entorno en tu equipo de forma permanente:" -ForegroundColor Yellow
        Write-Host "Ejecuta los siguientes comandos en esta ventana de PowerShell (reemplazando con tus datos):" -ForegroundColor White
        foreach ($var in $missingVars) {
            $exampleVal = switch ($var) {
                "MYSQL_LOCAL_USER" { "root" }
                "MYSQL_LOCAL_PASS" { "tu_contraseña_local" }
            }
            Write-Host "  [System.Environment]::SetEnvironmentVariable('$var', '$exampleVal', 'User')" -ForegroundColor Cyan
        }
        Write-Host "`nUna vez ejecutados los comandos, reinicia tu terminal para aplicar los cambios." -ForegroundColor Yellow
        return
    }

    # Determinar el nombre del archivo de salida (usamos prefijo 'dump_' para diferenciar de 'schema_')
    $fileName = "dump_local_$DBName.sql"
    if ($Table) {
        $fileName = "dump_local_${DBName}_${Table}.sql"
    }
    
    $outputPath = Join-Path -Path (Get-Location) -ChildPath $fileName

    # Argumentos: Igual que el anterior, pero SIN --no-data
    $mysqlArgs = @(
        "-h", $hostName,
        "-P", $port,
        "-u", $user,
        "-p$pass",
        "--compact",          # <- CLAVE PARA AHORRAR TOKENS: Quita comentarios y boilerplate
        "--no-tablespaces",
        "--skip-lock-tables",
        $DBName
    )

    if ($Table) {
        $mysqlArgs += $Table
    }

    function Show-SpinnerStatus {
        param(
            [Parameter(Mandatory=$true)]
            [int]$Tick,
            [Parameter(Mandatory=$true)]
            [TimeSpan]$Elapsed,
            [string]$Status = "Procesando"
        )

        $frames = @('|', '/', '-', '\')
        $frame = $frames[$Tick % $frames.Count]
        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds

        Write-Host -NoNewline ("`r[{0}] {1}  ({2})" -f $frame, $Status, $elapsedText)
    }

    try {
        $mysqlDumpCmd = Get-Command -Name "mysqldump" -ErrorAction SilentlyContinue
        if (-not $mysqlDumpCmd) {
            Write-Host "[ERROR] No se encontró 'mysqldump' en el PATH." -ForegroundColor Red
            Write-Host "Para solucionar esto, puedes instalar MySQL CLI / Workbench, o instalarlo mediante winget/scoop:" -ForegroundColor Yellow
            Write-Host "  winget install Oracle.MySQL -s winget" -ForegroundColor Cyan
            Write-Host "O si usas scoop:" -ForegroundColor Yellow
            Write-Host "  scoop install mysql" -ForegroundColor Cyan
            Write-Host "Asegúrate de que la ruta al ejecutable 'mysqldump.exe' esté agregada al PATH del sistema." -ForegroundColor Yellow
            return
        }

        Write-Host "GetLocalDB: Conectando al entorno local y descargando DB completa ($DBName)..."
        Show-SpinnerStatus -Tick 0 -Elapsed ([TimeSpan]::Zero) -Status "Descargando esquema y datos"

        $tempErrPath = [System.IO.Path]::GetTempFileName()
        $job = Start-Job -ScriptBlock {
            param($argsList, $outPath, $errPath)
            & mysqldump @argsList 2> $errPath | Out-File -FilePath $outPath -Encoding UTF8
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
        } -ArgumentList (,$mysqlArgs), $outputPath, $tempErrPath

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tick = 1
        while ((Get-Job -Id $job.Id).State -eq "Running") {
            Show-SpinnerStatus -Tick $tick -Elapsed $stopwatch.Elapsed -Status "Descargando esquema y datos"
            $tick++
            Start-Sleep -Milliseconds 120
        }

        $stopwatch.Stop()

        $result = Receive-Job -Id $job.Id -ErrorAction SilentlyContinue
        $exitCode = if ($result -and $result.ExitCode -ne $null) { [int]$result.ExitCode } else { 1 }
        Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue

        $elapsedText = "{0:00}:{1:00}:{2:00}" -f [int]$stopwatch.Elapsed.TotalHours, $stopwatch.Elapsed.Minutes, $stopwatch.Elapsed.Seconds
        Write-Host -NoNewline ("`r[OK] Descarga finalizada  ({0})" -f $elapsedText)
        Write-Host ""

        $stdErr = ""
        if (Test-Path $tempErrPath) {
            $stdErr = (Get-Content -Path $tempErrPath -Raw -ErrorAction SilentlyContinue).Trim()
        }

        if ($exitCode -eq 0) {
            Write-Host "[EXITO] DB completa (LOCAL) guardada exitosamente para contexto de Copilot en:" -ForegroundColor Green
            Write-Host "-> $outputPath" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] Ocurrió un error al ejecutar mysqldump en el entorno local." -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stdErr)) {
                Write-Host "Detalle: $stdErr" -ForegroundColor DarkYellow
            } else {
                Write-Host "Verifica que tu servidor local esté corriendo y tus credenciales sean correctas." -ForegroundColor DarkYellow
            }
            Remove-Item $outputPath -ErrorAction SilentlyContinue
        }

        Remove-Item $tempErrPath -ErrorAction SilentlyContinue
    } catch {
        Write-Host ""
        Write-Host "[ERROR] Falló GetLocalDB: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[TIP] Asegúrate de tener 'mysqldump' instalado y agregado al PATH." -ForegroundColor DarkYellow
    }
}

# Alias opcional para facilitar escritura
Set-Alias -Name Get-LocalDB -Value GetLocalDB

function SetGitUser {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ux", "yorch")]
        $Account
    )

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Host "[ERROR] No se encontró 'git' en el PATH." -ForegroundColor Red
        Write-Host "Para solucionar esto, puedes instalar git ejecutando:" -ForegroundColor Yellow
        Write-Host "  winget install Git.Git -s winget" -ForegroundColor Cyan
        return
    }

    if ($Account -eq "ux") {
        git config user.name "JorgeGarciaSerrano"
        git config user.email "jorgeserrano@xochicalco.edu.mx"
        Write-Host "Cambiado a perfil: UX" -ForegroundColor Cyan
    } else {
        git config user.name "jorjeGs"
        git config user.email "jgs_23072000@outlook.com"
        Write-Host "Cambiado a perfil: Yorch" -ForegroundColor Green
    }
}

# Alias opcional para facilitar escritura
Set-Alias -Name Set-GitUser -Value SetGitUser

function GitInit {
    <#
    .SYNOPSIS
    Inicializa un repositorio Git local y lo conecta al remote correcto segun el usuario SSH.
    #>
    param(
        [ValidateSet("ux", "yorch")]
        [string]$User,

        [string]$NameRepo,

        [switch]$Help
    )

    if ($Help -or ([string]::IsNullOrWhiteSpace($User) -and [string]::IsNullOrWhiteSpace($NameRepo))) {
        Write-Host @"

GitInit - Inicializa un repo Git con SSH correcto

USO:
    GitInit -User <ux|yorch> -NameRepo <nombre>

PARAMETROS:
    -User       Alias SSH a usar: 'ux' (JorgeGarciaSerrano) o 'yorch' (jorjeGs)
    -NameRepo   Nombre del repositorio a crear/configurar
    -Help       Muestra esta ayuda

EJEMPLOS:
    GitInit -User yorch -NameRepo miproyecto
    GitInit -User ux -NameRepo otroproyecto --help

"@ -ForegroundColor Cyan
        return
    }

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Host "[ERROR] No se encontró 'git' en el PATH." -ForegroundColor Red
        Write-Host "Para solucionar esto, puedes instalar git ejecutando:" -ForegroundColor Yellow
        Write-Host "  winget install Git.Git -s winget" -ForegroundColor Cyan
        return
    }

    $currentDir = Get-Location

    if (-not (Test-Path -Path "$currentDir\.git")) {
        git init
        Write-Host "[OK] Repositorio inicializado en: $currentDir" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Repositorio ya estaba inicializado" -ForegroundColor Yellow
    }

    switch ($User) {
        "ux" {
            git remote add origin "git@ux:JorgeGarciaSerrano/$NameRepo.git" 2>$null
            if ($LASTEXITCODE -ne 0) { git remote set-url origin "git@ux:JorgeGarciaSerrano/$NameRepo.git" }
            git config user.name "JorgeGarciaSerrano"
            git config user.email "jorgeserrano@xochicalco.edu.mx"
            $remoteUrl = "git@ux:JorgeGarciaSerrano/$NameRepo.git"
        }
        "yorch" {
            git remote add origin "git@yorch:jorjeGs/$NameRepo.git" 2>$null
            if ($LASTEXITCODE -ne 0) { git remote set-url origin "git@yorch:jorjeGs/$NameRepo.git" }
            git config user.name "jorjeGs"
            git config user.email "jgs_23072000@outlook.com"
            $remoteUrl = "git@yorch:jorjeGs/$NameRepo.git"
        }
    }

    Write-Host ""
    Write-Host "[EXITO] Remote configurado:" -ForegroundColor Green
    Write-Host "  -> $remoteUrl" -ForegroundColor Cyan
    Write-Host "  User: $($User.ToUpper())" -ForegroundColor White

    # Verificar configuración SSH para el host
    $sshConfigPath = Join-Path -Path $HOME -ChildPath ".ssh\config"
    $sshHostDefined = $false
    if (Test-Path -Path $sshConfigPath) {
        try {
            $sshConfigContent = Get-Content -Path $sshConfigPath -Raw -ErrorAction SilentlyContinue
            if ($sshConfigContent -match "(?mi)^Host\s+$User\b") {
                $sshHostDefined = $true
            }
        } catch {}
    }
    
    if (-not $sshHostDefined) {
        Write-Host ""
        Write-Host "[WARNING] No se encontró la configuración SSH para el host '$User' en '$sshConfigPath'." -ForegroundColor Yellow
        Write-Host "Para poder conectarte y autenticarte con Git usando SSH, debes agregar este host a tu configuración de SSH." -ForegroundColor White
        Write-Host "Ejemplo de configuración a agregar en '$sshConfigPath':" -ForegroundColor Yellow
        Write-Host @"
Host $User
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa_$User
"@ -ForegroundColor Cyan
        Write-Host "`nAsegúrate de crear dicho archivo config y colocar tu clave SSH correspondiente en '~/.ssh/id_rsa_$User'." -ForegroundColor Yellow
    }
}

Set-Alias -Name Set-GitInit -Value GitInit