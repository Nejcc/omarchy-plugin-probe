#!/usr/bin/env bash
# Runs probe against a fake /proc tree and fake plugin dirs, then checks the
# attribution, ranking, CPU math and the ablate report.
#   bash tests/probe.test.sh

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fails=0
check() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want <$want> got <$got>"
    fails=$((fails + 1))
  fi
}

OP=$T/omarchy
UP=$T/plugins
mkdir -p "$OP/shell/plugins/clipboard" "$UP"/{acme.foo/bin,acme.foo-bar,acme.bar,acme.idle} "$T/bin" "$T/proc"
echo '{"id":"omarchy.clipboard"}' >"$OP/shell/plugins/clipboard/manifest.json"
for id in acme.foo acme.foo-bar acme.bar acme.idle; do echo "{\"id\":\"$id\"}" >"$UP/$id/manifest.json"; done

# The real omarchy-shell is never touched: this one answers listPlugins only.
cat >"$T/bin/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
[[ $2 == listPlugins ]] && echo '[{"id":"acme.foo","enabled":true},{"id":"acme.foo-bar","enabled":true},{"id":"acme.bar","enabled":false},{"id":"acme.idle","enabled":true},{"id":"omarchy.clipboard","enabled":true},{"id":"omarchy.tray","enabled":true}]'
EOF
chmod +x "$T/bin/omarchy-shell"

# proc PID PPID RSS_PAGES CWD ARGV...
proc() {
  local pid=$1 ppid=$2 rss=$3 cwd=$4 d=$T/proc/$1
  shift 4
  mkdir -p "$d"
  # comm with a space and a paren, like real kernel names can have.
  echo "$pid (we) ird) S $ppid 0 0 0 -1 0 0 0 0 0 7 3 0 0 20 0 1 0 500 0 0" >"$d/stat"
  echo "0 $rss 0 0 0 0 0" >"$d/statm"
  printf '%s\0' "$@" >"$d/cmdline"
  ln -s "$cwd" "$d/cwd"
}
proc 1 0 10 / /sbin/init
proc 100 1 1000 "$HOME" quickshell -n -p "$OP/shell"
proc 101 100 10 "$HOME" bash "$UP/acme.foo/bin/helper" watch
proc 102 101 20 "$HOME" inotifywait -m /tmp
proc 103 100 30 "$HOME" tmux -f "$UP/acme.foo-bar/x.conf"
proc 104 100 5 "$HOME" udevadm monitor
proc 105 1 40 "$UP/acme.bar" python3 server.py
proc 106 1 2 "$HOME" qs ipc -n -p "$OP/shell" call shell ping
proc 107 100 3 "$HOME" wl-paste --watch "$OP/shell/plugins/clipboard/capture.sh"
proc 108 100 4 "$HOME" inotifywait -m -r "$UP"

out=$(PATH=$T/bin:$PATH PROBE_PROC=$T/proc PROBE_PLUGINS_DIR=$UP OMARCHY_PATH=$OP "$ROOT/bin/probe" snapshot --json --sample 0)
page_kb=$(($(getconf PAGESIZE) / 1024))
plugin() { jq -c --arg id "$1" '.plugins[] | select(.id == $id) | [.processes, .rssKb, .enabled, .pids]' <<<"$out"; }

check "shell found, not the qs ipc call" "[100,$((1000 * page_kb))]" "$(jq -c '[.shell.pid, .shell.rssKb]' <<<"$out")"
check "helper and its child go to acme.foo" "[2,$((30 * page_kb)),true,[101,102]]" "$(plugin acme.foo)"
check "foo-bar is not claimed by foo" "[1,$((30 * page_kb)),true,[103]]" "$(plugin acme.foo-bar)"
check "cwd attributes outside the shell tree" "[1,$((40 * page_kb)),false,[105]]" "$(plugin acme.bar)"
check "first-party plugin dir" "[1,$((3 * page_kb)),true,[107]]" "$(plugin omarchy.clipboard)"
check "dir-less built-in widget is listed" "[0,0,true,[]]" "$(plugin omarchy.tray)"
check "plugins root itself and udevadm stay unattributed" "[104,108]" "$(jq -c '.unattributed.pids' <<<"$out")"
check "ranked by RSS" '["acme.bar","acme.foo","acme.foo-bar","omarchy.clipboard"]' "$(jq -c '[.plugins[] | select(.processes > 0) | .id]' <<<"$out")"

# CPU: 50 ticks over 1s at 100 Hz is 50% of one core; a pid missing from the
# first sample counts as zero, not its lifetime total.
before=$'100\t1\t1000\t1\t/\tquickshell -p /s\n200\t100\t10\t1\t/\tbash /p/a/run'
after=$'100\t1\t1050\t1\t/\tquickshell -p /s\n200\t100\t30\t1\t/\tbash /p/a/run\n201\t200\t999\t1\t/\tsleep 1'
cpu=$(jq -n -c -f "$ROOT/bin/attribute.jq" --arg before "$before" --arg after "$after" \
  --argjson plugins '[{"id":"a","dirs":["/p/a"]}]' --argjson enabled '{}' --arg config /s --argjson hz 100 --argjson elapsed 1 |
  jq -c '[.shell.cpu, (.plugins[0] | .cpu, .processes)]')
check "cpu percent per core" "[50,20,2]" "$cpu"

# Ablate report: delta and whether it clears the spread.
report=$(printf '%s\n' \
  '{"state":"with","shellKb":204800,"helperKb":10240,"startupMs":900}' \
  '{"state":"without","shellKb":102400,"helperKb":0,"startupMs":880}' \
  '{"state":"with","shellKb":206848,"helperKb":10240,"startupMs":800}' \
  '{"state":"without","shellKb":104448,"helperKb":0,"startupMs":950}' |
  jq -rs --arg id acme.foo -f "$ROOT/bin/ablate-report.jq")
check "rss delta above noise" "shell RSS	201 MB (200-202)	101 MB (100-102)	+100 MB	above noise" "$(sed -n 4p <<<"$report")"
check "startup delta within noise" "startup	850 ms (800-900)	915 ms (880-950)	-65 ms	within noise" "$(sed -n 6p <<<"$report")"

# Ablate end to end against fakes: the shell's state lives in a fake
# shell.json, restarts are no-ops, and the original file must come back
# byte for byte, also when a restart fails halfway.
cat >"$T/bin/omarchy-shell" <<EOF
#!/usr/bin/env bash
case \$2 in
  ping) [[ ! -e "$T/dead" ]] ;;
  listPlugins) grep -q disabled "$T/shell.json" && e=false || e=true; echo "[{\"id\":\"acme.foo\",\"kinds\":[\"service\"],\"canDisable\":true,\"enabled\":\$e}]" ;;
  setPluginEnabled) echo '{"layout":"moved","disabled":["acme.foo"]}' >"$T/shell.json" ;;
esac
EOF
cat >"$T/bin/omarchy-restart-shell" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$T/restarts" 2>/dev/null || echo 0) + 1 )); echo \$n >"$T/restarts"
# A failed restart leaves no shell until the next restart brings one up.
rm -f "$T/dead"
[[ -z \${FAIL_AT:-} || \$n -ne \$FAIL_AT ]] || { touch "$T/dead"; exit 1; }
EOF
chmod +x "$T/bin/omarchy-shell" "$T/bin/omarchy-restart-shell"
echo '100.00 1.00' >"$T/proc/uptime"
original='{"layout":"mine, with settings"}'
ablate() { PATH=$T/bin:$PATH PROBE_PROC=$T/proc PROBE_PLUGINS_DIR=$UP PROBE_SHELL_JSON=$T/shell.json OMARCHY_PATH=$OP "$ROOT/bin/probe" ablate acme.foo --runs 1 --settle 0 --yes; }

echo "$original" >"$T/shell.json"
report=$(ablate 2>/dev/null)
check "ablate restores shell.json" "$original" "$(cat "$T/shell.json")"
check "ablate restarts: 2 runs + restore" "3" "$(cat "$T/restarts")"
check "ablate prints a report" "1" "$(grep -c '^startup ' <<<"$report")"

rm -f "$T/restarts"
echo "$original" >"$T/shell.json"
FAIL_AT=2 PROBE_READY_TIMEOUT=1 ablate >/dev/null 2>&1 && status=0 || status=$?
check "failed restart aborts" "1" "$status"
check "failed run still restores shell.json" "$original" "$(cat "$T/shell.json")"

((fails == 0)) || {
  echo "$fails failed"
  exit 1
}
echo "all passed"
