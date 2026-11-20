param(
    [string]$GameDir = 'D:\SteamLibrary\steamapps\common\ProjectZomboid',
    [string]$ZombieBuddyJar = 'D:\SteamLibrary\steamapps\workshop\content\108600\3619862853\mods\ZombieBuddy\libs\ZombieBuddy.jar',
    [string]$JdkDir = 'C:\Users\Maeiro\Documents\ChatGPT\PZ - Performance\build\jdk25\jdk-25.0.5+8'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src'
$javaDir = Join-Path $root 'content\mods\ViewpointStayWithMeInteractions\42\media\java\client'
$gameJar = Join-Path $GameDir 'projectzomboid.jar'
$javac = Join-Path $JdkDir 'bin\javac.exe'
$jar = Join-Path $JdkDir 'bin\jar.exe'
foreach ($file in @($javac, $jar, $gameJar, $ZombieBuddyJar)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Build input not found: $file" }
}

$tempRoot = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path
$classes = Join-Path $tempRoot ("stay-with-me-viewpoint-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $classes | Out-Null
try {
    $sources = @(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.java' | Sort-Object FullName | ForEach-Object FullName)
    & $javac --release 17 -Xlint:all -classpath "$gameJar;$ZombieBuddyJar" -d $classes @sources
    if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
    New-Item -ItemType Directory -Path $javaDir -Force | Out-Null
    $output = Join-Path $javaDir 'StayWithMeViewpointInteractions.jar'
    & $jar --create --date=2026-11-20T00:00:00Z --file $output -C $classes .
    if ($LASTEXITCODE -ne 0) { throw 'JAR packaging failed.' }
    Get-FileHash -LiteralPath $output -Algorithm SHA256
} finally {
    $resolved = (Resolve-Path -LiteralPath $classes).Path
    if ((Split-Path -Parent $resolved) -eq $tempRoot -and
            (Split-Path -Leaf $resolved) -match '^stay-with-me-viewpoint-[a-f0-9-]{36}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
