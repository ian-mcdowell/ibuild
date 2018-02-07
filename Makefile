TOOL_NAME = ibuild
VERSION = 1.0.0

PREFIX = /usr/local
INSTALL_PATH = $(PREFIX)/bin/$(TOOL_NAME)
BUILD_PATH = .build/release/$(TOOL_NAME)
CURRENT_PATH = $(PWD)
REPO = https://github.com/IMcD23/$(TOOL_NAME)
RELEASE_ZIP = $(REPO)/archive/$(VERSION).zip
SHA = $(shell curl -L -s $(RELEASE_ZIP) | shasum -a 256 | sed 's/ .*//')

.PHONY: install build uninstall format_code update_brew release

install: build
	mkdir -p $(PREFIX)/bin
	cp -f $(BUILD_PATH) $(INSTALL_PATH)

build:
	swift build --disable-sandbox -c release -Xswiftc -static-stdlib

uninstall:
	rm -rf $(INSTALL_PATH)

release:
	git add .
	git commit -m "Update to $(VERSION)"
	git tag $(VERSION)