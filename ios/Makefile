# Theos application (style follows caprice32ios/Makefile). Run ../build-ios-cldc.sh first.
export THEOS_DEVICE_IP =
ARCHS = armv7
TARGET = iphone:clang:9.3:7.0
INSTALL_TARGET_PROCESSES = pspkvm
export THEOS ?= /opt/theos
include $(THEOS)/makefiles/common.mk

SDK_ROOT ?= $(THEOS)/sdks/iPhoneOS9.3.sdk
KVM_ROOT  = $(abspath ..)
KVM_DIST  = $(KVM_ROOT)/build-ios/dist
KVM_LIBS  = $(KVM_DIST)/lib

APPLICATION_NAME = pspkvm
pspkvm_FILES = main.m KVMAppDelegate.m KVMBridge.m KVMScreenView.m KVMPadView.m KVMShims.c
ADDITIONAL_CFLAGS += -O2 -fno-stack-protector -fobjc-arc \
	-fno-modules -fno-cxx-modules -fno-implicit-modules -fno-implicit-module-maps \
	-Wno-error=objc-property-no-attribute -Wno-error=property-attribute-mismatch
pspkvm_CFLAGS = -DIOS -I$(SDK_ROOT)/usr/include \
	-I$(KVM_ROOT)/javacall/implementation/ios_arm/midp -I$(KVM_ROOT)/javacall/implementation/ios_arm
pspkvm_LDFLAGS = -L$(KVM_LIBS) -L$(SDK_ROOT)/usr/lib \
	-lmidp -ljavacall -lcldc_vm -lpcsl_file -lpcsl_string -lpcsl_memory -lpcsl_network -lpcsl_print -lfreetype -lc++ \
	-framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
	-framework AVFoundation -framework CoreMedia -framework CoreVideo -framework AudioToolbox
pspkvm_CODESIGN_FLAGS =
pspkvm_PLIST = Info.plist

include $(THEOS_MAKE_PATH)/application.mk

# Stage the runtime tree (lib/, appdb/, ini) into the bundle as kvm/
before-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Applications/pspkvm.app/kvm"
	@cp -R $(KVM_DIST)/midp/* "$(THEOS_STAGING_DIR)/Applications/pspkvm.app/kvm/"
	@cp $(KVM_ROOT)/psp/pspkvm.ini "$(THEOS_STAGING_DIR)/Applications/pspkvm.app/kvm/"
