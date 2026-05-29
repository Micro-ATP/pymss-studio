param(
    [ValidateSet("cuda")]
    [string]$Variant = "cuda",
    [string]$Python = "python",
    [string]$RuntimeDir = "python-runtime",
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/cu126"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$runtime = Join-Path $root $RuntimeDir

if (Test-Path -LiteralPath $runtime) {
    Remove-Item -LiteralPath $runtime -Recurse -Force
}

& $Python -m venv $runtime
$runtimePython = if ($IsWindows -or $env:OS -eq "Windows_NT") {
    Join-Path $runtime "Scripts\python.exe"
} else {
    Join-Path $runtime "bin/python"
}

& $runtimePython -m pip install --upgrade pip setuptools wheel
if ([string]::IsNullOrWhiteSpace($TorchIndexUrl)) {
    & $runtimePython -m pip install --no-cache-dir torch
} else {
    & $runtimePython -m pip install --no-cache-dir torch --index-url $TorchIndexUrl
}
& $runtimePython -m pip install --no-cache-dir av librosa numpy pyyaml tqdm

& (Join-Path $PSScriptRoot "prune-python-runtime.ps1") -RuntimeDir $runtime
& $runtimePython -c "import torch, librosa, av, yaml, tqdm; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available()); print('librosa', librosa.__version__); print('av', av.__version__)"
