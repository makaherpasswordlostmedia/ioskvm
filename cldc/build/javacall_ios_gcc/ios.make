# Cross toolchain for the *target* (armv7 iOS). Host tools use the host gcc -m32.
# Defaults mirror build-ios-cldc.sh / the CI (vanilla clang from the Theos Linux iOS toolchain).
IOS_SDK    ?= $(THEOS)/sdks/iPhoneOS9.3.sdk
IOS_MIN    ?= 7.0
IOS_CC     ?= $(THEOS)/toolchain/linux/iphone/bin/clang
IOS_CXX    ?= $(THEOS)/toolchain/linux/iphone/bin/clang++
IOS_AR     ?= $(THEOS)/toolchain/linux/iphone/bin/llvm-ar
IOS_TARGET_FLAGS ?= --target=armv7-apple-ios$(IOS_MIN) -isysroot $(IOS_SDK)
IOS_CFLAGS ?= $(IOS_TARGET_FLAGS) -O2 -fno-strict-aliasing -fno-stack-protector -fno-modules -fno-implicit-modules -fno-implicit-module-maps -Wno-error -Wno-register -Wno-reserved-user-defined-literal
export IOS_CC IOS_CXX IOS_AR IOS_CFLAGS
