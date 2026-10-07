# Turns two /proc samples into the snapshot JSON.
#
# Inputs (all via --arg/--argjson/--rawfile):
#   $before, $after  sample text: one process per line,
#                    pid \t ppid \t utime+stime ticks \t rss kB \t cwd \t cmdline
#   $plugins         [{id, dirs: [absolute dir, its realpath, ...]}]
#   $enabled         {id: bool} from `omarchy-shell shell listPlugins`, or {}
#   $config          the shell's config dir ($OMARCHY_PATH/shell)
#   $hz, $elapsed    clock ticks per second, seconds between the samples

# Widgets built into another plugin (the bar's own) have no dir of their own:
# listed, never attributed.
def all_plugins: $plugins + [$enabled | keys[] | select(. as $id | $plugins | all(.id != $id)) | {id: ., dirs: []}];

def rows:
  split("\n") | map(select(length > 0) | split("\t") | select(length >= 6) | {
    pid: (.[0] | tonumber), ppid: (.[1] | tonumber), ticks: (.[2] | tonumber),
    rss: (.[3] | tonumber), cwd: .[4], cmd: (.[5:] | join("\t"))
  });

# The shell is `quickshell|qs [flags] -p <config>`. Requiring only flags before
# -p skips `qs ipc -p <config> call ...`, which omarchy-shell runs constantly.
# ponytail: max RSS breaks ties between several matches; the real shell is
# always the big one.
def is_shell:
  (.cmd | split(" ")) as $w
  | ([range(1; $w | length) | select($w[.] | startswith("-") | not)] | first) as $i
  | ($w[0] // "" | split("/") | last | . == "quickshell" or . == "qs")
    and $i != null and ($w[$i - 1] == "-p" or $w[$i - 1] == "--path")
    and ($w[$i] | rtrimstr("/")) == ($config | rtrimstr("/"));

# dir appears in cmd as a whole path: whatever follows it is not a name char,
# so .../plugins/foo never claims .../plugins/foo-bar.
def mentions($dir):
  . as $cmd | any($cmd | indices($dir)[]; ($cmd[(. + ($dir | length)):(. + ($dir | length) + 1)]) | test("^[^A-Za-z0-9._-]?$"));

def own_plugin:
  . as $p
  | [ $plugins[] | . as $pl | $pl.dirs[] | . as $d | select(($p.cmd | mentions($d)) or $p.cwd == $d or ($p.cwd | startswith($d + "/"))) | {id: $pl.id, len: ($d | length)} ]
  | max_by(.len) | .id? // null;

def cpu($ticks): if $elapsed > 0 then ($ticks / $hz / $elapsed * 1000 | round) / 10 else 0 end;

($before | rows | map({key: (.pid | tostring), value: .ticks}) | from_entries) as $t0
| ($after | rows | map(. + {own: own_plugin, delta: ((.ticks - ($t0[.pid | tostring] // .ticks)) | if . < 0 then 0 else . end)})) as $procs
| ($procs | map({key: (.pid | tostring), value: .}) | from_entries) as $byPid
| ($procs | map(select(is_shell)) | max_by(.rss)) as $shell
# Nearest attributed ancestor wins; the depth cap stops a ppid cycle in bad input.
| def owner($pid; $d):
    $byPid[$pid | tostring] as $p
    | if $p == null or $d > 64 then null elif $p.own then $p.own else owner($p.ppid; $d + 1) end;
  def under_shell($pid; $d):
    $byPid[$pid | tostring] as $p
    | if $p == null or $d > 64 then false elif $p.pid == $shell.pid then true else under_shell($p.ppid; $d + 1) end;
  ($procs | map(select(.pid != $shell.pid) | . + {owner: owner(.pid; 0)})) as $owned
| def total($list): {processes: ($list | length), rssKb: ($list | map(.rss) | add // 0), cpu: cpu($list | map(.delta) | add // 0), pids: ($list | map(.pid))};
  {
    sampleSeconds: $elapsed,
    shell: (if $shell then {pid: $shell.pid, rssKb: $shell.rss, cpu: cpu($shell.delta)} else null end),
    plugins: ([
      all_plugins[] | .id as $id
      | {id: $id, enabled: $enabled[$id]} + total([$owned[] | select(.owner == $id)])
    ] | sort_by(-.rssKb, -.cpu, .id)),
    unattributed: total(if $shell then [$owned[] | select(.owner == null and under_shell(.ppid; 0))] else [] end)
  }
