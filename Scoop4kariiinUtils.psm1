#Requires -Version 5.1

function New-ProfileModifier {
    <#
    .SYNOPSIS
        Generate scripts which modifies PowerShell profile.

    .PARAMETER Behavior
        Type of scripts to generate.

    .PARAMETER PSModuleName
        Name of PowerShell module, should be $manifest.psmodule.name in most situations.

    .PARAMETER AppDir
        Path of the app directory, should be $dir in most situations.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias("Type")]
        [string] $Behavior,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $PSModuleName,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $AppDir
    )

    Write-Host "Generating $Behavior script for $PSModuleName..." -NoNewline

    $SupportedBehavior = @("ImportModule", "RemoveModule")

    if ($SupportedBehavior -notcontains $Behavior) {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  Unsupported behavior type: $Behavior" -ForegroundColor DarkRed
        return
    }

    $ImportUtilsCommand = "Import-Module -Name Scoop4kariiinUtils -ErrorAction Stop"
    $RemoveUtilsCommand = "Remove-Module -Name Scoop4kariiinUtils -ErrorAction SilentlyContinue"

    $ImportModuleCommand = ("Add-ProfileContent 'Import-Module ", $PSModuleName, "'") -Join ("")
    $RemoveModuleCommand = ("Remove-ProfileContent 'Import-Module ", $PSModuleName, "'") -Join ("")

    $NewLine = [Environment]::NewLine

    switch ($Behavior) {
        "ImportModule" {
            $GenerateContent = ($ImportUtilsCommand, $RemoveModuleCommand, $ImportModuleCommand, $RemoveUtilsCommand) -Join ($NewLine)
            $OutputPath = "$AppDir\add-profile-content.ps1"
        }
        "RemoveModule" {
            $GenerateContent = ($ImportUtilsCommand, $RemoveModuleCommand, $RemoveUtilsCommand) -Join ($NewLine)
            $OutputPath = "$AppDir\remove-profile-content.ps1"
        }
    }

    try {
        $GenerateContent | Out-File -FilePath $OutputPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "success." -ForegroundColor Green
    } catch {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Add-ProfileContent {
    <#
    .SYNOPSIS
        Add certain content to PowerShell profile.

    .PARAMETER Content
        Content to be added.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias("Value")]
        [string] $Content
    )

    Write-Host "Modifying PowerShell profile..." -NoNewline

    if (Test-Path $PROFILE) {
        $NewLine = [Environment]::NewLine
        try {
            Add-Content -Path $PROFILE -Value "$NewLine$Content" -Encoding UTF8 -NoNewLine -ErrorAction Stop
            Write-Host "success." -ForegroundColor Green
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    } else {
        $ProfileParentDir = Split-Path -Path $PROFILE -Parent
        if (-not (Test-Path $ProfileParentDir)) {
            try {
                New-Item -Path $ProfileParentDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Host "failed." -ForegroundColor Red
                Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                return
            }
        }
        try {
            $Content | Out-File -FilePath $PROFILE -Encoding UTF8 -Force -ErrorAction Stop
            Write-Host "success." -ForegroundColor Green
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }
}

function Remove-ProfileContent {
    <#
    .SYNOPSIS
        Remove certain content from PowerShell profile.

    .PARAMETER Content
        Content to be removed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Content
    )

    Write-Host "Cleaning up PowerShell profile..." -NoNewline

    if (-not (Test-Path $PROFILE)) {
        Write-Host "abort." -ForegroundColor Yellow
        Write-Host "INFO  PowerShell profile not found." -ForegroundColor DarkGray
        return
    }

    try {
        $RawProfile = Get-Content -Path $PROFILE -Encoding UTF8 -Raw -ErrorAction Stop
    } catch {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        return
    }

    if ($null -eq $RawProfile) {
        Write-Host "abort." -ForegroundColor Yellow
        Write-Host "INFO  PowerShell profile is empty." -ForegroundColor DarkGray
        return
    }

    $escapedContent = [Regex]::Escape($Content)
    $ProfileLinePattern = "(?m)^[ \t]*$escapedContent[ \t]*(?:\r?\n|$)"

    if ($RawProfile -match $ProfileLinePattern) {
        $modifiedProfile = $RawProfile -replace $ProfileLinePattern, ''
        try {
            $modifiedProfile | Out-File -FilePath $PROFILE -Encoding UTF8 -NoNewLine -ErrorAction Stop
            Write-Host "success." -ForegroundColor Green
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    } else {
        Write-Host "abort." -ForegroundColor Yellow
        Write-Host "INFO  Content not found in PowerShell profile." -ForegroundColor DarkGray
    }
}

function Mount-ExternalRuntimeData {
    <#
    .SYNOPSIS
        Mount external runtime data.

    .PARAMETER Source
        Path of source folder in scoop persist directory.

    .PARAMETER Target
        The actual path which app uses to access the runtime data. Conflicts with parameter AppData and LocalAppData.

    .PARAMETER AppData
        Mount in $env:APPDATA by the name of source folder. Conflicts with parameter Target and LocalAppData.

    .PARAMETER LocalAppData
        Mount in $env:LOCALAPPDATA by the name of source folder. Conflicts with parameter Target and AppData.
    #>
    [CmdletBinding(DefaultParameterSetName = "Target")]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias("SourcePath", "Persist")]
        [string] $Source,
        [Parameter(Mandatory = $true, ParameterSetName = "Target", Position = 1)]
        [Alias("TargetPath", "Runtime")]
        [string] $Target,
        [Parameter(Mandatory = $true, ParameterSetName = "AppData")]
        [switch] $AppData,
        [Parameter(Mandatory = $true, ParameterSetName = "LocalAppData")]
        [switch] $LocalAppData
    )

    $FolderName = Split-Path -Path $Source -Leaf

    Write-Host "Mounting environment directory `'$FolderName`'..." -NoNewline

    if (-not ($Target -or $AppData -or $LocalAppData)) {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  Mount point not specified." -ForegroundColor DarkRed
        return
    }

    if ($AppData) { $RuntimeParent = $env:APPDATA }

    if ($LocalAppData) { $RuntimeParent = $env:LOCALAPPDATA }

    if ($RuntimeParent) { $Target = Join-Path -Path $RuntimeParent -ChildPath $FolderName }

    if (-not (Test-Path $Source)) {
        try {
            New-Item -Path $Source -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
            return
        }

        if (Test-Path $Target) {
            Write-Host "`nImporting exist runtime cache to persist directory..." -ForegroundColor Yellow -NoNewline
            try {
                Get-ChildItem $Target -ErrorAction Stop | Copy-Item -Destination $Source -Force -Recurse -ErrorAction Stop
                Write-Host "done." -ForegroundColor Green
                Write-Host "Continue mounting..." -NoNewline
            } catch {
                Write-Host "failed." -ForegroundColor Red
                Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                return
            }
        }
    }

    if (Test-Path $Target) {
        try {
            Remove-Item $Target -Force -Recurse -ErrorAction Stop
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
            return
        }
    }

    try {
        New-Item -Path $Target -ItemType Junction -Target $Source -Force -ErrorAction Stop | Out-Null
        Write-Host "success." -ForegroundColor Green
    } catch {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Dismount-ExternalRuntimeData {
    <#
    .SYNOPSIS
        Unmount external runtime data.

    .PARAMETER Target
        Path or name of runtime folder mounted by scoop.

    .PARAMETER AppData
        Dismount folder in $env:APPDATA with folder name in Target parameter. Parent path in $Target will be overwritten. Conflicts with parameter LocalAppData.

    .PARAMETER LocalAppData
        Dismount folder in $env:LOCALAPPDATA with folder name in Target parameter. Parent path in $Target will be overwritten. Conflicts with parameter AppData.
    #>
    [CmdletBinding(DefaultParameterSetName = "Target")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "Target", Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = "AppData", Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = "LocalAppData", Position = 0)]
        [Alias("TargetPath", "Path", "Name")]
        [string] $Target,
        [Parameter(Mandatory = $true, ParameterSetName = "AppData")]
        [switch] $AppData,
        [Parameter(Mandatory = $true, ParameterSetName = "LocalAppData")]
        [switch] $LocalAppData
    )

    $FolderName = Split-Path -Path $Target -Leaf

    Write-Host "Dismounting environment directory `'$FolderName`'..." -NoNewline

    if ($AppData) { $RuntimeParent = $env:APPDATA }

    if ($LocalAppData) { $RuntimeParent = $env:LOCALAPPDATA }

    if ($RuntimeParent) { $Target = Join-Path -Path $RuntimeParent -ChildPath $FolderName }

    if (Test-Path $Target) {
        try {
            Remove-Item $Target -Force -Recurse -ErrorAction Stop
            Write-Host "success." -ForegroundColor Green
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    } else {
        Write-Host "skip." -ForegroundColor Yellow
        Write-Host "INFO  Target item not found." -ForegroundColor DarkGray
    }
}

function Import-PersistItem {
    <#
    .SYNOPSIS
        Import files persisted by other app.

    .PARAMETER PersistDir
        Path of persist directory.

    .PARAMETER SourceApp
        Name of source app to import from.

    .PARAMETER ConflictAction
        Actions when item conflicts.

    .PARAMETER Select
        Specific items to import.

    .PARAMETER Sync
        Create junction instead of copying files.

    .PARAMETER Backup
        Rename original item instead of removing it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $PersistDir,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $SourceApp,
        [Parameter(Mandatory = $false)]
        [string] $ConflictAction = "Skip",
        [Parameter(Mandatory = $false)]
        [string[]] $Select,
        [Parameter(Mandatory = $false)]
        [switch] $Sync,
        [Parameter(Mandatory = $false)]
        [switch] $Backup
    )

    $ScoopPersistDir = Split-Path -Path $PersistDir -Parent
    $SourcePath = Join-Path -Path $ScoopPersistDir -ChildPath $SourceApp
    $TargetPath = $PersistDir

    if (-not (Test-Path $SourcePath)) { return }

    Write-Host "Importing profiles from `'$SourceApp`'..." -NoNewline

    $SupportedConfAct = @("ReplaceDir", "Overwrite", "Mix", "Skip")

    if ($SupportedConfAct -notcontains $ConflictAction) {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  Unsupported conflict action: $ConflictAction" -ForegroundColor DarkRed
        return
    }

    if (Test-Path $TargetPath) {
        switch ($ConflictAction) {
            "ReplaceDir" {
                if ($Backup) {
                    $LastBackupSuccess = Backup-SelectItem -Path $TargetPath
                    if (-not $LastBackupSuccess) { return }
                } else {
                    try {
                        Remove-Item -Path $TargetPath -Force -Recurse -ErrorAction Stop
                    } catch {
                        Write-Host "failed." -ForegroundColor Red
                        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                        return
                    }
                }
            }
            "Skip" {
                Write-Host "abort." -ForegroundColor Yellow
                Write-Host "INFO  Target item already exists." -ForegroundColor DarkGray
                return
            }
            default {
                if ($Sync) {
                    Write-Host "abort." -ForegroundColor Yellow
                    Write-Host "INFO  Target item already exists." -ForegroundColor DarkGray
                    Write-Host "WARN  Conflict action `'$ConflictAction`' won't work in sync mode." -ForegroundColor DarkYellow
                    return
                }
            }
        }
    }

    if ($Sync) {
        Write-Host "`nSync mode: " -NoNewline
        Mount-ExternalRuntimeData -Source $SourcePath -Target $TargetPath
        Write-Host "WARN  DO NOT uninstall `'$SourceApp`' when using sync mode." -ForegroundColor DarkYellow
        Write-Host "WARN  Or you will lose persisted data for this app." -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-Path $TargetPath)) {
        try {
            New-Item -Path $TargetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
            return
        }
    }

    if ($Select) {
        $SelectArray = $Select
    } else {
        try {
            $SelectArray = Get-ChildItem -Path $SourcePath -ErrorAction Stop | Select-Object -ExpandProperty Name
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
            return
        }
    }

    if (0 -eq $SelectArray.Count) {
        Write-Host "abort." -ForegroundColor Yellow
        Write-Host "INFO  Specified files not found or folder is empty." -ForegroundColor DarkGray
        return
    }

    $AllImportSuccess = $true

    $baseArgs = @{
        SourceLocation = $SourcePath
        TargetLocation = $TargetPath
    }
    if ($Backup) { $baseArgs.Backup = $true }
    if ('Overwrite' -eq $ConflictAction) { $baseArgs.Overwrite = $true }

    Write-Host ""

    foreach ($SelectItem in $SelectArray) {
        Write-Host "Importing item `'$SelectItem`'..." -NoNewline
        $importArgs = $baseArgs + @{ Name = $SelectItem }
        $LastImportSuccess = Import-SelectItem @importArgs
        if (-not $LastImportSuccess) { $AllImportSuccess = $false }
    }

    if ($AllImportSuccess) {
        Write-Host "INFO  You can uninstall `'$SourceApp`' now." -ForegroundColor DarkGray
    } else {
        Write-Host "WARN  Some items failed to import." -ForegroundColor DarkYellow
        Write-Host "WARN  Try manually copying failed items, then force update this app." -ForegroundColor DarkYellow
    }
}


function New-PersistItem {
    <#
    .SYNOPSIS
        Create items in persist directory.

    .PARAMETER PersistDir
        Path of persist directory.

    .PARAMETER Name
        Name of items to create.

    .PARAMETER Type
        Type of item to create.

    .PARAMETER Content
        Initial content of file, use with parameter "-Type File".

    .PARAMETER Force
        Force overwrite if item exists.

    .PARAMETER Backup
        Rename original item instead of removing it, use with parameter "-Force".
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $PersistDir,
        [Parameter(Mandatory = $true, Position = 1)]
        [string[]] $Name,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Type,
        [Parameter(Mandatory = $false)]
        [Alias("Value")]
        [string] $Content = $null,
        [Parameter(Mandatory = $false)]
        [switch] $Force,
        [Parameter(Mandatory = $false)]
        [switch] $Backup
    )

    Write-Host "Creating persist items..." -NoNewline

    $SupportedType = @("Directory", "File")

    if ($SupportedType -notcontains $Type) {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  Unsupported type: $Type" -ForegroundColor DarkRed
        return
    }

    $ItemArray = $Name

    Write-Host ""

    foreach ($Item in $ItemArray) {
        $PersistItemPath = Join-Path -Path $PersistDir -ChildPath $Item

        Write-Host "Creating `'$Item`'..." -NoNewline

        if (Test-Path $PersistItemPath) {
            if ($Force) {
                if ($Backup) {
                    $LastBackupSuccess = Backup-SelectItem -Path $PersistItemPath
                    if (-not $LastBackupSuccess) { continue }
                } else {
                    try {
                        Remove-Item -Path $PersistItemPath -Force -Recurse -ErrorAction Stop
                    } catch {
                        Write-Host "failed." -ForegroundColor Red
                        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                        continue
                    }
                }
            } else {
                Write-Host "skip." -ForegroundColor Yellow
                Write-Host "INFO  Item already exists." -ForegroundColor DarkGray
                continue
            }
        }

        switch ($Type) {
            "Directory" {
                try {
                    New-Item -Path $PersistItemPath -ItemType $Type -Force -ErrorAction Stop | Out-Null
                    Write-Host "done." -ForegroundColor Green
                } catch {
                    Write-Host "failed." -ForegroundColor Red
                    Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                }
            }
            "File" {
                try {
                    New-Item -Path $PersistItemPath -ItemType $Type -Value $Content -Force -ErrorAction Stop | Out-Null
                    Write-Host "done." -ForegroundColor Green
                } catch {
                    Write-Host "failed." -ForegroundColor Red
                    Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                }
            }
        }
    }
}

function Backup-PersistItem {
    <#
    .SYNOPSIS
        Backup items to persist directory.

    .PARAMETER AppDir
        Path of app directory.

    .PARAMETER PersistDir
        Path of persist directory.

    .PARAMETER Name
        Name of items to backup.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $AppDir,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $PersistDir,
        [Parameter(Mandatory = $true, Position = 2)]
        [string[]] $Name
    )

    Write-Host "Backing up items to persist directory..."

    $ItemArray = $Name

    $AllImportSuccess = $true

    foreach ($Item in $ItemArray) {
        Write-Host "Backing up `'$Item`'..." -NoNewline
        $LastImportSuccess = Import-SelectItem -SourceLocation $AppDir -TargetLocation $PersistDir -Name $Item -Overwrite
        if (-not $LastImportSuccess) { $AllImportSuccess = $false }
    }

    if (-not $AllImportSuccess) {
        Write-Host "WARN  Some items failed to backup." -ForegroundColor DarkYellow
    }
}

function Restore-PersistItem {
    <#
    .SYNOPSIS
        Restore items from persist directory.

    .PARAMETER AppDir
        Path of app directory.

    .PARAMETER PersistDir
        Path of persist directory.

    .PARAMETER Name
        Name of items to restore.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $AppDir,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $PersistDir,
        [Parameter(Mandatory = $true, Position = 2)]
        [string[]] $Name
    )

    Write-Host "Restoring items from persist directory..."

    $ItemArray = $Name

    $AllImportSuccess = $true

    foreach ($Item in $ItemArray) {
        Write-Host "Restoring `'$Item`'..." -NoNewline
        $LastImportSuccess = Import-SelectItem -SourceLocation $PersistDir -TargetLocation $AppDir -Name $Item -Overwrite -Backup
        if (-not $LastImportSuccess) { $AllImportSuccess = $false }
    }

    if (-not $AllImportSuccess) {
        Write-Host "WARN  Some items failed to restore." -ForegroundColor DarkYellow
    }
}

function Import-SelectItem {
    <#
    .SYNOPSIS
        Import item to specific location.

    .PARAMETER SourceLocation
        Location of source item.

    .PARAMETER TargetLocation
        Location of target.

    .PARAMETER Name
        Name of selected item.

    .PARAMETER Overwrite
        Overwrite target item when conflict.

    .PARAMETER Backup
        Backup file before overwriting.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $SourceLocation,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $TargetLocation,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Name,
        [Parameter(Mandatory = $false)]
        [switch] $Overwrite,
        [Parameter(Mandatory = $false)]
        [switch] $Backup
    )

    $SourceItem = Join-Path -Path $SourceLocation -ChildPath $Name
    $TargetItem = Join-Path -Path $TargetLocation -ChildPath $Name

    if (-not (Test-Path $SourceItem)) {
        Write-Host "skip." -ForegroundColor Yellow
        Write-Host "INFO  Source item not found." -ForegroundColor DarkGray
        return $true
    }

    if (Test-Path $TargetItem) {
        if ($Overwrite) {
            if ($Backup) {
                $LastBackupSuccess = Backup-SelectItem -Path $TargetItem
                if (-not $LastBackupSuccess) { return $false }
            } else {
                try {
                    Remove-Item $TargetItem -Force -Recurse -ErrorAction Stop
                } catch {
                    Write-Host "failed." -ForegroundColor Red
                    Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
                    return $false
                }
            }
        } else {
            Write-Host "skip." -ForegroundColor Yellow
            Write-Host "INFO  Target item already exists." -ForegroundColor DarkGray
            return $true
        }
    }

    try {
        Copy-Item -Path $SourceItem -Destination $TargetLocation -Force -Recurse -ErrorAction Stop
        Write-Host "done." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        return $false
    }
}

function Backup-SelectItem {
    <#
    .SYNOPSIS
        Backup specific item by renaming with suffix '.backup'.

    .PARAMETER Path
        Path of item to backup.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        Write-Host "skip." -ForegroundColor Yellow
        Write-Host "INFO  Item not found." -ForegroundColor DarkGray
        return $true
    }

    $ItemName = Split-Path -Path $Path -Leaf
    $ItemLocation = Split-Path -Path $Path -Parent
    $BackupItemName = ($ItemName, "backup") -Join (".")
    $BackupItemPath = Join-Path -Path $ItemLocation -ChildPath $BackupItemName

    if (Test-Path $BackupItemPath) {
        try {
            Remove-Item -Path $BackupItemPath -Force -Recurse -ErrorAction Stop
        } catch {
            Write-Host "failed." -ForegroundColor Red
            Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
            return $false
        }
    }

    try {
        Rename-Item -Path $Path -NewName $BackupItemName -Force -ErrorAction Stop
        Write-Host "done." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "ERROR  $($_.Exception.Message)" -ForegroundColor DarkRed
        return $false
    }
}
