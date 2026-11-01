#!/bin/bash
# Retrain on this Mac (with its GPU) and, if the new model is better, push it
# to main, which builds and uploads to TestFlight. Same steps as the
# "Astrotype train" workflow. Options go to train_and_ship.py, e.g.
#   ./train_and_ship.sh --minutes 15
set -euo pipefail
cd "$(dirname "$0")"
git checkout main
git pull --ff-only origin main
source .venv/bin/activate
python3 train_and_ship.py "$@"
grep -q '^\*\*Shipped' runs/report.md || exit 0
swift test --package-path ../ios/AstrotypeKit
git add export models ../ios/Astrotype/Model
{ echo "Astrotype: model trained on recorded samples"; echo; cat runs/report.md; } | git commit -F -
git push origin main
