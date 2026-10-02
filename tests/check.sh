#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

omarchy plugin validate "$project_dir"
jq -e '.id == "io.github.nestorfaeric.ometalink" and .entryPoints.barWidget == "BarWidget.qml"' \
  "$project_dir/manifest.json" >/dev/null

for contract in \
  'moduleName: "io.github.nestorfaeric.ometalink"' \
  'target: "io.github.nestorfaeric.ometalink"' \
  'KeyboardPanel {' \
  'PanelKeyCatcher {' \
  '/ometalink-status' \
  '/ometalink-ctl'; do
  rg -Fq "$contract" "$project_dir/BarWidget.qml"
done

for script in "$project_dir"/bin/*; do
  test -x "$script"
  bash -n "$script"
done
python3 -m py_compile "$project_dir/tools/hfp-probe.py"

# An unknown address must still produce well-formed JSON.
"$project_dir/bin/ometalink-status" 00:00:00:00:00:00 \
  | jq -e '.found == true and .connected == false and .microphone == "unsupported"' >/dev/null

test -f "$project_dir/preview.png"
printf 'All OmetaLink checks passed.\n'
