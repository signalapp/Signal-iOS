# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

WORKING_DIR = ./
THIRD_PARTY_DIR = $(WORKING_DIR)/ThirdParty
SCHEME = Signal
XCODE_BUILD = xcrun xcodebuild -workspace $(SCHEME).xcworkspace -scheme $(SCHEME) -sdk iphonesimulator
SETUP_HOOK_PATH = $(HOME)/.ci/setup.sh

.PHONY: build test retest clean dependencies

default: test

update_dependencies:
	bundle exec pod update
	carthage update --platform iOS

setup:
	[ -x ${SETUP_HOOK_PATH} ] && ${SETUP_HOOK_PATH}
	rbenv install -s
	gem install bundler
	bundle install

dependencies:
	cd $(WORKING_DIR) && \
		git submodule foreach --recursive git clean -xfd && \
		git submodule foreach --recursive git reset --hard && \
		git submodule update --init
		cd $(THIRD_PARTY_DIR) && \
			carthage build --platform iOS

build: dependencies
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) build | bundle exec xcpretty

test:
	bundle exec fastlane test

clean: clean_carthage
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) clean | bundle exec xcpretty

clean_carthage:
	cd $(THIRD_PARTY_DIR) && \
		rm -fr Carthage/Build

# Migrating across swift versions requires me to run this sometimes
clean_carthage_cache:
	rm -fr ~/Library/Caches/org.carthage.CarthageKit/
