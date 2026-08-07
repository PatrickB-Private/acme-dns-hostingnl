#!/usr/bin/env sh
#
# dns_hostingnl.sh
#
# Hosting.nl DNS API hook for acme.sh DNS-01 validation.
#
# Required:
#   HOSTINGNL_API_TOKEN
#       Hosting.nl API token with permission to manage DNS records.
#
# Optional:
#   HOSTINGNL_ZONE
#       Explicit DNS-zone override. When set, automatic zone detection
#       and domain-list pagination are skipped.
#
#   HOSTINGNL_TTL
#       TTL for temporary ACME TXT records. Default: 300 seconds.
#
#   HOSTINGNL_API_BASE
#       Hosting.nl API base URL.
#       Default: https://api.hosting.nl
#
#   HOSTINGNL_PAGE_SIZE
#       Number of domains requested per page during automatic zone
#       detection. Default: 100.
#
#   HOSTINGNL_DOMAIN_LIMIT
#       Deprecated compatibility alias for HOSTINGNL_PAGE_SIZE.
#
# The script uses helper functions supplied by acme.sh:
#   _get, _post, _info, _err and _debug
#
# No external JSON parser such as jq is required.

HOSTINGNL_API_BASE="${HOSTINGNL_API_BASE:-https://api.hosting.nl}"
HOSTINGNL_TTL="${HOSTINGNL_TTL:-300}"

# HOSTINGNL_DOMAIN_LIMIT was used by earlier versions of this hook.
# Keep it as a fallback so existing configurations continue to work.
HOSTINGNL_PAGE_SIZE="${HOSTINGNL_PAGE_SIZE:-${HOSTINGNL_DOMAIN_LIMIT:-100}}"

###############################################################################
# Public acme.sh hook functions
###############################################################################

dns_hostingnl_add() {
  fulldomain="$1"
  txtvalue="$2"

  _hostingnl_require_token || return 1
  _hostingnl_validate_ttl || return 1

  _info "Hosting.nl: adding DNS-01 TXT record"
  _info "Hosting.nl: record name: $fulldomain"

  zone="$(_hostingnl_get_zone "$fulldomain")" || return 1
  _info "Hosting.nl: DNS zone: $zone"

  # Hosting.nl expects TXT content itself to be enclosed in quotation marks.
  # The escaped quotes below therefore form part of the DNS record content.
  payload="[{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"\\\"$txtvalue\\\"\",\"ttl\":$HOSTINGNL_TTL,\"prio\":0}]"

  export _H1="API-TOKEN: $HOSTINGNL_API_TOKEN"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  _debug "Hosting.nl: submitting TXT-record creation request"

  if ! resp="$(
    _post "$payload" "$HOSTINGNL_API_BASE/domains/$zone/dns"
  )"; then
    unset _H1 _H2 _H3
    _err "Hosting.nl: transport failure while creating TXT record"
    return 1
  fi

  unset _H1 _H2 _H3

  _hostingnl_validate_response \
    "$resp" \
    "TXT-record creation" || return 1

  _debug "Hosting.nl: creation response: $resp"
  _info "Hosting.nl: API accepted TXT-record creation request"

  # Do not rely solely on the API response. Verify through the API that
  # the exact record now exists.
  if ! _hostingnl_verify_record_present \
    "$zone" "$fulldomain" "$txtvalue"; then
    _err "Hosting.nl: TXT record was not found after creation"
    return 1
  fi

  _info "Hosting.nl: TXT record created and verified"
  return 0
}

dns_hostingnl_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _hostingnl_require_token || return 1

  _info "Hosting.nl: removing DNS-01 TXT record"
  _info "Hosting.nl: record name: $fulldomain"

  zone="$(_hostingnl_get_zone "$fulldomain")" || return 1
  _info "Hosting.nl: DNS zone: $zone"

  zonejson="$(_hostingnl_get_zone_records "$zone")" || return 1

  rec_id="$(
    _hostingnl_find_record_id \
      "$zonejson" \
      "$fulldomain" \
      "$txtvalue"
  )"

  if [ -z "$rec_id" ]; then
    # Cleanup should be idempotent. If the record is already gone,
    # there is nothing left to do.
    _info "Hosting.nl: matching TXT record is already absent"
    return 0
  fi

  _debug "Hosting.nl: matching TXT record ID: $rec_id"

  delpayload="[{\"id\":$rec_id}]"

  export _H1="API-TOKEN: $HOSTINGNL_API_TOKEN"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  _debug "Hosting.nl: submitting TXT-record deletion request"

  if ! resp="$(
    _post \
      "$delpayload" \
      "$HOSTINGNL_API_BASE/domains/$zone/dns" \
      "" \
      "DELETE"
  )"; then
    unset _H1 _H2 _H3
    _err "Hosting.nl: transport failure while deleting TXT record $rec_id"
    return 1
  fi

  unset _H1 _H2 _H3

  _hostingnl_validate_response \
    "$resp" \
    "TXT-record deletion" || return 1

  _debug "Hosting.nl: deletion response: $resp"
  _info "Hosting.nl: API accepted TXT-record deletion request"

  if ! _hostingnl_verify_record_absent \
    "$zone" "$fulldomain" "$txtvalue"; then
    _err "Hosting.nl: TXT record still exists after deletion"
    return 1
  fi

  _info "Hosting.nl: TXT record removed and verified"
  return 0
}

###############################################################################
# Configuration validation
###############################################################################

_hostingnl_require_token() {
  # API_TOKEN is retained as a compatibility fallback for installations
  # using an earlier version of this hook.
  HOSTINGNL_API_TOKEN="${HOSTINGNL_API_TOKEN:-${API_TOKEN:-}}"

  if [ -z "$HOSTINGNL_API_TOKEN" ]; then
    _err "Hosting.nl: HOSTINGNL_API_TOKEN is not set"
    return 1
  fi

  return 0
}

_hostingnl_validate_ttl() {
  case "$HOSTINGNL_TTL" in
    ''|*[!0-9]*)
      _err "Hosting.nl: HOSTINGNL_TTL must be a positive integer"
      return 1
      ;;
    0)
      _err "Hosting.nl: HOSTINGNL_TTL must be greater than zero"
      return 1
      ;;
  esac

  return 0
}

_hostingnl_validate_page_size() {
  case "$HOSTINGNL_PAGE_SIZE" in
    ''|*[!0-9]*)
      _err "Hosting.nl: HOSTINGNL_PAGE_SIZE must be a positive integer"
      return 1
      ;;
    0)
      _err "Hosting.nl: HOSTINGNL_PAGE_SIZE must be greater than zero"
      return 1
      ;;
  esac

  return 0
}

###############################################################################
# DNS-zone detection
###############################################################################

_hostingnl_get_zone() {
  fulldomain="$1"

  # An explicitly configured zone always takes precedence. Apart from
  # providing a useful override, this avoids an unnecessary /domains call.
  if [ -n "${HOSTINGNL_ZONE:-}" ]; then
    _debug "Hosting.nl: using explicit zone override: $HOSTINGNL_ZONE"
    printf '%s' "$HOSTINGNL_ZONE"
    return 0
  fi

  _hostingnl_validate_page_size || return 1

  _debug "Hosting.nl: automatically detecting zone for $fulldomain"
  _debug "Hosting.nl: domain-list page size: $HOSTINGNL_PAGE_SIZE"

  offset=0
  page=1
  best_zone=""
  best_length=0
  total_seen=0

  while :; do
    _debug "Hosting.nl: requesting domain page $page (limit=$HOSTINGNL_PAGE_SIZE, offset=$offset)"

    export _H1="API-TOKEN: $HOSTINGNL_API_TOKEN"
    export _H2="Accept: application/json"

    if ! domains_json="$(
      _get "$HOSTINGNL_API_BASE/domains?limit=$HOSTINGNL_PAGE_SIZE&offset=$offset"
    )"; then
      unset _H1 _H2
      _err "Hosting.nl: unable to retrieve domain page $page"
      return 1
    fi

    unset _H1 _H2

    _hostingnl_validate_response \
      "$domains_json" \
      "domain-list retrieval (page $page)" || return 1

    _hostingnl_validate_data_array \
      "$domains_json" \
      "domain-list retrieval (page $page)" || return 1

    # Extract the domain values from the data array.
    #
    # DNS names cannot contain whitespace, so iterating over the extracted
    # names using the shell word list is safe here and avoids a subshell that
    # would otherwise prevent best_zone from being updated.
    page_domains="$(
      printf '%s' "$domains_json" |
        grep -o '"domain"[[:space:]]*:[[:space:]]*"[^"]*"' |
        sed 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    )"

    if [ -n "$page_domains" ]; then
      page_count="$(
        printf '%s\n' "$page_domains" |
          grep -c .
      )"
    else
      page_count=0
    fi

    total_seen=$((total_seen + page_count))

    _debug "Hosting.nl: page $page returned $page_count domain(s)"

    # Select the longest domain that is a suffix of the requested ACME
    # hostname. Choosing the longest match also handles delegated/nested
    # zones correctly.
    for candidate in $page_domains; do
      case ".$fulldomain" in
        *."$candidate")
          candidate_length="${#candidate}"

          _debug "Hosting.nl: matching zone candidate: $candidate"

          if [ "$candidate_length" -gt "$best_length" ]; then
            best_zone="$candidate"
            best_length="$candidate_length"
            _debug "Hosting.nl: current best zone match: $best_zone"
          fi
          ;;
      esac
    done

    # A short page means there are no further records. An empty first page
    # naturally terminates here as well.
    if [ "$page_count" -lt "$HOSTINGNL_PAGE_SIZE" ]; then
      _debug "Hosting.nl: reached final domain page"
      break
    fi

    offset=$((offset + HOSTINGNL_PAGE_SIZE))
    page=$((page + 1))
  done

  _debug "Hosting.nl: examined $total_seen domain(s) across $page page(s)"

  if [ -z "$best_zone" ]; then
    _err "Hosting.nl: no matching DNS zone found for $fulldomain"
    _err "Hosting.nl: examined $total_seen domain(s)"
    _err "Hosting.nl: set HOSTINGNL_ZONE explicitly if the zone is not listed by GET /domains"
    return 1
  fi

  _debug "Hosting.nl: automatically detected zone: $best_zone"
  printf '%s' "$best_zone"
}

###############################################################################
# DNS-record retrieval and lookup
###############################################################################

_hostingnl_get_zone_records() {
  zone="$1"

  export _H1="API-TOKEN: $HOSTINGNL_API_TOKEN"
  export _H2="Accept: application/json"

  _debug "Hosting.nl: retrieving DNS records for zone $zone"

  if ! zonejson="$(
    _get "$HOSTINGNL_API_BASE/domains/$zone/dns"
  )"; then
    unset _H1 _H2
    _err "Hosting.nl: unable to retrieve DNS records for zone $zone"
    return 1
  fi

  unset _H1 _H2

  _hostingnl_validate_response \
    "$zonejson" \
    "DNS-record retrieval" || return 1

  _hostingnl_validate_data_array \
    "$zonejson" \
    "DNS-record retrieval" || return 1

  printf '%s' "$zonejson"
}

_hostingnl_find_record_id() {
  zonejson="$1"
  fulldomain="$2"
  txtvalue="$3"

  # Hosting.nl returns the TXT content including its DNS-level quotes.
  # Fixed-string matching avoids treating dots or other hostname characters
  # as regular-expression syntax.
  name_fragment="\"name\":\"$fulldomain\""
  type_fragment='"type":"TXT"'
  content_fragment="\"content\":\"\\\"$txtvalue\\\"\""

  printf '%s' "$zonejson" |
    tr '\r\n' '  ' |
    sed 's/}[[:space:]]*,[[:space:]]*{/}\
{/g' |
    grep -F "$name_fragment" |
    grep -F "$type_fragment" |
    grep -F "$content_fragment" |
    sed -n \
      's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
    head -n 1
}

_hostingnl_record_exists() {
  zonejson="$1"
  fulldomain="$2"
  txtvalue="$3"

  rec_id="$(
    _hostingnl_find_record_id \
      "$zonejson" \
      "$fulldomain" \
      "$txtvalue"
  )"

  [ -n "$rec_id" ]
}

###############################################################################
# Post-operation verification
###############################################################################

_hostingnl_verify_record_present() {
  zone="$1"
  fulldomain="$2"
  txtvalue="$3"

  _debug "Hosting.nl: verifying TXT-record creation"

  zonejson="$(_hostingnl_get_zone_records "$zone")" || return 1

  if ! _hostingnl_record_exists \
    "$zonejson" "$fulldomain" "$txtvalue"; then
    return 1
  fi

  _debug "Hosting.nl: TXT record is present in API response"
  return 0
}

_hostingnl_verify_record_absent() {
  zone="$1"
  fulldomain="$2"
  txtvalue="$3"

  _debug "Hosting.nl: verifying TXT-record deletion"

  zonejson="$(_hostingnl_get_zone_records "$zone")" || return 1

  if _hostingnl_record_exists \
    "$zonejson" "$fulldomain" "$txtvalue"; then
    return 1
  fi

  _debug "Hosting.nl: TXT record is absent from API response"
  return 0
}

###############################################################################
# Generic API-response validation
###############################################################################

_hostingnl_validate_response() {
  response="$1"
  operation="$2"

  if [ -z "$response" ]; then
    _err "Hosting.nl: empty API response during $operation"
    return 1
  fi

  # Basic sanity check: the API response must at least look like a JSON
  # object or array. Full JSON parsing is intentionally avoided to keep
  # the hook dependency-free.
  case "$response" in
    \{*\}|\[*\])
      ;;
    *)
      _err "Hosting.nl: malformed or unexpected API response during $operation"
      _debug "Hosting.nl: response body: $response"
      return 1
      ;;
  esac

  # Detect the explicit failure envelope used by Hosting.nl.
  if printf '%s' "$response" |
    grep -Eq '"success"[[:space:]]*:[[:space:]]*false'; then
    _err "Hosting.nl: API reported failure during $operation"
    _err "Hosting.nl: response: $response"
    return 1
  fi

  # Also catch API responses containing explicit error/error(s) members.
  if printf '%s' "$response" |
    grep -Eq '"errors?"[[:space:]]*:'; then
    _err "Hosting.nl: API returned an error during $operation"
    _err "Hosting.nl: response: $response"
    return 1
  fi

  return 0
}

_hostingnl_validate_data_array() {
  response="$1"
  operation="$2"

  # GET /domains and GET /domains/{zone}/dns are expected to return their
  # records in a top-level "data" array.
  if ! printf '%s' "$response" |
    grep -Eq '"data"[[:space:]]*:[[:space:]]*\['; then
    _err "Hosting.nl: response during $operation contains no data array"
    _debug "Hosting.nl: response body: $response"
    return 1
  fi

  return 0
}
