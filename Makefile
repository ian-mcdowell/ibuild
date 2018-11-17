TOOL_NAME = ibuild

PREFIX = /usr/local
INSTALL_PATH = $(PREFIX)/bin/$(TOOL_NAME)
BUILD_PATH = .build/release/$(TOOL_NAME)

.PHONY: install build clean uninstall

default: build

install: build
	mkdir -p $(PREFIX)/bin
	cp -f $(BUILD_PATH) $(INSTALL_PATH)

build:
	swift build -c release -Xcxx -UDEBUG -Xlinker -lsqlite3 -Xlinker -lncurses -Xswiftc -DLLBUILD_C_API_VERSION_6 --disable-sandbox

clean:
	rm -rf $(BUILD_PATH)

uninstall:
	rm -rf $(INSTALL_PATH)
