#!/usr/bin/env bash
# Back/forward navigation across visited tmux windows (browser-style).
# Bound to `prefix b` (back) and `prefix f` (forward); `push` is called by tmux
# hooks (after-select-window, client-session-changed) to record the trail.
#
# State lives in global tmux options (portable, survives across clients):
#   @ai_hist     - space-separated trail of window_ids (@N), oldest -> newest
#   @ai_hist_idx - 0-based cursor into the trail (the window you're "on")
#   @ai_hist_nav - '1' while a back/forward jump is in progress, so the push
#                  triggered by that jump is skipped (keeps the trail clean)
#
# Uses awk for list math and positional/here-strings only (no bash arrays), so
# it works on macOS's stock bash 3.2.
set -uo pipefail

MAX=50
cmd="${1:-push}"

get()  { tmux show-option -gqv "$1" 2>/dev/null; }
setg() { tmux set-option -g "$1" "$2" 2>/dev/null; }
win_alive() { tmux display-message -p -t "$1" '#{window_id}' >/dev/null 2>&1; }
nth() { awk -v i="$1" '{print $i}' <<<"$2"; }   # 1-based token from a string

trail="$(get @ai_hist)"
idx="$(get @ai_hist_idx)"; idx="${idx:-0}"

case "$cmd" in
  push)
    # Ignore the push caused by our own back/forward jump.
    if [ "$(get @ai_hist_nav)" = "1" ]; then setg @ai_hist_nav 0; exit 0; fi
    cur="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
    [ -z "$cur" ] && exit 0
    result="$(awk -v trail="$trail" -v idx="$idx" -v cur="$cur" -v max="$MAX" 'BEGIN{
      n=split(trail,a," ");
      ci=idx+1;                                   # 1-based cursor
      if (n>0 && ci>=1 && ci<=n && a[ci]==cur){ printf "%d\t%s", idx, trail; exit }
      keep=ci; if(keep>n)keep=n; if(keep<0)keep=0;
      out="";
      for(i=1;i<=keep;i++) out=(out==""?a[i]:out" "a[i]);   # drop forward history
      out=(out==""?cur:out" "cur);                          # append current
      m=split(out,b," ");
      if(m>max){ start=m-max+1; out=""; for(i=start;i<=m;i++) out=(out==""?b[i]:out" "b[i]); m=max; }
      printf "%d\t%s", m-1, out;
    }')"
    setg @ai_hist_idx "${result%%$'\t'*}"
    setg @ai_hist     "${result#*$'\t'}"
    ;;
  back)
    n="$(awk '{print NF}' <<<"$trail")"; n="${n:-0}"
    [ "$n" -eq 0 ] && exit 0
    k=$((idx-1))
    while [ "$k" -ge 0 ]; do
      w="$(nth $((k+1)) "$trail")"
      if [ -n "$w" ] && win_alive "$w"; then
        setg @ai_hist_nav 1
        setg @ai_hist_idx "$k"
        sess="$(tmux display-message -p -t "$w" '#{session_name}' 2>/dev/null || true)"
        [ -n "$sess" ] && tmux switch-client -t "$sess" 2>/dev/null || true
        tmux select-window -t "$w" 2>/dev/null || true
        exit 0
      fi
      k=$((k-1))
    done
    tmux display-message 'Historial: no hay más atrás'
    ;;
  forward)
    n="$(awk '{print NF}' <<<"$trail")"; n="${n:-0}"
    [ "$n" -eq 0 ] && exit 0
    k=$((idx+1))
    while [ "$k" -lt "$n" ]; do
      w="$(nth $((k+1)) "$trail")"
      if [ -n "$w" ] && win_alive "$w"; then
        setg @ai_hist_nav 1
        setg @ai_hist_idx "$k"
        sess="$(tmux display-message -p -t "$w" '#{session_name}' 2>/dev/null || true)"
        [ -n "$sess" ] && tmux switch-client -t "$sess" 2>/dev/null || true
        tmux select-window -t "$w" 2>/dev/null || true
        exit 0
      fi
      k=$((k+1))
    done
    tmux display-message 'Historial: no hay más adelante'
    ;;
  *)
    tmux display-message "history.sh: comando desconocido '$cmd'"
    ;;
esac
