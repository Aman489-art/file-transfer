# Windows Native File Transfer Script
# Compatible with Linux bash version - works natively on Windows
# No WSL or Git Bash required!

param(
    [switch]$Receive,
    [string]$Address,
    [string]$OutputDir
)

# Color functions
function Write-Success { param($msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "[✗] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "[ℹ] $msg" -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host "[⚠] $msg" -ForegroundColor Yellow }
function Write-Prompt { param($msg) Write-Host "[?] $msg" -ForegroundColor Blue -NoNewline }

# Configuration
$DEFAULT_PORT = 9999
$BUFFER_SIZE = 65536  # 64KB buffer

# Print header
function Show-Header {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     ULTRA-FAST WIRELESS FILE TRANSFER (Windows)            ║" -ForegroundColor Cyan
    Write-Host "║     Native PowerShell | Cross-platform Compatible          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Get local IP addresses
function Get-LocalIPs {
    $ips = @()
    $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*"
    }
    
    foreach ($adapter in $adapters) {
        $ips += $adapter.IPAddress
    }
    
    return $ips
}

# Check network connectivity
function Test-Network {
    $ips = Get-LocalIPs
    return ($ips.Count -gt 0)
}

# Format file size
function Format-FileSize {
    param([long]$bytes)
    
    if ($bytes -lt 1KB) { return "$bytes B" }
    elseif ($bytes -lt 1MB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    elseif ($bytes -lt 1GB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    else { return "{0:N2} GB" -f ($bytes / 1GB) }
}

# Check if port is available
function Test-PortAvailable {
    param([int]$port)
    
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $listener.Stop()
        return $true
    }
    catch {
        return $false
    }
}

# Get directory size
function Get-DirectorySize {
    param([string]$path)
    
    $size = (Get-ChildItem -Path $path -Recurse -File | Measure-Object -Property Length -Sum).Sum
    return $size
}

# Send file
function Send-File {
    param(
        [string]$FilePath,
        [int]$Port
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }
    
    $fileName = Split-Path $FilePath -Leaf
    $fileSize = (Get-Item $FilePath).Length
    $formattedSize = Format-FileSize $fileSize
    
    Write-Success "Preparing to send: $fileName ($formattedSize)"
    
    if (-not (Test-PortAvailable $Port)) {
        Write-Error "Port $Port is already in use"
        return
    }
    
    $ips = Get-LocalIPs
    Write-Host ""
    Write-Success "File ready to send!"
    Write-Info "File: $fileName"
    Write-Info "Size: $formattedSize"
    Write-Host ""
    Write-Success "Your IP addresses:"
    foreach ($ip in $ips) {
        Write-Host "  • $ip" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  Tell the receiver to run:                             ║" -ForegroundColor Yellow
    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    
    foreach ($ip in $ips) {
        # For Linux receiver
        Write-Host "║  Linux: ./file_transfer.sh --receive ${ip}:${Port}    ║" -ForegroundColor Yellow
        # For Windows receiver
        Write-Host "║  Windows: .\transfer.ps1 -Receive -Address ${ip}:${Port} ║" -ForegroundColor Yellow
    }
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Info "Waiting for connection..."
    Write-Host ""
    
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        
        Write-Info "Server listening on port $Port..."
        
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        
        Write-Success "Client connected! Starting transfer..."
        
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $BUFFER_SIZE
        $totalSent = 0
        $startTime = Get-Date
        
        while (($read = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $stream.Write($buffer, 0, $read)
            $totalSent += $read
            
            # Progress indicator
            $percent = [math]::Round(($totalSent / $fileSize) * 100, 1)
            $elapsed = (Get-Date) - $startTime
            $speed = if ($elapsed.TotalSeconds -gt 0) { 
                Format-FileSize ($totalSent / $elapsed.TotalSeconds) 
            } else { 
                "Calculating..." 
            }
            
            Write-Progress -Activity "Sending file" -Status "$percent% complete ($speed/s)" -PercentComplete $percent
        }
        
        $fileStream.Close()
        $stream.Close()
        $client.Close()
        $listener.Stop()
        
        Write-Progress -Activity "Sending file" -Completed
        Write-Host ""
        Write-Success "Transfer complete!"
        
        $totalTime = (Get-Date) - $startTime
        $avgSpeed = Format-FileSize ($fileSize / $totalTime.TotalSeconds)
        Write-Info "Time: $($totalTime.ToString('mm\:ss'))"
        Write-Info "Average speed: $avgSpeed/s"
    }
    catch {
        Write-Error "Transfer failed: $_"
    }
    finally {
        if ($listener) { $listener.Stop() }
    }
}

# Send directory
function Send-Directory {
    param(
        [string]$DirPath,
        [int]$Port
    )
    
    if (-not (Test-Path $DirPath -PathType Container)) {
        Write-Error "Directory not found: $DirPath"
        return
    }
    
    $dirName = Split-Path $DirPath -Leaf
    $dirSize = Get-DirectorySize $DirPath
    $formattedSize = Format-FileSize $dirSize
    
    Write-Info "Compressing directory: $dirName"
    
    $tempArchive = Join-Path $env:TEMP "transfer_$(Get-Random).zip"
    
    try {
        # Compress with fastest compression
        Compress-Archive -Path $DirPath -DestinationPath $tempArchive -CompressionLevel Fastest
        
        $archiveSize = (Get-Item $tempArchive).Length
        $formattedArchiveSize = Format-FileSize $archiveSize
        
        Write-Success "Compressed to: $formattedArchiveSize"
        
        # Send the archive
        Send-File -FilePath $tempArchive -Port $Port
    }
    catch {
        Write-Error "Compression failed: $_"
    }
    finally {
        if (Test-Path $tempArchive) {
            Remove-Item $tempArchive -Force
        }
    }
}

# Receive file
function Receive-File {
    param(
        [string]$Address,
        [string]$OutputDir = "."
    )
    
    if (-not ($Address -match '^(\d+\.){3}\d+:\d+$')) {
        Write-Error "Invalid address format. Use IP:PORT (e.g., 192.168.1.100:9999)"
        return
    }
    
    $parts = $Address -split ':'
    $ip = $parts[0]
    $port = [int]$parts[1]
    
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    $OutputDir = Resolve-Path $OutputDir
    
    Write-Info "Connecting to ${ip}:${port}..."
    
    $tempFile = Join-Path $OutputDir "received_$(Get-Random).tmp"
    
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($ip, $port)
        $stream = $client.GetStream()
        
        Write-Success "Connected! Receiving file..."
        Write-Host ""
        
        $fileStream = [System.IO.File]::OpenWrite($tempFile)
        $buffer = New-Object byte[] $BUFFER_SIZE
        $totalReceived = 0
        $startTime = Get-Date
        
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $totalReceived += $read
            
            # Progress indicator
            $elapsed = (Get-Date) - $startTime
            $speed = if ($elapsed.TotalSeconds -gt 0) { 
                Format-FileSize ($totalReceived / $elapsed.TotalSeconds) 
            } else { 
                "Calculating..." 
            }
            $received = Format-FileSize $totalReceived
            
            Write-Progress -Activity "Receiving file" -Status "$received received ($speed/s)" -PercentComplete -1
        }
        
        $fileStream.Close()
        $stream.Close()
        $client.Close()
        
        Write-Progress -Activity "Receiving file" -Completed
        Write-Host ""
        
        if ((Get-Item $tempFile).Length -eq 0) {
            Remove-Item $tempFile -Force
            Write-Error "No data received or connection failed"
            return
        }
        
        # Check if it's a ZIP archive
        $fileHeader = Get-Content $tempFile -Encoding Byte -TotalCount 4
        $isZip = ($fileHeader[0] -eq 0x50 -and $fileHeader[1] -eq 0x4B)
        
        if ($isZip) {
            Write-Info "Extracting compressed directory..."
            
            try {
                Expand-Archive -Path $tempFile -DestinationPath $OutputDir -Force
                Remove-Item $tempFile -Force
                Write-Success "Directory received and extracted to: $OutputDir"
            }
            catch {
                $finalPath = Join-Path $OutputDir "received_archive.zip"
                Move-Item $tempFile $finalPath -Force
                Write-Warning "Extraction failed. Saved as: $finalPath"
            }
        }
        else {
            # Determine file type and extension
            $extension = ""
            
            # Try to detect file type from magic bytes
            if ($fileHeader[0] -eq 0x25 -and $fileHeader[1] -eq 0x50 -and $fileHeader[2] -eq 0x44 -and $fileHeader[3] -eq 0x46) {
                $extension = ".pdf"
            }
            elseif ($fileHeader[0] -eq 0xFF -and $fileHeader[1] -eq 0xD8) {
                $extension = ".jpg"
            }
            elseif ($fileHeader[0] -eq 0x89 -and $fileHeader[1] -eq 0x50 -and $fileHeader[2] -eq 0x4E -and $fileHeader[3] -eq 0x47) {
                $extension = ".png"
            }
            elseif ($fileHeader[0] -eq 0x50 -and $fileHeader[1] -eq 0x4B) {
                $extension = ".zip"
            }
            
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $finalFileName = "received_file_${timestamp}${extension}"
            $finalPath = Join-Path $OutputDir $finalFileName
            
            Move-Item $tempFile $finalPath -Force
            
            $fileSize = Format-FileSize (Get-Item $finalPath).Length
            
            Write-Success "File received: $finalPath"
            Write-Info "Size: $fileSize"
        }
        
        $totalTime = (Get-Date) - $startTime
        $avgSpeed = Format-FileSize ($totalReceived / $totalTime.TotalSeconds)
        Write-Info "Time: $($totalTime.ToString('mm\:ss'))"
        Write-Info "Average speed: $avgSpeed/s"
    }
    catch {
        Write-Error "Transfer failed: $_"
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

# Network diagnostics
function Show-Diagnostics {
    Show-Header
    Write-Host "Network Diagnostics" -ForegroundColor White
    Write-Host ""
    
    Write-Success "Detecting your system..."
    Write-Info "Operating System: Windows $(([System.Environment]::OSVersion.Version).ToString())"
    Write-Info "PowerShell Version: $($PSVersionTable.PSVersion.ToString())"
    Write-Host ""
    
    Write-Success "Detecting IP addresses..."
    $ips = Get-LocalIPs
    
    if ($ips.Count -eq 0) {
        Write-Error "No network interfaces found!"
        Write-Host ""
        Write-Warning "Troubleshooting steps:"
        Write-Host "  1. Check if WiFi/Ethernet is connected"
        Write-Host "  2. Try: ipconfig in Command Prompt"
        Write-Host "  3. Ensure you're not in airplane mode"
    }
    else {
        Write-Info "Available IP addresses:"
        foreach ($ip in $ips) {
            Write-Host "  • $ip" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Success "Checking firewall status..."
    
    try {
        $firewallProfiles = Get-NetFirewallProfile
        foreach ($profile in $firewallProfiles) {
            $status = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
            Write-Info "$($profile.Name): $status"
        }
        
        Write-Host ""
        Write-Warning "If transfers fail, you may need to allow the port through firewall:"
        Write-Host "  netsh advfirewall firewall add rule name=`"File Transfer`" dir=in action=allow protocol=TCP localport=9999"
    }
    catch {
        Write-Info "Could not check firewall status"
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

# Interactive menu
function Show-Menu {
    while ($true) {
        Show-Header
        
        if (-not (Test-Network)) {
            Write-Error "No network connection detected!"
            Write-Host ""
            Write-Info "Please ensure:"
            Write-Host "  • WiFi or Ethernet is connected"
            Write-Host "  • Both devices are on the same network"
            Write-Host ""
            Read-Host "Press Enter to retry"
            continue
        }
        
        Write-Success "Network connection detected"
        Write-Host ""
        
        Write-Host "What do you want to do?" -ForegroundColor White
        Write-Host ""
        Write-Host "  1) 📤 Send files/folders (I'm the SENDER)"
        Write-Host "  2) 📥 Receive files/folders (I'm the RECEIVER)"
        Write-Host "  3) 🔧 Network diagnostics"
        Write-Host "  4) ❌ Exit"
        Write-Host ""
        
        Write-Prompt "Enter your choice [1-4]: "
        $choice = Read-Host
        
        switch ($choice) {
            "1" { Sender-Mode; break }
            "2" { Receiver-Mode; break }
            "3" { Show-Diagnostics }
            "4" { Write-Host ""; Write-Success "Goodbye!"; exit 0 }
            default { Write-Error "Invalid choice. Please select 1-4."; Start-Sleep -Seconds 2 }
        }
    }
}

# Sender mode
function Sender-Mode {
    Show-Header
    Write-Host "📤 SENDER MODE" -ForegroundColor White
    Write-Host ""
    
    Write-Host "What do you want to send?"
    Write-Host "  1) Single file"
    Write-Host "  2) Entire folder"
    Write-Host ""
    Write-Prompt "Enter choice [1-2]: "
    $sendType = Read-Host
    
    $sourcePath = ""
    $isDirectory = $false
    
    switch ($sendType) {
        "1" {
            Write-Host ""
            Write-Prompt "Enter file path (or drag & drop): "
            $sourcePath = Read-Host
            $sourcePath = $sourcePath.Trim('"')
            
            if (-not (Test-Path $sourcePath -PathType Leaf)) {
                Write-Error "File not found: $sourcePath"
                Start-Sleep -Seconds 2
                return
            }
        }
        "2" {
            Write-Host ""
            Write-Prompt "Enter folder path (or drag & drop): "
            $sourcePath = Read-Host
            $sourcePath = $sourcePath.Trim('"')
            
            if (-not (Test-Path $sourcePath -PathType Container)) {
                Write-Error "Folder not found: $sourcePath"
                Start-Sleep -Seconds 2
                return
            }
            $isDirectory = $true
        }
        default {
            Write-Error "Invalid choice"
            Start-Sleep -Seconds 2
            return
        }
    }
    
    Write-Host ""
    Write-Prompt "Port number (default 9999): "
    $portInput = Read-Host
    $port = if ($portInput) { [int]$portInput } else { $DEFAULT_PORT }
    
    Show-Header
    Write-Host "📤 Ready to Send" -ForegroundColor White
    Write-Host ""
    
    if ($isDirectory) {
        Send-Directory -DirPath $sourcePath -Port $port
    }
    else {
        Send-File -FilePath $sourcePath -Port $port
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

# Receiver mode
function Receiver-Mode {
    Show-Header
    Write-Host "📥 RECEIVER MODE" -ForegroundColor White
    Write-Host ""
    
    Write-Prompt "Enter sender's IP:PORT (e.g., 192.168.1.100:9999): "
    $address = Read-Host
    
    if (-not ($address -match '^(\d+\.){3}\d+:\d+$')) {
        Write-Error "Invalid format! Use IP:PORT (e.g., 192.168.1.100:9999)"
        Start-Sleep -Seconds 2
        return
    }
    
    Write-Host ""
    Write-Prompt "Save to folder (default: current directory): "
    $saveDir = Read-Host
    if (-not $saveDir) { $saveDir = "." }
    
    Show-Header
    Write-Host "📥 Connecting to Sender" -ForegroundColor White
    Write-Host ""
    
    Receive-File -Address $address -OutputDir $saveDir
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

# Main execution
if ($Receive -and $Address) {
    # Quick receive mode
    Show-Header
    Write-Host "📥 Quick Receive Mode" -ForegroundColor White
    Write-Host ""
    
    $output = if ($OutputDir) { $OutputDir } else { "." }
    Receive-File -Address $Address -OutputDir $output
    exit 0
}

# Interactive mode
Show-Menu