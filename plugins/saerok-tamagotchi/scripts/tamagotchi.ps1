# Claude 다마고치: Claude가 쓴 출력 토큰만큼 경험치를 얻고(1,000토큰 = 1 EXP), 오래 안 쓰면 배고파한다.
# 캐릭터 '새록이': 씨앗 → 새싹 → 꽃봉오리 → 꽃요정 순서로 자란다. (도형으로 직접 그림)
#   -Feed   : Stop 훅. 새 출력 토큰만큼 경험치 추가, 밥 먹은 시각 기록, 위젯이 없으면 띄움
#   -Ensure : SessionStart 훅. 위젯이 없으면 띄움
#   -Widget : 화면 오른쪽 아래에 항상 떠 있는 위젯 (훅이 알아서 실행)
#   -DataDir: 키우는 기록을 저장할 폴더 (플러그인 데이터 폴더. 비어 있으면 ~/.claude/saerok-tamagotchi)
param([switch]$Feed, [switch]$Ensure, [switch]$Widget, [string]$DataDir)

if (-not $IsWindows) { exit 0 }

if (-not $DataDir) { $DataDir = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA } else { Join-Path $HOME '.claude/saerok-tamagotchi' } }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$statePath = Join-Path $DataDir 'tamagotchi.json'
$mutexName = 'SaerokTamagotchiWidget'

function Read-State {
    try { Get-Content $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable }
    catch { $null }
}

function Start-Widget {
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting($mutexName, [ref]$m)) { $m.Dispose(); return }
    Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', "`"$PSCommandPath`"", '-Widget', '-DataDir', "`"$DataDir`""
}

if ($Feed) {
    $hook = try { [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { $null }
    $s = Read-State
    if (-not $s) { $s = @{ exp = 0.0; born = Get-Date } }
    if (-not $s.sessions) { $s.sessions = @{} }

    # 대화 기록에서 지난번 이후 새로 생긴 답변의 출력 토큰을 더한다.
    # 한 답변이 여러 줄에 나뉘어 기록되므로 답변 id별 최댓값만 센다.
    $gain = 0
    $path = $hook.transcript_path
    if ($path -and (Test-Path $path)) {
        $lines = @(Get-Content $path)
        $done = [int]$s.sessions[$hook.session_id]
        $tokens = @{}
        $lines | Select-Object -Skip $done | ForEach-Object {
            $l = try { $_ | ConvertFrom-Json } catch { $null }
            if ($l.type -eq 'assistant' -and $l.message.usage) {
                $id = $l.message.id
                $tokens[$id] = [math]::Max([int]$tokens[$id], [int]$l.message.usage.output_tokens)
            }
        }
        $gain = ($tokens.Values | Measure-Object -Sum).Sum / 1000
        $s.sessions[$hook.session_id] = $lines.Count
    }
    $s.exp = [double]$s.exp + $gain
    $s.lastGain = $gain
    $s.lastFed = Get-Date
    $s | ConvertTo-Json | Set-Content $statePath -Encoding utf8
    Start-Widget
    exit 0
}
if ($Ensure) { Start-Widget; exit 0 }
if (-not $Widget) { exit 0 }

# ---- 위젯 (하나만 실행) ----
$created = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function C($r, $g, $b, $a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function B($c) { New-Object System.Drawing.SolidBrush($c) }
function P($c, $w = 2) { $p = New-Object System.Drawing.Pen($c, $w); $p.LineJoin = 'Round'; $p }
function Pt($x, $y) { [System.Drawing.PointF]::new($x, $y) }

$cream  = C 255 248 236
$pink   = C 255 182 193
$pinkDk = C 255 128 156
$brown  = C 110 80 70
$white  = C 255 255 255

$fTitle  = New-Object System.Drawing.Font('Malgun Gothic', 11, [System.Drawing.FontStyle]::Bold)
$fBadge  = New-Object System.Drawing.Font('Malgun Gothic', 8, [System.Drawing.FontStyle]::Bold)
$fExp    = New-Object System.Drawing.Font('Malgun Gothic', 7.5)
$fBubble = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$fClose  = New-Object System.Drawing.Font('Malgun Gothic', 10)

# 단계: 필요한 경험치, 이름, 밥 먹을 때 문구, 진화했을 때 문구
$stages = @(
    @{ Min = 0;   Name = '씨앗';     Cry = '쑥!';   Evolve = '' }
    @{ Min = 10;  Name = '새싹';     Cry = '새록!'; Evolve = '싹이 났어요!' }
    @{ Min = 50;  Name = '꽃봉오리'; Cry = '새록!'; Evolve = '꽃봉오리가 생겼어요!' }
    @{ Min = 150; Name = '꽃요정';   Cry = '새록!'; Evolve = '꽃이 활짝 폈어요!' }
)

function RoundRect($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); $p
}

# 새록이 그리기 ---------------------------------------------------------
$eye    = C 60 45 45
$blushC = C 255 150 170 150
$leafC  = C 160 225 120
$leafLn = C 95 165 75
$bodyC  = C 175 230 140

# 얼굴: 반짝 눈(또는 감은 눈), 작은 입, 볼터치
function Draw-Face($g, $cx, $cy, $gap, [switch]$Sleepy) {
    if ($Sleepy) {
        $pen = P $eye 1.8
        $g.DrawArc($pen, $cx - $gap - 4, $cy - 3, 8, 6, 0, 180)
        $g.DrawArc($pen, $cx + $gap - 4, $cy - 3, 8, 6, 0, 180)
    } else {
        foreach ($ex in ($cx - $gap), ($cx + $gap)) {
            $g.FillEllipse((B $eye), $ex - 3.5, $cy - 4.5, 7, 8)
            $g.FillEllipse((B $white), $ex - 1.8, $cy - 3, 3, 3)
        }
        $g.DrawArc((P $eye 1.4), $cx - 3, $cy + 2, 6, 5, 0, 180)
    }
    $g.FillEllipse((B $blushC), $cx - $gap - 10, $cy + 3, 8, 5)
    $g.FillEllipse((B $blushC), $cx + $gap + 2, $cy + 3, 8, 5)
}

# (x,y)를 밑동으로 angle만큼 기울인 잎/꽃잎 모양 타원
function Draw-Leaf($g, $x, $y, $angle, $w, $h, $fill = $leafC, $line = $leafLn) {
    $st = $g.Save()
    $g.TranslateTransform($x, $y); $g.RotateTransform($angle)
    $g.FillEllipse((B $fill), -$w / 2, -$h, $w, $h)
    $g.DrawEllipse((P $line 1.5), -$w / 2, -$h, $w, $h)
    $g.Restore($st)
}

function Draw-Sparkle($g, $x, $y, $r) {
    $pts = [System.Drawing.PointF[]]@((Pt $x ($y - $r)), (Pt ($x + $r * 0.3) ($y - $r * 0.3)), (Pt ($x + $r) $y), (Pt ($x + $r * 0.3) ($y + $r * 0.3)),
        (Pt $x ($y + $r)), (Pt ($x - $r * 0.3) ($y + $r * 0.3)), (Pt ($x - $r) $y), (Pt ($x - $r * 0.3) ($y - $r * 0.3)))
    $g.FillPolygon((B (C 255 210 90)), $pts)
}

function Draw-Pet($g, $stage, $cx, $cy) {
    $zFont = New-Object System.Drawing.Font('Malgun Gothic', 8, [System.Drawing.FontStyle]::Bold)
    switch ($stage) {
        0 { # 씨앗: 흙 위에서 쿨쿨
            $g.FillEllipse((B (C 165 125 95)), $cx - 30, $cy + 16, 60, 18)
            $g.FillEllipse((B (C 215 160 105)), $cx - 16, $cy - 18, 32, 40)
            $g.DrawEllipse((P (C 160 110 70) 2), $cx - 16, $cy - 18, 32, 40)
            $g.DrawArc((P (C 160 110 70) 1.5), $cx - 6, $cy - 16, 12, 10, 200, 140)
            Draw-Face $g $cx ($cy + 4) 6 -Sleepy
            $g.DrawString('z', $zFont, (B (C 160 110 70)), $cx + 16, $cy - 28)
        }
        1 { # 새싹: 머리에 떡잎 두 장
            $g.DrawLine((P $leafLn 2.5), $cx, $cy - 10, $cx, $cy - 22)
            Draw-Leaf $g $cx ($cy - 20) -50 12 20
            Draw-Leaf $g $cx ($cy - 20) 50 12 20
            $g.FillEllipse((B $bodyC), $cx - 21, $cy - 12, 42, 42)
            $g.DrawEllipse((P $leafLn 2), $cx - 21, $cy - 12, 42, 42)
            Draw-Face $g $cx ($cy + 8) 8
        }
        2 { # 꽃봉오리: 머리 위 분홍 봉오리, 잎사귀 팔
            Draw-Leaf $g ($cx - 18) ($cy + 14) -115 10 18
            Draw-Leaf $g ($cx + 18) ($cy + 14) 115 10 18
            $g.DrawLine((P $leafLn 2.5), $cx, $cy - 6, $cx, $cy - 20)
            $g.FillEllipse((B (C 255 170 200)), $cx - 10, $cy - 40, 20, 24)
            $g.DrawEllipse((P (C 235 120 160) 1.5), $cx - 10, $cy - 40, 20, 24)
            Draw-Leaf $g $cx ($cy - 18) -35 8 12
            Draw-Leaf $g $cx ($cy - 18) 35 8 12
            $g.FillEllipse((B $bodyC), $cx - 22, $cy - 8, 44, 42)
            $g.DrawEllipse((P $leafLn 2), $cx - 22, $cy - 8, 44, 42)
            Draw-Face $g $cx ($cy + 12) 8
        }
        3 { # 꽃요정: 분홍 꽃잎 여섯 장, 노란 얼굴
            $g.DrawLine((P $leafLn 3), $cx, $cy + 10, $cx, $cy + 36)
            Draw-Leaf $g $cx ($cy + 30) -60 9 16
            Draw-Leaf $g $cx ($cy + 30) 60 9 16
            for ($k = 0; $k -lt 6; $k++) { Draw-Leaf $g $cx ($cy - 8) ($k * 60) 22 38 (C 255 175 205) (C 240 125 165) }
            $g.FillEllipse((B (C 255 228 120)), $cx - 18, $cy - 26, 36, 36)
            $g.DrawEllipse((P (C 230 180 60) 2), $cx - 18, $cy - 26, 36, 36)
            Draw-Face $g $cx ($cy - 9) 7
            Draw-Sparkle $g ($cx + 34) ($cy - 30) 5
        }
    }
}

$W = 270; $H = 140
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form = New-Object System.Windows.Forms.Form -Property @{
    FormBorderStyle = 'None'
    StartPosition   = 'Manual'
    TopMost         = $true
    ShowInTaskbar   = $false
    BackColor       = $cream
    Size            = New-Object System.Drawing.Size($W, $H)
}
$form.Location = New-Object System.Drawing.Point(($wa.Right - $W - 20), ($wa.Bottom - $H - 20))
$form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true)
$form.Region = New-Object System.Drawing.Region (RoundRect 0 0 $W $H 22)

# 화면 그리기: $script:view 내용대로 전부 직접 그린다
$script:view = $null
$form.Add_Paint({
    $v = $script:view
    if (-not $v) { return }
    $g = $_.Graphics
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'

    $g.DrawPath((P $pink 3), (RoundRect 1.5 1.5 ($W - 3) ($H - 3) 21))
    $g.DrawString([string][char]0x00D7, $fClose, (B $pinkDk), $W - 22, 6)

    # 캐릭터
    $g.FillEllipse((B (C 255 236 240)), 16, 28, 88, 88)
    Draw-Pet $g $v.Stage 60 72

    # 이름 + Lv 배지
    $g.DrawString($v.Title, $fTitle, (B $brown), 116, 14)
    $tw = $g.MeasureString($v.Title, $fTitle).Width
    $g.FillPath((B $pinkDk), (RoundRect (118 + $tw) 18 34 16 8))
    $g.DrawString("Lv.$($v.Lv)", $fBadge, (B $white), 121 + $tw, 18)

    # 하트 경험치 막대
    $g.DrawString([string][char]0x2665, $fBadge, (B $pinkDk), 114, 43)
    $g.FillPath((B (C 255 225 230)), (RoundRect 130 46 120 12 6))
    $g.FillPath((B $pinkDk), (RoundRect 130 46 ([math]::Max(12.0, 120.0 * $v.Progress)) 12 6))
    $g.DrawString($v.ExpText, $fExp, (B $brown), 130, 60)

    # 말풍선
    $bubble = RoundRect 116 86 140 36 14
    $g.FillPath((B $white), $bubble)
    $g.DrawPath((P $pink 2), $bubble)
    $tail = [System.Drawing.PointF[]]@((Pt 117 98), (Pt 107 104), (Pt 117 110))
    $g.FillPolygon((B $white), $tail)
    $g.DrawLines((P $pink 2), $tail)
    $sf = New-Object System.Drawing.StringFormat -Property @{ Alignment = 'Center'; LineAlignment = 'Center' }
    $g.DrawString($v.Msg, $fBubble, (B $brown), (New-Object System.Drawing.RectangleF(116, 86, 140, 36)), $sf)
})

# 마우스: × 를 누르면 닫고, 나머지는 끌어서 옮기기
function Test-Close($e) { $e.X -ge ($W - 26) -and $e.Y -le 26 }
$script:dragging = $false
$form.Add_MouseDown({
    if ($_.Button -ne 'Left') { return }
    if (Test-Close $_) { $form.Close(); return }
    $p = [System.Windows.Forms.Cursor]::Position
    $script:dx = $p.X - $form.Left; $script:dy = $p.Y - $form.Top; $script:dragging = $true
})
$form.Add_MouseMove({
    $form.Cursor = if (Test-Close $_) { 'Hand' } else { 'Default' }
    if ($script:dragging) { $p = [System.Windows.Forms.Cursor]::Position; $form.Location = New-Object System.Drawing.Point(($p.X - $script:dx), ($p.Y - $script:dy)) }
})
$form.Add_MouseUp({ $script:dragging = $false })

# 상태 갱신: 단계, 경험치, 기분(배고픔), 이벤트 문구
$script:lastFed = $null
$script:lastStage = -1
$script:eventUntil = Get-Date
function Update-View {
    $s = Read-State
    $exp = if ($s) { [double]$s.exp } else { 0 }
    $i = @($stages | Where-Object { $exp -ge $_.Min }).Count - 1
    $st = $stages[$i]

    if ($i -lt $stages.Count - 1) {
        $lo = $st.Min; $hi = $stages[$i + 1].Min
        $progress = [math]::Min(1.0, ($exp - $lo) / ($hi - $lo))
        $expText = '{0:0.0} / {1} EXP' -f $exp, $hi
    } else {
        $progress = 1.0
        $expText = '{0:0.0} EXP  MAX' -f $exp
    }

    # 방금 밥을 먹었으면 6초 동안 이벤트 문구 (진화했으면 진화 문구)
    $fed = if ($s) { [string]$s.lastFed } else { $null }
    if ($script:lastFed -and $fed -ne $script:lastFed) {
        $script:eventText = if ($i -gt $script:lastStage) { $st.Evolve } else { '{0} +{1:0.0} EXP' -f $st.Cry, $s.lastGain }
        $script:eventUntil = (Get-Date).AddSeconds(6)
    }
    $script:lastFed = if ($fed) { $fed } else { '-' }
    $script:lastStage = $i

    $hours = if ($s -and $s.lastFed) { ((Get-Date) - [datetime]$s.lastFed).TotalHours } else { 0 }
    $msg = if ((Get-Date) -lt $script:eventUntil) { $script:eventText }
           elseif ($i -eq 0) {
               if ($hours -lt 6) { '쿨쿨... 싹 틔울 꿈' } elseif ($hours -lt 24) { '흙이 말라가요...' }
               elseif ($hours -lt 72) { '목말라요...' } else { '시들기 직전...' }
           } else {
               if ($hours -lt 6) { '새록새록~ 배불러요' } elseif ($hours -lt 24) { '새록~ 심심해요' }
               elseif ($hours -lt 72) { '새록... 목말라요...' } else { '시들기 직전...' }
           }

    $new = @{ Title = $st.Name; Lv = $i + 1; Stage = $i; Progress = $progress; ExpText = $expText; Msg = $msg }
    $key = "$($new.Title)|$($new.Progress)|$($new.ExpText)|$($new.Msg)"
    if ($key -ne $script:viewKey) { $script:view = $new; $script:viewKey = $key; $form.Invalidate() }
}

$timer = New-Object System.Windows.Forms.Timer -Property @{ Interval = 1000 }
$timer.Add_Tick({ Update-View })
Update-View
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
$timer.Dispose()
$mutex.ReleaseMutex()
