param(
  [Parameter(Mandatory=$true)][string]$Action,
  [string]$Out,
  [int]$X = 0,
  [int]$Y = 0,
  [int]$X2 = 0,
  [int]$Y2 = 0,
  [int]$Dx = 0,
  [int]$Dy = 0,
  [string]$Text = "",
  [string]$Keys = "",
  [string]$Path = "",
  [string]$Args = "",
  [string]$Title = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Convert-ToJsonLine($obj) {
  $obj | ConvertTo-Json -Compress -Depth 6
}

switch ($Action.ToLowerInvariant()) {
  "screenshot" {
    if (-not $Out) {
      $dir = Join-Path $env:TEMP "openclaw"
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
      $Out = Join-Path $dir ("screenshot-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".png")
    }
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose()
    $bmp.Dispose()
    Convert-ToJsonLine @{ ok=$true; action="screenshot"; path=$Out; width=$bounds.Width; height=$bounds.Height }
  }
  "windows" {
    $rows = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
      Select-Object Id, ProcessName, MainWindowTitle, MainWindowHandle
    Convert-ToJsonLine @{ ok=$true; action="windows"; windows=$rows }
  }
  "focus" {
    $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$Title*" } | Select-Object -First 1
    if (-not $p) { throw "No window matched title: $Title" }
    [Win32]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
    [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Convert-ToJsonLine @{ ok=$true; action="focus"; pid=$p.Id; title=$p.MainWindowTitle }
  }
  "click" {
    [Win32]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 80
    [Win32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Win32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Convert-ToJsonLine @{ ok=$true; action="click"; x=$X; y=$Y }
  }
  "scroll" {
    if ($X -ne 0 -or $Y -ne 0) {
      [Win32]::SetCursorPos($X, $Y) | Out-Null
      Start-Sleep -Milliseconds 80
    }
    if ($Dy -ne 0) {
      [Win32]::mouse_event(0x0800, 0, 0, [uint32]$Dy, [UIntPtr]::Zero)
    }
    if ($Dx -ne 0) {
      [Win32]::mouse_event(0x1000, 0, 0, [uint32]$Dx, [UIntPtr]::Zero)
    }
    Convert-ToJsonLine @{ ok=$true; action="scroll"; x=$X; y=$Y; dx=$Dx; dy=$Dy }
  }
  "drag" {
    [Win32]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 80
    [Win32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [Win32]::SetCursorPos($X2, $Y2) | Out-Null
    Start-Sleep -Milliseconds 120
    [Win32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Convert-ToJsonLine @{ ok=$true; action="drag"; x1=$X; y1=$Y; x2=$X2; y2=$Y2 }
  }
  "type" {
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Convert-ToJsonLine @{ ok=$true; action="type"; length=$Text.Length }
  }
  "hotkey" {
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Convert-ToJsonLine @{ ok=$true; action="hotkey"; keys=$Keys }
  }
  "start" {
    if (-not $Path) { throw "Missing -Path for start action" }
    if ($Args) { Start-Process -FilePath $Path -ArgumentList $Args }
    else { Start-Process -FilePath $Path }
    Convert-ToJsonLine @{ ok=$true; action="start"; path=$Path; args=$Args }
  }
  default {
    throw "Unknown action: $Action"
  }
}
