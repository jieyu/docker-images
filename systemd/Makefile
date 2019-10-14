ifeq ($(origin VERSION), undefined)
VERSION := $(shell git describe --tags --always)
endif

IMG_TAG ?= $(VERSION)

all: build

build:
	docker build -t systemd:$(IMG_TAG) .

push:
	docker push systemd:$(IMG_TAG)
