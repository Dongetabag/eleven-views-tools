#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Configure the single-company Desk bridge credential without exposing the
# bearer token in shell history, process arguments, or a plaintext config file.

set -euo pipefail

service="io.elevenviews.tools.desk-bridge"
label="Eleven Views Desk bridge"
action="${1:-configure}"

case "$action" in
  configure)
    read -r -p "Desk company UUID: " company_id
    if [[ ! "$company_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
      echo "Invalid Desk company UUID." >&2
      exit 2
    fi

    # One active company credential is supported in bridge v1. Remove a prior
    # account so SecItemCopyMatching cannot return an ambiguous item.
    security delete-generic-password -s "$service" >/dev/null 2>&1 || true
    echo "Enter the scoped Desk bridge token in the macOS Keychain prompt."
    security add-generic-password \
      -a "$company_id" \
      -s "$service" \
      -l "$label" \
      -w
    echo "Desk bridge credential saved in macOS Keychain."
    ;;
  remove)
    if security delete-generic-password -s "$service" >/dev/null 2>&1; then
      echo "Desk bridge credential removed from macOS Keychain."
    else
      echo "No Desk bridge credential was configured."
    fi
    ;;
  *)
    echo "Usage: $0 [configure|remove]" >&2
    exit 2
    ;;
esac
