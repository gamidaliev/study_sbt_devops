FROM golang:1.26.10-alpine3.23 AS builder
WORKDIR /src
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
COPY app/go.mod app/go.sum ./
RUN go mod download
COPY app/ ./
RUN go test ./... \
    && go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/app . \
    && tar -czf /out/app.tar.gz -C /out app

FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ansible-core openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /ansible
ENV ANSIBLE_CONFIG=/ansible/ansible.cfg
COPY ansible/ /ansible/
COPY --from=builder /out/app.tar.gz /artifacts/app.tar.gz
COPY docker/control/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod 0755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
