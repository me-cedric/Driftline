.PHONY: bootstrap build test run lint package-dmg ui-smoke iconset integration-up integration-down

bootstrap:
	./scripts/bootstrap.sh

build:
	swift build

test:
	swift test

run:
	./script/build_and_run.sh

lint:
	./scripts/lint.sh

package-dmg:
	./scripts/package-dmg.sh

ui-smoke:
	./scripts/ui-smoke.sh

iconset:
	./scripts/generate-iconset.sh

integration-up:
	./scripts/integration-sftp-server.sh start

integration-down:
	./scripts/integration-sftp-server.sh stop
