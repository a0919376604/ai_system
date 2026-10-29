#!/usr/bin/env bash
# Shared by /run-plan model, /run-plan-model, and the launch block.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo 'Usage: model.sh [show|get|reset|MODEL]' >&2
  exit 2
fi
setting="${XDG_CONFIG_HOME:-$HOME/.config}/run-plan/model"
action="${1-show}"
valid_model() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.:/-]*$ ]]; }

case "$action" in
  show|get)
    model=''
    if [ -e "$setting" ]; then
      model=$(cat "$setting")
      if ! valid_model "$model"; then
        echo "Invalid run-plan model setting: $setting. Use /run-plan-model reset or set a model." >&2
        exit 2
      fi
    fi
    if [ "$action" = get ]; then
      [ -z "$model" ] || printf '%s\n' "$model"
    else
      printf 'run-plan model: %s\nsetting: %s\n' "${model:-inherit (Codex configuration)}" "$setting"
    fi
    ;;
  reset)
    rm -f -- "$setting"
    printf 'run-plan model: inherit (Codex configuration); applies to new runs.\n'
    ;;
  *)
    case "$action" in
      sol) model=gpt-6.1-sol ;;
      astra) model=gpt-6-astra ;;
      *) model="$action" ;;
    esac
    if ! valid_model "$model"; then
      echo 'Invalid model ID. Use sol, astra, a full model ID, or reset.' >&2
      exit 2
    fi
    mkdir -p "$(dirname "$setting")"
    pending=$(mktemp "${setting}.tmp.XXXXXX")
    trap 'rm -f -- "$pending"' EXIT
    printf '%s\n' "$model" > "$pending"
    mv -f -- "$pending" "$setting"
    printf 'run-plan model: %s; applies to new runs.\nsetting: %s\n' "$model" "$setting"
    ;;
esac
