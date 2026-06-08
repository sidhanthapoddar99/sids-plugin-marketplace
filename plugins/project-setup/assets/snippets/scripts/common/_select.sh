#!/usr/bin/env bash
# scripts/common/_select.sh — dependency-free terminal selector widget. SOURCE this; call tui_select.
#
# A small, reusable picker (no fzf/gum). Single-select, multi-select, and a horizontal
# action row, with arrow-key nav, [x]/[ ] checkboxes, and an automatic numbered-prompt
# fallback when there's no usable TTY (CI / pipes). It carries ZERO project knowledge —
# copy this file verbatim into any bash control plane.
#
#   tui_select --into VAR [--multi|--horizontal] --header "T" [--hint "T"] [--preselect "a,b"] -- opt…
#
#   Fills the caller array VAR with the selection (nameref). Returns:
#     0 = confirmed   ·   1 = cancelled (Esc/q/EOF)   ·   2 = misuse
#   All UI is drawn to /dev/tty, so it composes with `$(…)`/pipes around the caller.
#
#   Keys — single:     ↑/↓ (or k/j) move · Enter select · Esc/q cancel
#          multi:      ↑/↓ move · Tab or Space toggle · Enter confirm (may be empty) · Esc cancel
#          horizontal: ←/→ (or h/l) move · Enter select · Esc cancel
#
# Requires bash 4.3+ (namerefs). macOS system bash is 3.2 — use mise's bash (mise pins it).
# All arithmetic uses x=$((x+1)) form, never ((x++)), so it's safe under `set -euo pipefail`.

# Standalone color defaults — no-ops if _lib.sh already set them (incl. its NO_COLOR/TTY logic).
: "${C_RESET:=$'\033[0m'}"; : "${C_DIM:=$'\033[2m'}"; : "${C_B:=$'\033[1m'}"
: "${C_GRN:=$'\033[32m'}"; : "${C_CYN:=$'\033[36m'}"

tui_select() {
  local multi=0 horizontal=0 header="" hint="" preselect="" varname=""
  while [[ $# -gt 0 ]]; do case "$1" in
    --multi)      multi=1; shift ;;
    --horizontal) horizontal=1; shift ;;
    --into)       varname="$2"; shift 2 ;;
    --header)     header="$2"; shift 2 ;;
    --hint)       hint="$2"; shift 2 ;;
    --preselect)  preselect="$2"; shift 2 ;;
    --)           shift; break ;;
    *)            break ;;
  esac; done
  [[ -n $varname ]] || { printf 'tui_select: --into VAR required\n' >&2; return 2; }
  local -n __out="$varname"; __out=()
  local opts=("$@") n=$#
  (( n )) || return 1
  if [[ -z $hint ]]; then
    if   (( horizontal )); then hint="←/→ move · Enter select · Esc cancel"
    elif (( multi ));      then hint="↑/↓ move · Tab/Space toggle · Enter confirm · Esc cancel"
    else                        hint="↑/↓ move · Enter select · Esc cancel"; fi
  fi

  # ── fallback: no usable terminal → numbered prompt (same result contract) ──
  if [[ ! -t 1 || ! -r /dev/tty || "${TERM:-dumb}" == dumb ]]; then
    { [[ -n $header ]] && printf '%s\n' "$header"
      local i; for ((i=0;i<n;i=i+1)); do printf '  %2d) %s\n' "$((i+1))" "${opts[i]}"; done; } >&2
    local line t
    if (( multi )); then
      printf 'numbers (e.g. 1,3 — empty=none): ' >&2; read -r line || return 1
      for t in ${line//,/ }; do [[ $t =~ ^[0-9]+$ ]] && (( t>=1 && t<=n )) && __out+=("${opts[t-1]}"); done
      return 0
    fi
    printf 'number: ' >&2; read -r line || return 1
    [[ $line =~ ^[0-9]+$ ]] && (( line>=1 && line<=n )) && { __out=("${opts[line-1]}"); return 0; }
    return 1
  fi

  # ── interactive ──
  local -a marked=(); local i
  for ((i=0;i<n;i=i+1)); do marked[i]=0; done
  if [[ -n $preselect ]]; then
    local IFS=',' tok
    for tok in $preselect; do for ((i=0;i<n;i=i+1)); do [[ "${opts[i]}" == "$tok" ]] && marked[i]=1; done; done
  fi

  local saved cur=0 drawn=0 key rest rc=0
  saved=$(stty -g < /dev/tty 2>/dev/null || true)
  _tui_restore() { [[ -n $saved ]] && stty "$saved" < /dev/tty 2>/dev/null; printf '\033[?25h' > /dev/tty 2>/dev/null || true; }
  trap '_tui_restore' EXIT INT TERM
  stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null || true
  printf '\033[?25l' > /dev/tty 2>/dev/null || true

  while true; do
    # ── draw (redraw in place) ──
    (( drawn > 0 )) && printf '\033[%dA' "$drawn" > /dev/tty
    local lines=0 j cell
    if [[ -n $header ]]; then printf '\033[2K  %s%s%s\n' "$C_B" "$header" "$C_RESET" > /dev/tty; lines=$((lines+1)); fi
    if (( horizontal )); then
      printf '\033[2K  ' > /dev/tty
      for ((j=0;j<n;j=j+1)); do
        if (( j==cur )); then printf '%s❯ %s%s    ' "$C_CYN" "${opts[j]}" "$C_RESET" > /dev/tty
        else                  printf '  %s    ' "${opts[j]}" > /dev/tty; fi
      done
      printf '\n' > /dev/tty; lines=$((lines+1))
    else
      for ((j=0;j<n;j=j+1)); do
        cell=""
        if (( j==cur )); then cell+="${C_CYN}❯ ${C_RESET}"; else cell+="  "; fi
        if (( multi )); then
          if (( marked[j] )); then cell+="${C_GRN}[x]${C_RESET} "; else cell+="${C_DIM}[ ]${C_RESET} "; fi
        fi
        if (( j==cur )); then cell+="${C_B}${opts[j]}${C_RESET}"; else cell+="${opts[j]}"; fi
        printf '\033[2K%s\n' "$cell" > /dev/tty; lines=$((lines+1))
      done
    fi
    printf '\033[2K  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" > /dev/tty; lines=$((lines+1))
    drawn=$lines

    # ── read one key ──
    IFS= read -rsn1 key < /dev/tty || { rc=1; break; }
    if [[ $key == $'\e' ]]; then
      rest=""; read -rsn2 -t 0.05 rest < /dev/tty 2>/dev/null || true
      case "$rest" in
        '[A') (( horizontal )) || { if (( cur>0 )); then cur=$((cur-1)); else cur=$((n-1)); fi; } ;;  # up
        '[B') (( horizontal )) || { if (( cur<n-1 )); then cur=$((cur+1)); else cur=0; fi; } ;;       # down
        '[C') (( horizontal )) && { if (( cur<n-1 )); then cur=$((cur+1)); else cur=0; fi; } ;;       # right
        '[D') (( horizontal )) && { if (( cur>0 )); then cur=$((cur-1)); else cur=$((n-1)); fi; } ;;  # left
        '')   rc=1; break ;;                                                                          # bare Esc
      esac
    else
      case "$key" in
        k|K) (( horizontal )) || { if (( cur>0 )); then cur=$((cur-1)); else cur=$((n-1)); fi; } ;;
        j|J) (( horizontal )) || { if (( cur<n-1 )); then cur=$((cur+1)); else cur=0; fi; } ;;
        h|H) (( horizontal )) && { if (( cur>0 )); then cur=$((cur-1)); else cur=$((n-1)); fi; } ;;
        l|L) (( horizontal )) && { if (( cur<n-1 )); then cur=$((cur+1)); else cur=0; fi; } ;;
        q|Q) rc=1; break ;;
        $'\t'|' ') (( multi )) && marked[cur]=$(( marked[cur] ^ 1 )) ;;
        ''|$'\n'|$'\r')
          if (( multi )); then for ((i=0;i<n;i=i+1)); do (( marked[i] )) && __out+=("${opts[i]}"); done
          else __out=("${opts[cur]}"); fi
          rc=0; break ;;
      esac
    fi
  done

  _tui_restore; trap - EXIT INT TERM
  return $rc
}
