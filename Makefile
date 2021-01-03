JULIA_VER := 1.5.3
BUILD_DIR := $(shell pwd)/build
APP_DIR := $(shell pwd)/julia-$(JULIA_VER)
JULIA_DEPOT_PATH := $(APP_DIR)/depot
JULIA := $(APP_DIR)/bin/julia
TMPDIR := $(APP_DIR)/tmp
USER := $(shell id -u -n)
HOME := $(APP_DIR)/home

export JULIA_VER BUILD_DIR JULIA_DEPOT_PATH APP_DIR USER TMPDIR HOME

default: julia-$(JULIA_VER)/bin/julia

$(BUILD_DIR) $(JULIA_DEPOT_PATH) $(TMPDIR) $(HOME):
	-mkdir -p $@

MAJMIN := $(patsubst %$(suffix $(JULIA_VER)),%,$(JULIA_VER))
$(JULIA):
	-rm -rf $(APP_DIR)
	-mkdir -p $(APP_DIR)
	-curl -# -L https://julialang-s3.julialang.org/bin/mac/x64/$(MAJMIN)/julia-$(JULIA_VER)-mac64.tar.gz | tar -zx --strip-components=1 -C julia-$(JULIA_VER)

test-%: $(JULIA) | $(JULIA_DEPOT_PATH) $(TMPDIR)
	$(JULIA) -e 'Base.runtests(["$*"])'

$(BUILD_DIR)/%.sb: %.sb.template | $(BUILD_DIR)
	envsubst < $< > $@

sandbox-%: $(JULIA) $(BUILD_DIR)/julia_tests.sb | $(JULIA_DEPOT_PATH) $(TMPDIR) $(HOME)
	sandbox-exec -f $(BUILD_DIR)/julia_tests.sb $(JULIA) -e 'Base.runtests(["$*"])'

trace-%: $(JULIA) $(BUILD_DIR)/trace.sb | $(JULIA_DEPOT_PATH) $(TMPDIR) $(HOME)
	sandbox-exec -f $(BUILD_DIR)/trace.sb $(JULIA) -e 'Base.runtests(["$*"])'

print-%:
	@echo '$*=$($*)'