# Cargar oh-my-posh con tema
oh-my-posh init pwsh --config "C:\Users\anitj\scoop\apps\oh-my-posh\17.12.0\themes\craver.omp.json" | Invoke-Expression
# Cargar íconos
Import-Module -Name Terminal-Icons

# Configurar PSReadLine
Import-Module -Name PSReadLine

Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

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

    if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
        Write-Host "[ERROR] Faltan variables de entorno. Configura MYSQL_REMOTE_HOST, MYSQL_REMOTE_USER y MYSQL_REMOTE_PASS." -ForegroundColor Red
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

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
        Write-Host "[ERROR] Faltan variables de entorno locales. Configura MYSQL_LOCAL_USER y MYSQL_LOCAL_PASS." -ForegroundColor Red
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

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
        Write-Host "[ERROR] Faltan variables de entorno locales. Configura MYSQL_LOCAL_USER y MYSQL_LOCAL_PASS." -ForegroundColor Red
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
}

Set-Alias -Name Set-GitInit -Value GitInit