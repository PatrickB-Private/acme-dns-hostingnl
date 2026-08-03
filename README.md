# acme-sh-dns-hostingnl

DNS API hook for Hosting.nl that enables automatic Let's Encrypt (ACME) DNS-01 certificate issuance and renewal with **acme.sh**.

## Features

* Automatic DNS-01 validation using the Hosting.nl DNS API.
* Automatic certificate issuance.
* Automatic certificate renewal.
* Compatible with any platform supported by acme.sh.
* Tested on TrueNAS SCALE.

## Requirements

* A Hosting.nl account.
* A domain managed by Hosting.nl.
* A Hosting.nl API token with permission to manage DNS records.
* An existing installation of acme.sh.

## Installation

Copy the hook into the acme.sh DNS API directory:

```bash
cp dns_hostingnl.sh ~/.acme.sh/dnsapi/
chmod 700 ~/.acme.sh/dnsapi/dns_hostingnl.sh
```

or, if using a custom ACME_HOME:

```bash
cp dns_hostingnl.sh <ACME_HOME>/dnsapi/
chmod 700 <ACME_HOME>/dnsapi/dns_hostingnl.sh
```

## Configuration

Create a Hosting.nl API token in the Hosting.nl control panel.

Export the token before running acme.sh:

```bash
export HOSTINGNL_API_TOKEN="your-api-token"
```

Optionally, specify the DNS zone explicitly:

```bash
export HOSTINGNL_ZONE="example.nl"
```

If `HOSTINGNL_ZONE` is omitted, the hook will attempt to determine the correct zone automatically (if supported by the installed version).

## Issue a certificate

```bash
acme.sh --issue \
    -d truenas.example.nl \
    --dns dns_hostingnl
```

## Renew a certificate

```bash
acme.sh --renew \
    -d truenas.example.nl
```

or simply run the standard acme.sh cron job:

```bash
acme.sh --cron
```

## Installing the certificate

This hook only performs DNS validation.

Certificate installation remains the responsibility of acme.sh using the normal `--install-cert` command appropriate for your system.

## Notes

Hosting.nl requires TXT record contents to be submitted as quoted strings. The hook automatically performs this conversion.

## Troubleshooting

### TXT record never appears

Verify:

* `HOSTINGNL_API_TOKEN` is set.
* The API token has permission to edit DNS.
* The domain is managed by Hosting.nl.
* No wildcard CNAME masks the `_acme-challenge` record.

### View DNS propagation

```bash
dig +short TXT _acme-challenge.example.nl
```

or

```bash
dig @1.1.1.1 TXT _acme-challenge.example.nl
```

### Enable debugging

```bash
acme.sh --issue \
    -d truenas.example.nl \
    --dns dns_hostingnl \
    --debug 2
```

## Compatibility

Tested with:

* acme.sh
* Let's Encrypt
* TrueNAS SCALE

The hook contains no TrueNAS-specific code and should work on any platform supported by acme.sh.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0), matching the license of acme.sh.

## Contributing

Bug reports, feature requests and pull requests are welcome.

## Acknowledgements

Thanks to the acme.sh project for providing an extensible framework for DNS API integrations.
