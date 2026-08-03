#!/bin/sh

# Issue a certificate using the Hosting.nl DNS API hook.

acme.sh --issue \
    -d host.domain.tld \
    --dns dns_hostingnl
