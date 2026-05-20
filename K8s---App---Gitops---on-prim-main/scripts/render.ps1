# يبني manifests من Kustomize ويحفظها في .render/ للمراجعة أو kubectl apply
param(
    [ValidateSet("development", "production", "monitoring", "all")]
    [string]$Environment = "all"
)

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = Join-Path $Root ".render"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Render-Overlay {
    param([string]$Name, [string]$OverlayPath)
    $out = Join-Path $OutDir "$Name.yaml"
    Write-Host "Building $Name -> $out"
    kubectl kustomize $OverlayPath | Set-Content -Path $out -Encoding utf8
}

$overlays = @{
    development = Join-Path $Root "apps\overlays\development"
    production  = Join-Path $Root "apps\overlays\production"
    monitoring  = Join-Path $Root "apps\overlays\monitoring"
}

if ($Environment -eq "all") {
    foreach ($key in $overlays.Keys) {
        Render-Overlay -Name $key -OverlayPath $overlays[$key]
    }
} else {
    Render-Overlay -Name $Environment -OverlayPath $overlays[$Environment]
}

Write-Host "Done. Review files in .render/ then apply when ready."
