# Summarises `probe ablate` runs: [{state, shellKb, helperKb, startupMs}].
# A delta only counts when it is bigger than the run-to-run spread of either
# side; otherwise it is reported as noise.

def stats: {mean: (add / length), min: min, max: max, spread: (max - min)};
def mb: . / 1024 | . * 10 | round / 10;
def side($s; f): [.[] | select(.state == $s) | f] | stats;
def verdict($d; $w; $o): if ($d | fabs) > ([$w.spread, $o.spread] | max) then "above noise" else "within noise" end;
def row($name; $w; $o; fmt; $unit):
  ($w.mean - $o.mean) as $d
  | "\($name)\t\($w.mean | fmt) \($unit) (\($w.min | fmt)-\($w.max | fmt))\t\($o.mean | fmt) \($unit) (\($o.min | fmt)-\($o.max | fmt))\t\(if $d >= 0 then "+" else "" end)\($d | fmt) \($unit)\t\(verdict($d; $w; $o))";

map(. + {totalKb: (.shellKb + .helperKb)}) as $runs
| ($runs | map(select(.state == "with")) | length) as $n
| "\($id), \($n) runs per side (mean, min-max)",
  "",
  "METRIC\tWITH\tWITHOUT\tDELTA\tVERDICT",
  row("shell RSS"; $runs | side("with"; .shellKb); $runs | side("without"; .shellKb); mb; "MB"),
  row("shell + helpers"; $runs | side("with"; .totalKb); $runs | side("without"; .totalKb); mb; "MB"),
  row("startup"; $runs | side("with"; .startupMs); $runs | side("without"; .startupMs); round; "ms")
