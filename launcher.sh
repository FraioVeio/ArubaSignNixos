#!@bash@/bin/bash
# ArubaSign writes into its own install tree (licensing file in the install
# root, certificate DBs under asp/no-arch). The Nix store is read-only, so we
# mirror the install tree into a writable per-user directory:
#   - directories are real,
#   - files are symlinks into the store,
#   - executables that locate the install via /proc/self/exe and the databases
#     that get updated at runtime are real copies.
# The mirror is refreshed only when the store path changes (package update);
# files created by the application at runtime are preserved.
set -euo pipefail

src="@src@"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/arubasign"
stamp="$dest/.nix-source"

copied=(
  "./app/lin-x64/ArubaSign"
  "./asp/lin-x64/ArubaSignPlatform.exe"
  "./asp/no-arch/cert.cdb"
  "./asp/no-arch/dist/asp.db"
)

is_copied() {
  local f
  for f in "${copied[@]}"; do [[ "$1" == "$f" ]] && return 0; done
  return 1
}

if [[ "$(cat "$stamp" 2>/dev/null || true)" != "$src" ]]; then
  echo "arubasign: preparing writable install in $dest" >&2
  mkdir -p "$dest"
  # Drop symlinks from a previous version (they may point to a GC'd path).
  find "$dest" -type l -delete

  (cd "$src" && find . -mindepth 1 -type d) | while IFS= read -r d; do
    mkdir -p "$dest/$d"
  done

  (cd "$src" && find . ! -type d) | while IFS= read -r f; do
    if is_copied "$f"; then
      rm -f "$dest/$f"
      cp --reflink=auto "$src/$f" "$dest/$f"
      chmod u+w "$dest/$f"
    else
      ln -s "$src/${f#./}" "$dest/$f"
    fi
  done

  echo "$src" > "$stamp"
fi

# A cert DB copied into the workdir by older runs may be read-only.
workdb="$HOME/.ArubaSign/webconf/ArubaTrustedPlatform/cert.cdb"
[[ -f "$workdb" && ! -w "$workdb" ]] && chmod u+w "$workdb"

# Inside the FHS sandbox the JVM cannot infer the time zone from
# /etc/localtime (it points into the Nix store), so export it explicitly.
if [[ -z "${TZ:-}" ]]; then
  tz="$(readlink -f /etc/localtime 2>/dev/null || true)"
  [[ "$tz" == */zoneinfo/* ]] && export TZ="${tz##*/zoneinfo/}"
fi

flags=()
if [[ -n "${NIXOS_OZONE_WL:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
  flags+=(--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations)
fi

gui="$dest/app/lin-x64/ArubaSign"
pgrep="@procps@/bin/pgrep"
pkill="@procps@/bin/pkill"

# The GUI spawns a Java backend (and the HID->CCID converter) that upstream
# leaves running after the window is closed, with no tray icon to stop it.
# Stop them once the last ArubaSign window is gone, unless
# ARUBASIGN_KEEP_BACKEND is set.
backend_patterns=(
  "^$dest/asp/lin-x64/ArubaSignPlatform\.exe( |\$)"
  "^$HOME/\.hsvc_$UID/"
)

# True if an ArubaSign main (browser) process is still running. Electron
# helper processes carry --type=... and are ignored. A second launch hands its
# arguments to the running instance and exits at once, so this keeps the
# backend alive while another window is still open.
gui_running() {
  local line
  while IFS= read -r line; do
    [[ "$line" == *--type=* ]] || return 0
  done < <("$pgrep" -u "$UID" -a -f -- "^$gui( |\$)" || true)
  return 1
}

stop_backend() {
  local p alive
  for p in "${backend_patterns[@]}"; do
    "$pkill" -TERM -u "$UID" -f -- "$p" || true
  done
  # Give the JVM up to 5 s to run its shutdown hooks, then force it.
  for _ in {1..50}; do
    alive=0
    for p in "${backend_patterns[@]}"; do
      "$pgrep" -u "$UID" -f -- "$p" >/dev/null && alive=1
    done
    ((alive)) || return 0
    sleep 0.1
  done
  for p in "${backend_patterns[@]}"; do
    "$pkill" -KILL -u "$UID" -f -- "$p" || true
  done
}

"$gui" "${flags[@]}" "$@" &
gui_pid=$!
trap 'kill -TERM "$gui_pid" 2>/dev/null || true' TERM INT HUP

status=0
while kill -0 "$gui_pid" 2>/dev/null; do
  wait "$gui_pid" || status=$?
done

if [[ -z "${ARUBASIGN_KEEP_BACKEND:-}" ]]; then
  # Let Electron's helper processes wind down before checking.
  sleep 1
  gui_running || stop_backend
fi

exit "$status"
