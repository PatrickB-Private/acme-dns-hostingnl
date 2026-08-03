#!/usr/bin/env sh
#
# dns_hostingnl.sh
#
# Hosting.nl DNS API hook for acme.sh DNS-01 validation.
#
# Required:
#   HOSTINGNL_API_TOKEN
#
# Optional:
#   HOSTINGNL_ZONE
#       Explicit DNS-zone override.
#
#   HOSTINGNL_TTL
#       Challenge-record TTL. Default: 300.
#
#   HOSTINGNL_API_BASE
#       Hosting.nl API base URL.
#
#   HOSTINGNL_DOMAIN_LIMIT
#       Maximum number of domains requested during automatic zone detection.
#       Default: 100.
#
# The script uses helper functions supplied by acme.sh:
#   _get, _post, _info, _err and _debug

HOSTINGNL_API_BASE="${HOSTINGNL_API_BASE:-https://api.hosting.nl}"
HOSTINGNL_TTL="${HOSTINGNL_TTL:-300}"
HOSTINGNL_DOMAIN_LIMIT="${HOSTINGNL_DOMAIN_LIMIT:-100}"

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

  # Hosting.nl requires TXT content to include DNS-level quotation marks.
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

  _hostingnl_validate_response "$resp" "TXT-record creation" || return 1

  _debug "Hosting.nl: creation response: $resp"
  _info "Hosting.nl: API accepted TXT-record creation request"

  if ! _hostingnl_verify_record_present "$zone" "$fulldomain" "$txtvalue"; then
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

  _hostingnl_validate_response "$resp" "TXT-record deletion" || return 1

  _debug "Hosting.nl: deletion response: $resp"
  _info "Hosting.nl: API accepted TXT-record deletion request"

  if ! _hostingnl_verify_record_absent "$zone" "$fulldomain" "$txtvalue"; then
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
  # API_TOKEN is retained as a compatibility fallback.
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

_hostingnl_validate_domain_limit() {
  case "$HOSTINGNL_DOMAIN_LIMIT" in
    ''|*[!0-9]*)
      _err "Hosting.nl: HOSTINGNL_DOMAIN_LIMIT must be a positive integer"
      return 1
      ;;
    0)
      _err "Hosting.nl: HOSTINGNL_DOMAIN_LIMIT must be greater than zero"
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

  if [ -n "${HOSTINGNL_ZONE:-}" ]; then
    _debug "Hosting.nl: using explicit zone override: $HOSTINGNL_ZONE"
    printf '%s' "$HOSTINGNL_ZONE"
    return 0
  fi

  _hostingnl_validate_domain_limit || return 1

  _debug "Hosting.nl: detecting zone for $fulldomain"
  _debug "Hosting.nl: requesting up to $HOSTINGNL_DOMAIN_LIMIT domains"

  export _H1="API-TOKEN: $HOSTINGNL_API_TOKEN"
  export _H2="Accept: application/json"

  if ! domains_json="$(
    _get "$HOSTINGNL_API_BASE/domains?limit=$HOSTINGNL_DOMAIN_LIMIT"
  )"; then
    unset _H1 _H2
    _err "Hosting.nl: unable to retrieve domains for automatic zone detection"
    return 1
  fi

  unset _H1 _H2

  _hostingnl_validate_response \
    "$domains_json" \
    "domain-list retrieval" || return 1

  _hostingnl_validate_data_array \
    "$domains_json" \
    "domain-list retrieval" || return 1

  zone="$(
    printf '%s' "$domains_json" |
      grep -o '"domain"[[:space:]]*:[[:space:]]*"[^"]*"' |
      sed 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' |
      while IFS= read -r candidate; do
        case ".$fulldomain" in
          *."$candidate")
            printf '%s\t%s\n' "${#candidate}" "$candidate"
            ;;
        esac
      done |
      sort -rn |
      head -n 1 |
      cut -f2-
  )"

  if [ -z "$zone" ]; then
    _err "Hosting.nl: no matching DNS zone found for $fulldomain"
    _err "Hosting.nl: set HOSTINGNL_ZONE explicitly if necessary"
    return 1
  fi

  _debug "Hosting.nl: automatically detected zone: $zone"
  printf '%s' "$zone"
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

  # Hosting.nl returns compact JSON containing the quoted TXT value.
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

  if ! _hostingnl_record_exists "$zonejson" "$fulldomain" "$txtvalue"; then
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

  if _hostingnl_record_exists "$zonejson" "$fulldomain" "$txtvalue"; then
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

  # Require a JSON object or array as the outer response structure.
  case "$response" in
    \{*\}|\[*\])
      ;;
    *)
      _err "Hosting.nl: malformed or unexpected API response during $operation"
      _debug "Hosting.nl: response body: $response"
      return 1
      ;;
  esac

  if printf '%s' "$response" |
    grep -Eq '"success"[[:space:]]*:[[:space:]]*false'; then
    _err "Hosting.nl: API reported failure during $operation"
    _err "Hosting.nl: response: $response"
    return 1
  fi

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

  if ! printf '%s' "$response" |
    grep -Eq '"data"[[:space:]]*:[[:space:]]*\['; then
    _err "Hosting.nl: response during $operation contains no data array"
    _debug "Hosting.nl: response body: $response"
    return 1
  fi

  return 0
}
