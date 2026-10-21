#!/usr/bin/env bash
set -euo pipefail

# Local vsftpd for FTP integration tests: plain FTP and explicit FTPS on one port, implicit FTPS on another.
# The certificate is self-signed, so the tests also cover the certificate trust flow.
MODE="${1:-start}"
NAME="driftline-ftp-test"
IMAGE="driftline-ftp-test:local"
FTP_PORT="${DRIFTLINE_TEST_FTP_PORT:-2121}"
# Driftline picks implicit TLS for port 990 only, so the implicit server is published on 990.
FTPS_IMPLICIT_PORT="${DRIFTLINE_TEST_FTPS_IMPLICIT_PORT:-990}"
PASSWORD="${DRIFTLINE_TEST_PASSWORD:-}"

case "$MODE" in
  start)
    command -v docker >/dev/null || {
      echo "Docker is required for the integration FTP server." >&2
      exit 2
    }
    [[ -n "$PASSWORD" ]] || {
      echo "Set DRIFTLINE_TEST_PASSWORD for the FTP test user." >&2
      exit 2
    }
    docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE'
FROM alpine:3.20
RUN apk add --no-cache vsftpd openssl \
 && openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=driftline-ftp-test" \
      -keyout /etc/ssl/private/vsftpd.key -out /etc/ssl/certs/vsftpd.crt \
 && adduser -D -h /home/driftline driftline \
 && printf '%s\n' \
      listen=YES anonymous_enable=NO local_enable=YES write_enable=YES local_umask=022 \
      chroot_local_user=YES allow_writeable_chroot=YES seccomp_sandbox=NO \
      pasv_enable=YES pasv_min_port=30000 pasv_max_port=30009 pasv_address=127.0.0.1 \
      rsa_cert_file=/etc/ssl/certs/vsftpd.crt rsa_private_key_file=/etc/ssl/private/vsftpd.key \
      ssl_enable=YES force_local_logins_ssl=NO force_local_data_ssl=NO \
      > /etc/vsftpd/explicit.conf \
 && sed -e 's/pasv_min_port=30000/pasv_min_port=30010/' -e 's/pasv_max_port=30009/pasv_max_port=30019/' \
      /etc/vsftpd/explicit.conf > /etc/vsftpd/implicit.conf \
 && printf '%s\n' listen_port=990 implicit_ssl=YES force_local_logins_ssl=YES force_local_data_ssl=YES >> /etc/vsftpd/implicit.conf
# Restart loops keep the container up if one vsftpd process exits.
CMD echo "driftline:$FTP_PASSWORD" | chpasswd \
 && (while true; do vsftpd /etc/vsftpd/implicit.conf; sleep 1; done &) \
 && while true; do vsftpd /etc/vsftpd/explicit.conf; sleep 1; done
DOCKERFILE
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" \
      -p "$FTP_PORT:21" -p "$FTPS_IMPLICIT_PORT:990" -p 30000-30019:30000-30019 \
      -e FTP_PASSWORD="$PASSWORD" \
      "$IMAGE" >/dev/null
    echo "Started $NAME: FTP and explicit FTPS on $FTP_PORT, implicit FTPS on $FTPS_IMPLICIT_PORT"
    echo "Export:"
    echo "  export DRIFTLINE_INTEGRATION_FTP=1"
    echo "  export DRIFTLINE_TEST_FTP_PORT=$FTP_PORT"
    echo "  export DRIFTLINE_TEST_FTPS_IMPLICIT_PORT=$FTPS_IMPLICIT_PORT"
    ;;
  stop)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    echo "Stopped $NAME"
    ;;
  *)
    echo "usage: $0 [start|stop]" >&2
    exit 2
    ;;
esac
