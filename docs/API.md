# Hosting.nl DNS API implementation

This document describes the internal design of `dns_hostingnl.sh` and is intended for maintainers and contributors.

User installation and usage instructions are described in the project README.

---

# Overview

The hook implements the standard acme.sh DNS API interface for the Hosting.nl DNS service.

The implementation consists of two public entry points:

* `dns_hostingnl_add()`
* `dns_hostingnl_rm()`

These functions are invoked automatically by acme.sh during certificate issuance and renewal.

---

# DNS record creation

When acme.sh requests creation of an ACME challenge record, the hook:

1. determines the appropriate DNS zone;
2. constructs the JSON payload;
3. submits the request to the Hosting.nl API;
4. validates the API response;
5. reports success or failure to acme.sh.

The hook performs no DNS propagation checks itself; these are handled by acme.sh.

---

# DNS record removal

After successful validation, acme.sh requests removal of the challenge record.

The hook:

1. retrieves the DNS records for the selected zone;
2. locates the matching TXT record;
3. retrieves its record identifier;
4. requests deletion through the Hosting.nl API.

---

# Zone selection

The preferred DNS zone is determined as follows:

1. If `HOSTINGNL_ZONE` is defined, that value is used.
2. Otherwise, the hook attempts automatic zone detection (if supported by the installed version).

Using an explicit zone avoids ambiguity for accounts managing multiple domains or delegated subdomains.

---

# TXT record formatting

Hosting.nl requires TXT record contents to be submitted as quoted strings.

The hook therefore converts the ACME challenge value into the format expected by the API before submitting the request.

This behaviour is internal to the hook and requires no user configuration.

---

# acme.sh integration

The hook follows the standard acme.sh DNS API plugin conventions and relies on helper functions supplied by acme.sh, including:

* `_get`
* `_post`
* `_info`
* `_err`

HTTP request headers are supplied using the acme.sh header variables (`_H1`, `_H2`, `_H3`).

---

# Error handling

The hook validates both transport-level and application-level success.

A successful HTTP transaction does not necessarily indicate that the requested DNS operation succeeded.

The implementation therefore inspects API responses for reported errors before returning success to acme.sh.

---

# Design goals

The implementation aims to:

* follow the acme.sh DNS hook conventions;
* remain portable by using POSIX shell only;
* minimise external dependencies;
* provide deterministic behaviour;
* produce useful diagnostic messages;
* keep Hosting.nl-specific behaviour isolated from the acme.sh interface.

---

# Future development

Potential future enhancements include:

* improved automatic zone detection;
* additional API response validation;
* automated regression tests;
* contribution of the hook to the official acme.sh project.
