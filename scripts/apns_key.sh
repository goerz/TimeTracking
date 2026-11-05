#!/bin/sh
# `make apns-key`: stores the team's APNs auth key in the login Keychain
# (architecture.md §2.4, ARCH-9, ARCH-10).
#
#   scripts/apns_key.sh <P8 file> <KEY_ID or ""> <TEAM> <BUNDLE_ID> <app path> [<keychain>]
#
# One generic-password item: service <BUNDLE_ID>.apns, account the key id,
# secret {"keyID": ..., "teamID": ..., "p8": <file contents>}. An existing item
# of that service is replaced. The key is never printed.
set -eu

p8="$1"
key_id="$2"
team="$3"
bundle_id="$4"
app="$5"
keychain="${6:-}"
service="$bundle_id.apns"

die() {
    echo "apns-key: $*" >&2
    exit 1
}

[ -n "$p8" ] || die "usage: make apns-key P8=<path>/AuthKey_<KEYID>.p8 [KEY_ID=<id>]"
[ -f "$p8" ] || die "no such file: $p8"
[ -n "$team" ] || die "set TEAM in local.mk"
if [ -z "$key_id" ]; then
    key_id=$(basename "$p8" | sed -n 's/^AuthKey_\([A-Z0-9]\{10\}\)\.p8$/\1/p')
    [ -n "$key_id" ] || die "cannot read the key id from the file name; pass KEY_ID=<id>"
fi
printf '%s' "$key_id" | grep -Eq '^[A-Z0-9]{10}$' || die "the key id must be 10 upper-case letters or digits"

# A PEM PKCS#8 private key on the P-256 curve, and nothing else.
head -n 1 "$p8" | grep -q '^-----BEGIN PRIVATE KEY-----' || die "$p8 is not a PEM private key"
grep -Eqv '^(-----(BEGIN|END) PRIVATE KEY-----|[A-Za-z0-9+/=]+|)$' "$p8" && die "$p8 contains text besides a PEM private key"
curve=$(openssl pkey -in "$p8" -noout -text 2>/dev/null | sed -n 's/^ASN1 OID: //p')
[ "$curve" = prime256v1 ] || die "$p8 is not a P-256 key"

# JSON-escape the PEM, which holds only base64, dashes, spaces, and
# newlines, keeping the file's content exactly (with or without a final
# newline).
pem=$(awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }' "$p8")
[ -n "$(tail -c 1 "$p8")" ] || pem="$pem\\n"
secret=$(printf '{"keyID": "%s", "teamID": "%s", "p8": "%s"}' "$key_id" "$team" "$pem")

set --
[ -z "$keychain" ] || set -- "$keychain"
while security find-generic-password -s "$service" "$@" >/dev/null 2>&1; do
    security delete-generic-password -s "$service" "$@" >/dev/null
done
if [ -d "$app" ]; then
    access="-T $app"
else
    access=""
    echo "apns-key: $app is not installed; run make install, then make apns-key again so the app can read the key without a prompt" >&2
fi
# shellcheck disable=SC2086
security add-generic-password -s "$service" -a "$key_id" -l "$service" -X "$(printf '%s' "$secret" | xxd -p | tr -d '\n')" $access "$@"
echo "apns-key: stored key $key_id for team $team as Keychain item $service"
