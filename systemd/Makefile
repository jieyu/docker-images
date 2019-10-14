ifeq ($(origin VERSION), undefined)
VERSION := $(shell git describe --tags --always)
endif

IMG_REPO ?= jieyu
IMG_TAG ?= $(VERSION)

all: build

build:
	docker build -t $(IMG_REPO)/systemd:$(IMG_TAG) .

push:
	docker push $(IMG_REPO)/systemd:$(IMG_TAG)
