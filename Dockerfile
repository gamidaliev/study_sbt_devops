FROM golang:1.26.10-alpine3.23@sha256:0525c952defebc693cdaf62cdf43afa32be5a7f377e99260642ea19c240c708e AS builder

WORKDIR /src
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN GOPROXY=off go test ./... \
    && GOPROXY=off go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -o /out/app .

FROM alpine:3.23.7@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63 AS runtime

RUN addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app
WORKDIR /app
COPY --from=builder --chown=0:0 --chmod=0555 /out/app /app/app
ENV APP_PORT=8080
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=4s --start-period=10s --retries=3 \
    CMD ["/app/app", "healthcheck"]
ENTRYPOINT ["/app/app"]
