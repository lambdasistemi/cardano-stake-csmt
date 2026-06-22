{
  pkgs,
  system,
  packageVersion,
  artifactVersion ? packageVersion,
  package,
}:

let
  lib = pkgs.lib;
  appImageRuntime = pkgs.fetchurl {
    url = "https://github.com/AppImage/AppImageKit/releases/download/12/appimagetool-x86_64.AppImage";
    sha256 = "04ws94q71bwskmhizhwmaf41ma4wabvfgjgkagr8wf3vakgv866r";
  };
  runtimeClosure = pkgs.closureInfo {
    rootPaths = [ package ];
  };
  packageIteration =
    if artifactVersion == packageVersion then
      "1"
    else
      lib.removePrefix "${packageVersion}-" artifactVersion;
  debArch =
    if system == "x86_64-linux" then
      "amd64"
    else
      throw "unsupported Linux release system for DEB artifacts: ${system}";
  rpmArch =
    if system == "x86_64-linux" then
      "x86_64"
    else
      throw "unsupported Linux release system for RPM artifacts: ${system}";
in
pkgs.runCommand "cardano-stake-csmt-${artifactVersion}-${system}-artifacts"
  {
    nativeBuildInputs = [
      pkgs.binutils-unwrapped
      pkgs.cpio
      pkgs.coreutils
      pkgs.dpkg
      pkgs.findutils
      pkgs.fpm
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnutar
      pkgs.gzip
      pkgs.patchelf
      pkgs.rpm
      pkgs.squashfsTools
      pkgs.xz
    ];
    passthru = {
      inherit
        appImageRuntime
        package
        ;
    };
  }
  ''
    set -euo pipefail

    mkdir -p "$out"
    workdir="$(mktemp -d)"

    install_tree="$workdir/install-root"
    bundle_store="$install_tree/usr/lib/cardano-stake-csmt/nix/store"
    mkdir -p \
      "$install_tree/usr/bin" \
      "$install_tree/usr/share/doc/cardano-stake-csmt" \
      "$bundle_store"

    while IFS= read -r store_path; do
      cp -a "$store_path" "$bundle_store/"
    done < ${runtimeClosure}/store-paths
    chmod -R u+rwX "$install_tree"

    exe_store_name="$(basename ${package})"
    interpreter="$(patchelf --print-interpreter ${package}/bin/cardano-stake-csmt)"
    interpreter_store_name="$(printf '%s\n' "$interpreter" | cut -d/ -f4)"
    interpreter_rel="''${interpreter#/nix/store/$interpreter_store_name/}"

    cat > "$install_tree/usr/bin/cardano-stake-csmt" <<WRAPPER
    #!/bin/sh
    set -eu

    self="\$0"
    case "\$self" in
      */*) ;;
      *) self="\$(command -v -- "\$self" 2>/dev/null || printf '%s' "\$self")" ;;
    esac
    case "\$self" in
      /*) ;;
      *) self="\$(pwd)/\$self" ;;
    esac
    case "\$self" in
      */usr/bin/cardano-stake-csmt)
        root="\''${self%/usr/bin/cardano-stake-csmt}"
        ;;
      *)
        root="\''${self%/*}"
        root="\''${root%/bin}"
        ;;
    esac
    [ -n "\$root" ] || root=/

    bundle_store="\$root/usr/lib/cardano-stake-csmt/nix/store"
    exe="\$bundle_store/$exe_store_name/bin/cardano-stake-csmt"
    loader="\$bundle_store/$interpreter_store_name/$interpreter_rel"

    if [ ! -x "\$exe" ]; then
      echo "cardano-stake-csmt: bundled executable missing: \$exe" >&2
      exit 127
    fi
    if [ ! -x "\$loader" ]; then
      echo "cardano-stake-csmt: bundled loader missing: \$loader" >&2
      exit 127
    fi

    library_path=
    for dir in "\$bundle_store"/*/lib "\$bundle_store"/*/lib64; do
      [ -d "\$dir" ] || continue
      if [ -z "\$library_path" ]; then
        library_path="\$dir"
      else
        library_path="\$library_path:\$dir"
      fi
    done

    exec "\$loader" --library-path "\$library_path" "\$exe" "\$@"
    WRAPPER
    chmod 0755 "$install_tree/usr/bin/cardano-stake-csmt"

    cat > "$install_tree/usr/share/doc/cardano-stake-csmt/README" <<'DOC'
    cardano-stake-csmt maintains a Compact Sparse Merkle Tree over Cardano stake snapshots.
    DOC

    appdir="$workdir/CardanoStakeCSMT.AppDir"
    mkdir -p "$appdir/usr/bin"
    cp -R "$install_tree/usr" "$appdir/"
    cat > "$appdir/AppRun" <<'APPRUN'
    #!/usr/bin/env sh
    set -eu
    self="$0"
    case "$self" in
      */*) appdir=''${self%/*} ;;
      *) appdir=. ;;
    esac
    appdir="$(cd "$appdir" && pwd)"
    exec "$appdir/usr/bin/cardano-stake-csmt" "$@"
    APPRUN
    chmod 0755 "$appdir/AppRun"
    cat > "$appdir/cardano-stake-csmt.desktop" <<'DESKTOP'
    [Desktop Entry]
    Type=Application
    Name=Cardano Stake CSMT
    Exec=cardano-stake-csmt
    Icon=cardano-stake-csmt
    Categories=Network;
    Terminal=true
    DESKTOP
    cat > "$appdir/cardano-stake-csmt.svg" <<'SVG'
    <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
      <rect width="128" height="128" fill="#0d3b66"/>
      <path d="M64 18 26 40v48l38 22 38-22V40L64 18Z" fill="#faf0ca"/>
      <path d="M64 36 42 49v30l22 13 22-13V49L64 36Z" fill="#2a9d8f"/>
      <circle cx="64" cy="64" r="10" fill="#f4d35e"/>
    </svg>
    SVG

    runtime_size="$(
      LC_ALL=C readelf -h ${appImageRuntime} \
        | awk 'NR==13 { e_shoff = $5 } NR==18 { e_shentsize = $5 } NR==19 { e_shnum = $5 } END { print e_shoff + e_shentsize * e_shnum }'
    )"
    test -n "$runtime_size"
    head -c "$runtime_size" ${appImageRuntime} > "$workdir/runtime"
    mksquashfs "$appdir" "$workdir/cardano-stake-csmt.squashfs" \
      -noappend -all-root -quiet >/dev/null

    appimage="$out/cardano-stake-csmt-${artifactVersion}-${system}.AppImage"
    cat "$workdir/runtime" "$workdir/cardano-stake-csmt.squashfs" > "$appimage"
    chmod 0755 "$appimage"
    cp "$appimage" "$out/cardano-stake-csmt.AppImage"

    common_fpm_args=(
      --name cardano-stake-csmt
      --version ${packageVersion}
      --iteration ${packageIteration}
      --license Apache-2.0
      --maintainer "Lambdasistemi"
      --url "https://github.com/lambdasistemi/cardano-stake-csmt"
      --description "Cardano stake CSMT HTTP service"
      --input-type dir
      --chdir "$install_tree"
    )

    fpm "''${common_fpm_args[@]}" \
      --output-type deb \
      --architecture ${debArch} \
      --package "$out/cardano-stake-csmt-${artifactVersion}-${system}.deb" \
      usr
    fpm "''${common_fpm_args[@]}" \
      --output-type rpm \
      --architecture ${rpmArch} \
      --package "$out/cardano-stake-csmt-${artifactVersion}-${system}.rpm" \
      usr

    (
      cd "$out"
      sha256sum \
        "cardano-stake-csmt-${artifactVersion}-${system}.AppImage" \
        "cardano-stake-csmt.AppImage" \
        "cardano-stake-csmt-${artifactVersion}-${system}.deb" \
        "cardano-stake-csmt-${artifactVersion}-${system}.rpm" \
        > SHA256SUMS
    )
  ''
