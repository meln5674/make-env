FROM docker.io/library/golang:1.21.5 AS build

WORKDIR /src/

COPY go.mod go.sum main.go Makefile.tpl Dockerfile.tpl ./

RUN go build -o make-env -a -tags netgo -ldflags '-w -extldflags "-static"'

FROM docker.io/library/ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl golang pipx

COPY --from=build /src/make-env /usr/bin/
