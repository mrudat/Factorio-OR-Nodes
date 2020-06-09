.SUFFIXES:

# commands
LUAC := luac
LUACHECK := luacheck
ZIP := zip -r
GIT := git

# directories
FACTORIO_MODS := ~/.Factorio/mods

# override the above with local values in the optional local.mk
-include local.mk
# read and cache PACKAGE_NAME/VERSION
-include info.mk

OUTPUT_NAME := $(PACKAGE_NAME)_$(VERSION_STRING)

OUTPUT_DIR := build/$(OUTPUT_NAME)

COPY_FILES := $(wildcard *.png **/*.png)
COPY_FILES += $(wildcard locale/**/*.cfg)

SED_FILES += $(wildcard *.md **/*.md)
SED_FILES += $(wildcard *.txt **/*.txt)
SED_FILES += $(wildcard *.json **/*.json)

LUA_FILES := $(wildcard *.lua **/*.lua)

TARGET_FILES := $(COPY_FILES)
TARGET_FILES += $(SED_FILES)
TARGET_FILES += $(LUA_FILES)

TEST_FILES := $(filter test/%,$(TARGET_FILES))
TARGET_FILES := $(filter-out test/%,$(TARGET_FILES))

TARGET_FILES := $(addprefix $(OUTPUT_DIR)/,$(TARGET_FILES))

TARGET_FILES += $(addprefix build/,$(TEST_FILES))

TARGET_DIRS := $(sort $(dir $(TARGET_FILES)))

SED_EXPRS := -e 's/{{MOD_NAME}}/$(PACKAGE_NAME)/g'
SED_EXPRS += -e 's/{{VERSION}}/$(VERSION_STRING)/g'

.PHONY: all
all: verify package install

.PHONY: release
release: verify package install tag

.PHONY: directories
directories: | $(TARGET_DIRS)

$(TARGET_DIRS):
	mkdir -p $@

.PHONY: package-copy
package-copy: directories $(TARGET_FILES)

.PHONY: package
package: package-copy
	cd build && $(ZIP) $(OUTPUT_NAME).zip $(OUTPUT_NAME)

.PHONY: clean
clean:
	rm -f info.mk
	rm -rf build/

.PHONY: verify
verify:
	$(LUACHECK) $(LUA_FILES)

.PHONY: install
install: package-copy
	if [ -d $(FACTORIO_MODS) ]; then \
		rm -rf $(FACTORIO_MODS)/$(OUTPUT_NAME) ; \
		cp -R build/$(OUTPUT_NAME) $(FACTORIO_MODS) ; \
		rm -rf $(FACTORIO_MODS)/"Test mod_0.0.1" ; \
		cp -R build/test $(FACTORIO_MODS)/"Test mod_0.0.1" ; \
	fi;

.PHONY: tag
tag:
	$(git) tag -f $(VERSION_STRING)

$(OUTPUT_DIR)/%.png: %.png
	cp $< $@

$(OUTPUT_DIR)/%.cfg: %.cfg
	cp $< $@

$(OUTPUT_DIR)/%.md: %.md info.mk
	sed $(SED_EXPRS) $< > $@

$(OUTPUT_DIR)/%.txt: %.txt info.mk
	sed $(SED_EXPRS) $< > $@

$(OUTPUT_DIR)/%.json: %.json info.mk
	sed $(SED_EXPRS) $< > $@

$(OUTPUT_DIR)/%.lua: %.lua info.mk
	sed $(SED_EXPRS) $< > $@
	$(LUAC) -p $@

build/test/%: test/%
	cp $< $@

info.mk: info.json
	echo "PACKAGE_NAME := $$(jq -r .name < $<)\nVERSION_STRING := $$(jq -r .version < $<)" > $@
