#!/bin/sh

# Force renewal of an existing certificate.

acme.sh --renew \
    -d host.domain.tld \
    --force
