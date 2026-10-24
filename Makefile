TARGET := iphone:clang:16.5:15.0
ARCHS := arm64
export LD_LIBRARY_PATH := $(THEOS)/toolchain/linux/host/lib:$(THEOS)/toolchain/linux/iphone/lib:$(LD_LIBRARY_PATH)

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ValidationRelay

# Source files
ValidationRelay_FILES = \
    ValidationRelay/absdUser.c \
    ValidationRelay/ValidationRelayApp.swift \
    ValidationRelay/ContentView.swift \
    ValidationRelay/LogView.swift \
    ValidationRelay/Relay.swift \
    ValidationRelay/ValidationData.swift \
    $(shell find vendor/NWWebSocket/Sources -name '*.swift' 2>/dev/null)

ValidationRelay_FRAMEWORKS = UIKit SwiftUI Foundation Network
ValidationRelay_LIBRARIES = MobileGestalt
ValidationRelay_SWIFTFLAGS = -import-objc-header $(CURDIR)/ValidationRelay/ValidationRelay-Bridging-Header.h -I$(CURDIR)/ValidationRelay
ValidationRelay_CODESIGN_FLAGS = -S$(CURDIR)/ValidationRelay/ValidationRelay.entitlements -Icom.jakecrowley.ValidationRelayNew

include $(THEOS_MAKE_PATH)/application.mk

after-all::
	@echo "Creating TrollStore .tipa package..."
	@rm -rf Payload ValidationRelay.tipa
	@mkdir -p Payload
	@if [ -d "$(THEOS_OBJ_DIR)/ValidationRelay.app" ]; then \
		cp -r $(THEOS_OBJ_DIR)/ValidationRelay.app Payload/; \
	elif [ -d "$(THEOS_STAGING_DIR)/Applications/ValidationRelay.app" ]; then \
		cp -r $(THEOS_STAGING_DIR)/Applications/ValidationRelay.app Payload/; \
	fi
	@if [ -d "Payload/ValidationRelay.app" ]; then \
		cp -r $(CURDIR)/Resources/* Payload/ValidationRelay.app/; \
		zip -qry ValidationRelay.tipa Payload; \
		rm -rf Payload; \
		echo "==> Successfully created ValidationRelay.tipa!"; \
	else \
		echo "==> Warning: Could not find ValidationRelay.app to package."; \
	fi
