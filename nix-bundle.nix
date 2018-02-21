{ pkgs, daedalus, nix-bundle, coreutils, utillinux, procps, lib, gnutar, xz, pv, gnused }:

let
  bundle = import (pkgs.fetchFromGitHub {
    owner = "input-output-hk";
    repo = "nix-bundle";
    rev = "630e89d1d16083";
    sha256 = "1s9vzlsfxd2ym8jzv2p64j6jlwr9cmir45mb12yzzjr4dc91xk8x";
  }) { nixpkgs = pkgs; };
  wrapper = pkgs.writeScriptBin "daedalus-wrapper" ''
  #!${pkgs.stdenv.shell}

  export PATH=${coreutils}/bin:${utillinux}/bin:${procps}/bin

  mkdir /etc/
  for x in machine-id resolv.conf hosts nsswitch.conf; do
    cp /host-etc/$x /etc/$x
  done
  ln -sv ${pkgs.iana-etc}/etc/protocols /etc/protocols
  ln -sv ${pkgs.iana-etc}/etc/services /etc/services

  exec ${daedalus}/bin/daedalus
  '';
  namespaceHelper = pkgs.writeScriptBin "namespaceHelper" ''
    #!/bin/sh

    set -x
    set -e
    cd "$(dirname "''${BASH_SOURCE[0]}")"

    exec .${bundle.nix-user-chroot}/bin/nix-user-chroot -n ./nix -c -m /home:/home -m /etc:/host-etc -p DISPLAY -p HOME -p XAUTHORITY -- ${wrapper}/bin/daedalus-wrapper
  '';
  foo = bundle.nix-bootstrap {
    target = "${wrapper}";
    run = "/bin/daedalus-wrapper";
    nixUserChrootFlags = "-c -m /home:/home -m /etc:/host-etc -p DISPLAY -p HOME -p XAUTHORITY";
  };
  daedalusPackage = pkgs.callPackage (pkgs.path + "/nixos/lib/make-system-tarball.nix") {
    fileName = "daedalusPackage";
    contents = [];
    storeContents = [
      {
        object = namespaceHelper;
        symlink = "/namespaceHelper";
      }
    ];
  };
  desktopItem = pkgs.makeDesktopItem {
    name = "Daedalus";
    exec = "INSERT_PATH_HERE";
    desktopName = "Daedalus";
    genericName = "Crypto-Currency Wallet";
    categories = "Application;Network;";
  };
  installer = pkgs.writeScriptBin "daedalus-installer" ''
    #!${pkgs.stdenv.shell}

    set -e
    export PATH=${lib.makeBinPath [ coreutils gnutar xz pv gnused ]}

    test -z "$XDG_DATA_HOME" && { XDG_DATA_HOME="''${HOME}/.local/share"; }
    export DAEDALUS_DIR="''${XDG_DATA_HOME}/Daedalus"

    echo now installing daedalus...

    if [ -d "''${DAEDALUS_DIR}/unpack" ]; then
      chmod -R u+w "''${DAEDALUS_DIR}/unpack"
      rm -rf "''${DAEDALUS_DIR}/unpack"
    fi

    mkdir -pv "''${DAEDALUS_DIR}/unpack" "''${HOME}/bin/"

    pv ${daedalusPackage}/tarball/daedalusPackage.tar.xz | tar -C "''${DAEDALUS_DIR}/unpack" -xJ

    pushd "''${DAEDALUS_DIR}/unpack"
    rm namespaceHelper
    ln -s .${builtins.unsafeDiscardStringContext namespaceHelper}/bin/namespaceHelper namespaceHelper
    popd

    if [ -d "''${DAEDALUS_DIR}/installation" ]; then
      mv "''${DAEDALUS_DIR}/installation" "''${DAEDALUS_DIR}/garbage"
    fi
    mv "''${DAEDALUS_DIR}/unpack" "''${DAEDALUS_DIR}/installation"
    rm ~/bin/daedalus || true
    ln -sf "''${DAEDALUS_DIR}/installation/namespaceHelper" ~/bin/daedalus
    cat ${desktopItem}/share/applications/Daedalus.desktop | sed -e "s+INSERT_PATH_HERE+''${DAEDALUS_DIR}/installation/namespaceHelper+g" > "''${XDG_DATA_HOME}/applications/Daedalus.desktop"

    if [ -d "''${DAEDALUS_DIR}/garbage" ]; then
      echo cleaning up old version...
      chmod -R u+w "''${DAEDALUS_DIR}/garbage"
      rm -rf "''${DAEDALUS_DIR}/garbage"
    fi

    echo installation finished, daedalus is now in "''${DAEDALUS_DIR}/installation"
  '';
  installerBundle = bundle.nix-bootstrap {
    target = "${installer}";
    run = "/bin/daedalus-installer";
    nixUserChrootFlags = "-c -m /home:/home -p HOME";
  };
in {
  inherit foo installer namespaceHelper installerBundle;
}
