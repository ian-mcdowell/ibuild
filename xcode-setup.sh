#!/bin/bash

REPO=${SCRIPT_INPUT_FILE_0}
DESTINATION=${BUILT_PRODUCTS_DIR}

if [ -z "$REPO" ]; then
    echo "Please provide a path to the repository as the input file in Xcode";
    exit 1;
fi

CC=$(xcrun -sdk ${SDKROOT} -find clang)
CXX=$(xcrun -sdk ${SDKROOT} -find clang++)
AR=$(xcrun -sdk ${SDKROOT} -find ar)
RANLIB=$(xcrun -sdk ${SDKROOT} -find ranlib)

get_arch_install_dir() {
    echo "$DESTINATION/$ARCH"
}

get_per_arch_args() {
    if [ ! -z "$PER_ARCH_ARGS" ]; then
        echo $(defaults read ${PER_ARCH_ARGS} ${PLATFORM_NAME}-${ARCH})
    fi
}