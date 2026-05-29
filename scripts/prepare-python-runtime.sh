#!/usr/bin/env bash
set -euo pipefail

VARIANT="${1:-cuda}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RUNTIME_DIR="${RUNTIME_DIR:-python-runtime}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu126}"

rm -rf "$RUNTIME_DIR"
"$PYTHON_BIN" -m venv "$RUNTIME_DIR"
PY="$RUNTIME_DIR/bin/python"

"$PY" -m pip install --upgrade pip setuptools wheel
if [[ -z "$TORCH_INDEX_URL" ]]; then
  "$PY" -m pip install --no-cache-dir torch
else
  "$PY" -m pip install --no-cache-dir torch --index-url "$TORCH_INDEX_URL"
fi
"$PY" -m pip install --no-cache-dir av librosa numpy pyyaml tqdm

bash "$(dirname "$0")/prune-python-runtime.sh" "$RUNTIME_DIR"
"$PY" - <<'PY'
import torch, librosa, av, yaml, tqdm
print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cuda_available', torch.cuda.is_available())
print('librosa', librosa.__version__)
print('av', av.__version__)
PY
