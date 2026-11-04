FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server python3 supervisor \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /root/.ssh \
    && chmod 0700 /root/.ssh \
    && printf '%s\n' 'PermitRootLogin prohibit-password' 'PasswordAuthentication no' \
       'KbdInteractiveAuthentication no' > /etc/ssh/sshd_config.d/lab.conf \
    && rm -f /etc/ssh/ssh_host_*
COPY docker/host/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/host/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod 0755 /usr/local/bin/entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
