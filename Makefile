# Gurbani Soul (iOS) — developer entrypoints. `make help` lists targets.
MARKETING_VERSION = $(shell python3 -c "import re;print(re.search(r'MARKETING_VERSION:\s*\"([^\"]+)\"',open('ios/App/project.yml').read()).group(1))")

.PHONY: help doctor dataset dataset-check vendor-check vendor-sync-platform vendor-sync-data check-versions test-ios-gates gates ios-db ios-db-check ios-db-repair parity project testflight-next testflight appstore-preflight
help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n",$$1,$$2}'

doctor: ## check the local toolchain and the database pair
	@command -v xcodebuild >/dev/null && xcodebuild -version | head -1 || echo "  Xcode missing"
	@command -v xcodegen >/dev/null && echo "xcodegen: ok" || echo "  xcodegen missing — brew install xcodegen"
	@test -f db/sggs.sqlite && head -c 16 db/sggs.sqlite | grep -q "SQLite format 3" && echo "db: real SQLite" || echo "  db/sggs.sqlite missing — run: make dataset"
	@python3 pipeline/check_ios_db_pair.py || true

dataset: ## install db/sggs.sqlite from the pinned sggs-data object (dataset.lock.json), sha256-verified
	python3 scripts/data/fetch_dataset.py --cache-dir .dataset-cache

dataset-check: ## sggs-data@commit publishes the pinned database
	python3 scripts/data/fetch_dataset.py --check-pin

vendor-check: ## vendored platform/data files == vendor.lock.json (add REMOTE=1 to also compare with their sources)
	python3 scripts/vendor_sync.py check $(if $(REMOTE),--remote,)

vendor-sync-platform: ## re-vendor the golden contract, contributors + brand tokens from a platform ref: make vendor-sync-platform REF=v1.3.8
	@test -n "$(REF)" || { echo "usage: make vendor-sync-platform REF=vX.Y.Z"; exit 2; }
	python3 scripts/vendor_sync.py sync platform $(REF)

vendor-sync-data: ## re-vendor the iOS DB builder from dataset.lock.json's sggs-data commit
	python3 scripts/vendor_sync.py sync data

check-versions: ## MARKETING_VERSION == the vendored platform release; build-number invariants
	python3 scripts/release/check_versions.py

test-ios-gates: ## iOS source/listing/archive gates, no simulator (ios/tests)
	python3 -m unittest discover -s ios/tests -v

gates: vendor-check check-versions test-ios-gates ## the gates CI runs without a Mac

ios-db: ## rebuild both iOS SQLite profiles + licence gate
	python3 pipeline/build_ios_db.py --profile personal
	python3 pipeline/build_ios_db.py --profile public
	bash pipeline/check_release_license.sh

ios-db-check: ## does ios/Resources/sggs-ios.sqlite hash to its manifest? (after a branch switch / in a new worktree)
	python3 pipeline/check_ios_db_pair.py

ios-db-repair: ## rebuild the personal iOS DB the app/tests bundle, then check the pair (never touches git)
	@head -c 16 db/sggs.sqlite | grep -q "SQLite format 3" || (echo "db/sggs.sqlite missing — run: make dataset"; exit 1)
	python3 pipeline/build_ios_db.py --profile personal
	python3 pipeline/check_ios_db_pair.py

parity: ## Swift kit parity against the golden contract on the vendored SQLite
	swift test --package-path ios/Packages/GurbaniSearchKit

project: ## generate ios/App/SGGS.xcodeproj from project.yml
	xcodegen generate --spec ios/App/project.yml --project ios/App

testflight-next: ## the next TestFlight build number for the current marketing version
	@echo "version $(MARKETING_VERSION) — next build: $$(python3 ios/tools/testflight_ledger.py next $(MARKETING_VERSION))"

testflight: ## archive + gate + export/upload (macOS): make testflight TEAM_ID=… BUILD=N [CHANNEL=testflight|appstore] [PROFILE=public] [UPLOAD=1]
	@test -n "$(TEAM_ID)" || { echo "usage: make testflight TEAM_ID=ABCDE12345 BUILD=N [PROFILE=public|personal] [UPLOAD=1]"; exit 1; }
	@test -n "$(BUILD)" || { echo "usage: make testflight TEAM_ID=ABCDE12345 BUILD=N [PROFILE=public|personal] [UPLOAD=1]"; \
		echo "version $(MARKETING_VERSION) — next build: $$(python3 ios/tools/testflight_ledger.py next $(MARKETING_VERSION))"; exit 1; }
	SGGS_TEAM_ID=$(TEAM_ID) SGGS_BUILD_NUMBER=$(BUILD) SGGS_DB_PROFILE=$(or $(PROFILE),public) SGGS_RELEASE_CHANNEL=$(or $(CHANNEL),testflight) SGGS_UPLOAD=$(or $(UPLOAD),0) bash ios/tools/testflight_archive.sh

appstore-preflight: ## may this version be SUBMITTED? newest ledger build must be channel=appstore, review signed, versions + listing clean
	python3 ios/tools/appstore_preflight.py $(MARKETING_VERSION)
