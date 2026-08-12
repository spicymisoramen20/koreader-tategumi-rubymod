# Windows desktop package (MinGW cross-build from Linux, or native MSYS2).
WIN32_PACKAGE = koreader-win32$(KODEDUG_SUFFIX)-$(VERSION).zip

define UPDATE_PATH_EXCLUDES +=
tools
endef

update: all
	# Package the install tree; runtime DLLs are already linked in from
	# platform/win32 by the top-level Makefile when WIN32=1.
	$(strip $(call mkupdate,$(WIN32_PACKAGE)))
