{ pkgs, system }:

pkgs.writeShellApplication {
  name = "linux-artifact-smoke";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.bash
    pkgs.curl
    pkgs.dpkg
    pkgs.iproute2
    pkgs.rpm
    pkgs.cpio
    pkgs.util-linux
  ];
  text = ''
    set -euo pipefail

    usage() {
      cat <<'USAGE'
    Usage: linux-artifact-smoke --artifacts-dir DIR --artifact-version VERSION

    Extracts and smoke-tests the Linux AppImage, DEB, and RPM release artifacts.
    USAGE
    }

    artifacts_dir=""
    artifact_version=""
    system_suffix="${system}"

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --artifacts-dir)
          artifacts_dir="$2"
          shift 2
          ;;
        --artifact-version)
          artifact_version="$2"
          shift 2
          ;;
        --system-suffix)
          system_suffix="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "unknown option: $1" >&2
          usage >&2
          exit 2
          ;;
      esac
    done

    if [ -z "$artifacts_dir" ] || [ -z "$artifact_version" ]; then
      usage >&2
      exit 2
    fi

    artifacts_dir="$(cd "$artifacts_dir" && pwd)"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    find_executable() {
      root="$1"
      bin=""
      if [ -x "$root/usr/bin/cardano-stake-csmt" ]; then
        bin="$root/usr/bin/cardano-stake-csmt"
      else
        bin="$(
          find -L "$root" -path '*/bin/cardano-stake-csmt' -type f -executable 2>/dev/null \
            | head -1 || true
        )"
      fi
      if [ -z "$bin" ]; then
        echo "linux-artifact-smoke: cardano-stake-csmt executable not found under $root" >&2
        exit 1
      fi
      printf '%s\n' "$bin"
    }

    assert_bundled_store_refs() {
      root="$1"
      label="$2"
      bundle_store="$root/usr/lib/cardano-stake-csmt/nix/store"
      refs="$workdir/$label-store-refs.txt"

      LC_ALL=C grep -RahoE '/nix/store/[0-9a-z]{32}[-+._A-Za-z0-9]*' "$root" 2>/dev/null \
        | sort -u > "$refs" || true

      missing=0
      while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        store_name="''${ref#/nix/store/}"
        case "$store_name" in
          eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-*) continue ;;
        esac
        if [ ! -e "$bundle_store/$store_name" ]; then
          echo "linux-artifact-smoke: $label references external store path $ref" >&2
          missing=1
        fi
      done < "$refs"

      if [ "$missing" -ne 0 ]; then
        exit 1
      fi
    }

    probe_server_host() {
      bin="$1"
      label="$2"
      log="$3"

      if curl --fail --silent --show-error --max-time 1 http://127.0.0.1:8080/ready >/dev/null 2>&1; then
        echo "linux-artifact-smoke: port 8080 already has a service on /ready" >&2
        exit 1
      fi

      "$bin" >"$log" 2>&1 &
      pid="$!"

      for _ in $(seq 1 60); do
        if ! kill -0 "$pid" 2>/dev/null; then
          echo "linux-artifact-smoke: $label server exited before readiness" >&2
          cat "$log" >&2
          exit 1
        fi

        ready_body="$(
          curl --fail --silent --show-error --max-time 1 http://127.0.0.1:8080/ready 2>/dev/null \
            || true
        )"
        if [ -n "$ready_body" ]; then
          printf '%s\n' "$ready_body" | grep -F '"ready":true' >/dev/null \
            || {
              echo "linux-artifact-smoke: unexpected /ready response from $label: $ready_body" >&2
              kill "$pid" >/dev/null 2>&1 || true
              exit 1
            }

          health_body="$(
            curl --fail --silent --show-error --max-time 1 http://127.0.0.1:8080/health
          )"
          if [ "$health_body" != "ok" ]; then
            echo "linux-artifact-smoke: unexpected /health response from $label: $health_body" >&2
            kill "$pid" >/dev/null 2>&1 || true
            exit 1
          fi

          kill "$pid" >/dev/null 2>&1 || true
          wait "$pid" 2>/dev/null || true
          return
        fi

        sleep 1
      done

      echo "linux-artifact-smoke: $label server did not become ready" >&2
      cat "$log" >&2
      kill "$pid" >/dev/null 2>&1 || true
      exit 1
    }

    probe_server() {
      bin="$1"
      label="$2"
      log="$workdir/$label.log"

      if unshare --user --map-root-user --net true >/dev/null 2>&1; then
        # shellcheck disable=SC2016
        unshare --user --map-root-user --net bash -c '
          set -euo pipefail
          bin="$1"
          label="$2"
          log="$3"

          ip link set lo up
          "$bin" >"$log" 2>&1 &
          pid="$!"

          for _ in $(seq 1 60); do
            if ! kill -0 "$pid" 2>/dev/null; then
              echo "linux-artifact-smoke: $label server exited before readiness" >&2
              cat "$log" >&2
              exit 1
            fi

            ready_body="$(
              curl --fail --silent --show-error --max-time 1 http://127.0.0.1:8080/ready 2>/dev/null \
                || true
            )"
            if [ -n "$ready_body" ]; then
              printf "%s\n" "$ready_body" | grep -F "\"ready\":true" >/dev/null \
                || {
                  echo "linux-artifact-smoke: unexpected /ready response from $label: $ready_body" >&2
                  kill "$pid" >/dev/null 2>&1 || true
                  exit 1
                }

              health_body="$(
                curl --fail --silent --show-error --max-time 1 http://127.0.0.1:8080/health
              )"
              if [ "$health_body" != "ok" ]; then
                echo "linux-artifact-smoke: unexpected /health response from $label: $health_body" >&2
                kill "$pid" >/dev/null 2>&1 || true
                exit 1
              fi

              kill "$pid" >/dev/null 2>&1 || true
              wait "$pid" 2>/dev/null || true
              exit 0
            fi

            sleep 1
          done

          echo "linux-artifact-smoke: $label server did not become ready" >&2
          cat "$log" >&2
          kill "$pid" >/dev/null 2>&1 || true
          exit 1
        ' bash "$bin" "$label" "$log"
      else
        probe_server_host "$bin" "$label" "$log"
      fi
    }

    smoke_appimage() {
      appimage="$artifacts_dir/cardano-stake-csmt-$artifact_version-$system_suffix.AppImage"
      test -f "$appimage"
      test -f "$artifacts_dir/cardano-stake-csmt.AppImage"

      appimage_dir="$workdir/appimage"
      mkdir -p "$appimage_dir"
      appimage_copy="$appimage_dir/cardano-stake-csmt.AppImage"
      cp -L "$appimage" "$appimage_copy"
      chmod +x "$appimage_copy"
      (
        cd "$appimage_dir"
        "$appimage_copy" --appimage-extract >/dev/null
      )
      assert_bundled_store_refs "$appimage_dir/squashfs-root" appimage
      bin="$(find_executable "$appimage_dir/squashfs-root")"
      probe_server "$bin" appimage
    }

    smoke_deb() {
      deb="$artifacts_dir/cardano-stake-csmt-$artifact_version-$system_suffix.deb"
      test -f "$deb"
      deb_dir="$workdir/deb"
      mkdir -p "$deb_dir"
      dpkg-deb -x "$deb" "$deb_dir"
      assert_bundled_store_refs "$deb_dir" deb
      bin="$(find_executable "$deb_dir")"
      probe_server "$bin" deb
    }

    smoke_rpm() {
      rpm="$artifacts_dir/cardano-stake-csmt-$artifact_version-$system_suffix.rpm"
      test -f "$rpm"
      rpm_dir="$workdir/rpm"
      mkdir -p "$rpm_dir"
      (
        cd "$rpm_dir"
        rpm2cpio "$rpm" | cpio -idm >/dev/null
      )
      assert_bundled_store_refs "$rpm_dir" rpm
      bin="$(find_executable "$rpm_dir")"
      probe_server "$bin" rpm
    }

    smoke_appimage
    smoke_deb
    smoke_rpm
  '';
}
