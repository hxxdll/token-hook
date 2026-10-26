# Claude 답변이 끝나면(Stop 훅) 화면 가운데에 알림창을 띄운다.
# 훅이 바로 끝나도록, 알림창은 별도 프로세스(-Show)로 띄운다.
param([switch]$Show)

if (-not $IsWindows) { exit 0 }

if (-not $Show) {
    Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', "`"$PSCommandPath`"", '-Show'
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Claude Code 터미널 느낌: 어두운 배경, 고정폭 글꼴, 주황 포인트, 둥근 테두리
$bg     = [System.Drawing.Color]::FromArgb(30, 30, 30)
$fg     = [System.Drawing.Color]::FromArgb(220, 220, 220)
$accent = [System.Drawing.Color]::FromArgb(217, 119, 87)
$mono   = 'Cascadia Mono', 'Consolas' | Where-Object { (New-Object System.Drawing.Font($_, 10)).Name -eq $_ } | Select-Object -First 1

$form = New-Object System.Windows.Forms.Form -Property @{
    FormBorderStyle = 'None'
    StartPosition   = 'CenterScreen'
    TopMost         = $true
    ShowInTaskbar   = $false
    BackColor       = $bg
    Size            = New-Object System.Drawing.Size(360, 160)
    KeyPreview      = $true
}

# 둥근 모서리 경로 (창 모양과 테두리에 같이 사용)
function New-RoundPath([System.Drawing.Rectangle]$r, [int]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}
$form.Region = New-Object System.Drawing.Region (New-RoundPath (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)) 12)
$form.Add_Paint({
    $_.Graphics.SmoothingMode = 'AntiAlias'
    $pen = New-Object System.Drawing.Pen($accent, 1.5)
    $_.Graphics.DrawPath($pen, (New-RoundPath (New-Object System.Drawing.Rectangle(1, 1, ($form.Width - 3), ($form.Height - 3))) 11))
    $pen.Dispose()
})

$title = New-Object System.Windows.Forms.Label -Property @{
    Text      = [char]0x273B + ' Claude Code'
    ForeColor = $accent
    Font      = New-Object System.Drawing.Font($mono, 11, [System.Drawing.FontStyle]::Bold)
    Location  = New-Object System.Drawing.Point(20, 18)
    AutoSize  = $true
}

$msg = New-Object System.Windows.Forms.Label -Property @{
    Text      = '> 응답이 완료되었습니다.'
    ForeColor = $fg
    Font      = New-Object System.Drawing.Font($mono, 10)
    Location  = New-Object System.Drawing.Point(20, 60)
    AutoSize  = $true
}

$ok = New-Object System.Windows.Forms.Button -Property @{
    Text      = '확인'
    ForeColor = $accent
    BackColor = $bg
    FlatStyle = 'Flat'
    Font      = New-Object System.Drawing.Font($mono, 9)
    Size      = New-Object System.Drawing.Size(80, 30)
    Location  = New-Object System.Drawing.Point(258, 112)
    Cursor    = 'Hand'
}
$ok.FlatAppearance.BorderColor = $accent
$ok.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 40, 36)
$ok.Add_Click({ $form.Close() })

$form.Controls.AddRange(@($title, $msg, $ok))
$form.AcceptButton = $ok
$form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } })
$form.Add_Shown({ $form.Activate(); $ok.Focus() })

[void]$form.ShowDialog()
$form.Dispose()
