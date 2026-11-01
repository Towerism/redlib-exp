IMAGE     := $(shell cat docker-image)
DOCKER    ?= docker
COOKIE    ?= .cookie
TEST_PORT ?= 18080

.PHONY: build test

# Download the Redlib image named in docker-image.
build:
	$(DOCKER) pull $(IMAGE)

# Check the cookie, then load a Reddit page through it in a throwaway container.
test:
	@sh scripts/check-cookie.sh $(COOKIE)
	@sh scripts/smoke-test.sh $(DOCKER) $(IMAGE) $(COOKIE) $(TEST_PORT)
