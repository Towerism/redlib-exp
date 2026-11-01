IMAGE     := $(strip $(shell cat docker-image 2>/dev/null))
DOCKER    ?= docker
COOKIE    ?= .cookie
TEST_PORT ?= 18080

ifeq ($(IMAGE),)
$(error docker-image is missing or empty; it must hold the image name, e.g. ghcr.io/nachtalb/redlib:latest)
endif

.PHONY: build test

# Download the Redlib image named in docker-image.
build:
	$(DOCKER) pull '$(IMAGE)'

# Check the cookie, then load a Reddit page through it in a throwaway container.
test:
	@sh scripts/check-cookie.sh '$(COOKIE)'
	@sh scripts/smoke-test.sh '$(DOCKER)' '$(IMAGE)' '$(COOKIE)' '$(TEST_PORT)'
