# Astrotype: the everyday commands. Run `make` to see them.
#
# Python commands use ml/.venv (created by `make setup`). Variables you can
# set on the command line: MINUTES=15 (training time), MODEL=runs/x.pt.

ML := ml
PY := $(ML)/.venv/bin/python3
MINUTES ?= 6
MODEL ?= $(ML)/models/shipped.pt

.DEFAULT_GOAL := help
.PHONY: help setup download eval train train-dry test build samples lexicon

help: ## Show this list
	@echo "Astrotype commands (run from apps/astrotype):"
	@echo
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sort | awk -F ':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'
	@echo
	@echo "Options: MINUTES=15 (train time), MODEL=path/to/weights.pt (eval)."

setup: ## Create ml/.venv and install the Python packages (Python 3.13)
	cd $(ML) && python3.13 -m venv .venv && .venv/bin/pip install -r requirements.txt

download: ## Download samples recorded in the app from iCloud to ml/samples/cloud
	cd $(ML) && .venv/bin/python3 download_samples.py

eval: download ## Score a model on the recorded phrases (MODEL=...)
	cd $(ML) && .venv/bin/python3 eval_real.py samples/cloud --model $(patsubst $(ML)/%,%,$(MODEL)) --show 20

train: ## Download, retrain, and push a TestFlight build if the new model is better (MINUTES=6)
	$(ML)/train_and_ship.sh --minutes $(MINUTES)

train-dry: ## Same as train, but never commits or pushes
	cd $(ML) && .venv/bin/python3 train_and_ship.py --minutes $(MINUTES) --force && cat runs/report.md

samples: ## How many samples are recorded, by kind
	@cd $(ML) && .venv/bin/python3 -c "import samples as S; \
	  s = S.load(['samples/cloud'], phrases=True); \
	  p = sum(x.get('version', 1) >= 2 for x in s); \
	  print(f'{len(s)} samples: {p} phrases with finger lifts, {len(s) - p} single-stroke words')"

test: ## Run the Swift package tests (features, decoder, Core ML parity)
	swift test --package-path ios/AstrotypeKit

build: ## Build the iOS app for the simulator
	cd ios && xcodebuild build -project Astrotype.xcodeproj -scheme Astrotype \
	  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet
