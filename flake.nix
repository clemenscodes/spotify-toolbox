{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    gradle2nix = {
      url = "github:clemenscodes/gradle2nix/v2";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs = {
        nixpkgs = {
          follows = "nixpkgs";
        };
      };
    };
  };
  outputs = {
    nixpkgs,
    gradle2nix,
    android-nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pname = "spotify-toolbox";
    version = "0.0.1";
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";
    jdk = pkgs.jdk21;
    gradle = pkgs.callPackage pkgs.gradle-packages.gradle_8 {java = jdk;};
    JAVA_HOME = jdk.home;
    GRADLE_HOME = "${gradle}/lib/gradle";
    GRADLE_LOCAL_JAVA_HOME = JAVA_HOME;
    ANDROID_HOME = "${pkgs.android-studio.sdk}/share/android-sdk";
    ANDROID_SDK_ROOT = ANDROID_HOME;
    ANDROID_NDK_HOME = "${ANDROID_HOME}/ndk/27.2.12479018";
    ANDROID_NDK_ROOT = ANDROID_NDK_HOME;
    AAPT2 = "${ANDROID_HOME}/build-tools/34.0.0/aapt2";
    ANDROID_AAPT2 = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${AAPT2}";
    GRADLE_JAVA_HOME = "-Dorg.gradle.java.home=${JAVA_HOME}";
    GRADLE_OPTS = "${GRADLE_JAVA_HOME} ${ANDROID_AAPT2}";
    GRADLE_INSTALL_FLAG = ":app:assembleDebug";
    emulatorBins = with pkgs; [
      file
      mesa-demos
      pciutils
      xorg.setxkbmap
    ];
    emulatorLibs = with pkgs; [
      alsa-lib
      dbus
      systemd
      expat
      libbsd
      libpulseaudio
      libuuid
      libxkbcommon
      xorg.libX11
      xorg.libxcb
      xorg.xcbutilwm
      xorg.xcbutilrenderutil
      xorg.xcbutilkeysyms
      xorg.xcbutilimage
      xorg.xcbutilcursor
      xorg.libICE
      xorg.libSM
      xorg.libxkbfile
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXfixes
      libGL
      libdrm
      libpng
      nspr
      nss_latest
      gtk2
      glib
      wayland
    ];
    pkgs = import nixpkgs {
      inherit system;
      config = {
        android_sdk = {
          accept_license = true;
        };
        allowUnfreePredicate = pkg: let
          unfreePkgs = [
            "android-studio-stable"
            "android-sdk-cmdline-tools"
            "android-sdk-tools"
          ];
        in
          builtins.elem (pkgs.lib.getName pkg) unfreePkgs;
      };
      overlays = [
        (final: prev: {
          inherit gradle;
          android-studio = (prev.android-studio).withSdk (android-nixpkgs.sdk.${system} (sdkPkgs:
            with sdkPkgs; [
              platform-tools
              emulator
              cmdline-tools-latest
              ndk-27-2-12479018
              build-tools-34-0-0
              platforms-android-34
              sources-android-34
              system-images-android-34-google-apis-x86-64
              system-images-android-34-default-x86-64
            ]));
          spotify-toolbox-android = gradle2nix.builders.${system}.buildGradlePackage rec {
            inherit
              pname
              version
              gradle
              JAVA_HOME
              ANDROID_HOME
              ANDROID_NDK_ROOT
              ANDROID_SDK_ROOT
              GRADLE_LOCAL_JAVA_HOME
              ;
            buildJdk = jdk;
            src = ./.;
            lockFile = ./gradle.lock;
            gradleFlags = [
              GRADLE_JAVA_HOME
              ANDROID_AAPT2
            ];
            gradleInstallFlags = [
              GRADLE_INSTALL_FLAG
            ];
            nativeBuildInputs = with pkgs; [
              makeWrapper
              android-studio.sdk
              jdk
            ];
            postInstall = ''
              mkdir -p $out
              cp app/build/outputs/apk/debug/app-debug.apk $out/${pname}-${version}.apk
            '';
          };
          spotify-toolbox-android-emulator = final.stdenv.mkDerivation {
            inherit version;
            pname = "${pname}-emulator";
            buildCommand = ''
              mkdir -p $out/bin
              cat > $out/bin/${pname}-emulator << "EOF"
              #!${final.bash}/bin/bash -e

              if [ "$TMPDIR" = "" ]
              then
                  export TMPDIR=/tmp
              fi

              export LD_LIBRARY_PATH=${builtins.toString (pkgs.lib.makeLibraryPath emulatorLibs)}
              export PATH="$PATH:${builtins.toString (pkgs.lib.makeBinPath emulatorBins)}"
              export QT_XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb
              export QT_COMPOSE=${pkgs.xorg.libX11.out}/share/X11/locale
              export JAVA_HOME=${JAVA_HOME}
              export ANDROID_HOME=${ANDROID_HOME}
              export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}
              export ANDROID_NDK_HOME=${ANDROID_NDK_HOME}
              export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}
              export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1
              export ANDROID_USER_HOME=$(mktemp -d $TMPDIR/nix-android-user-home-XXXX)
              export ANDROID_AVD_HOME=$ANDROID_USER_HOME/avd
              export AVD_NAME="Nix_AVD"
              export AVD_PLATFORM_VERSION="34"
              export AVD_SYSTEM_IMAGE_TYPE="google_apis"
              export AVD_ABI_VERSION="x86_64"
              export AVD_IMAGE="system-images;android-$AVD_PLATFORM_VERSION;$AVD_SYSTEM_IMAGE_TYPE;$AVD_ABI_VERSION"
              export AVD_PATH="$ANDROID_AVD_HOME/$AVD_NAME.avd"
              export ANDROID_PACKAGE="thm.mse.spotify-toolbox"
              export ANDROID_ACTIVITY=".MainActivity"

              echo "Looking for a free TCP port in range 5554-5584" >&2

              for i in $(seq 5554 2 5584)
              do
                if [ -z "$(${final.android-studio.sdk}/bin/adb devices | grep emulator-$i)" ]
                then
                  port=$i
                  break
                fi
              done

              if [ -z "$port" ]
              then
                echo "Unfortunately, the emulator port space is exhausted!" >&2
                exit 1
              else
                echo "We have a free TCP port: $port" >&2
              fi

              export ANDROID_SERIAL="emulator-$port"

              if [ "$(${final.android-studio.sdk}/bin/avdmanager list avd | grep 'Name: $AVD_NAME')" = "" ]
              then
                yes "" | ${final.android-studio.sdk}/bin/avdmanager create avd --force -n $AVD_NAME -k "$AVD_IMAGE" -p $AVD_PATH
                echo "hw.gpu.enabled=yes" >> $ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini
                echo "hw.gpu.mode=host" >> $ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini
              fi

              echo "\nLaunch the emulator"
              ${final.android-studio.sdk}/bin/emulator -avd $AVD_NAME -gpu host -no-boot-anim -port $port &

              echo "Waiting until the emulator has booted the $AVD_NAME and the package manager is ready..." >&2

              ${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL wait-for-device

              echo "Device state has been reached" >&2

              while [ -z "$(${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL shell getprop dev.bootcomplete | grep 1)" ]
              do
                sleep 2
              done

              echo "dev.bootcomplete property is 1" >&2

              while [ -z "$(${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL shell getprop sys.boot_completed | grep 1)" ]
              do
                sleep 2
              done

              echo "sys.boot_completed property is 1" >&2

              echo "ready" >&2

              if [ "$(${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL shell pm list packages | grep package:$ANDROID_PACKAGE)" = "" ]
              then
                appPath="${pkgs.spotify-toolbox}/${pkgs.spotify-toolbox.name}.apk"
                ${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL install "$appPath"
              fi

              ${final.android-studio.sdk}/bin/adb -s $ANDROID_SERIAL shell am start -a android.intent.action.MAIN -n $ANDROID_PACKAGE/$ANDROID_ACTIVITY

              EOF
              chmod +x $out/bin/${pname}-emulator
            '';
          };
          lockgradle = final.writeShellScriptBin "lockgradle" ''
            ${gradle2nix.packages.${system}.gradle2nix}/bin/gradle2nix \
              -j ${JAVA_HOME} \
              --gradle-home ${GRADLE_HOME} \
              -l gradle.lock \
              -t ${GRADLE_INSTALL_FLAG}
          '';
        })
      ];
    };
  in {
    packages = {
      ${system} = {
        inherit
          (pkgs)
          android-studio
          spotify-toolbox
          spotify-toolbox-android-emulator
          lockgradle
          ;
        default = pkgs.spotify-toolbox-app-emulator;
      };
    };
    devShells = {
      ${system} = {
        default = pkgs.mkShell rec {
          inherit
            LANG
            LC_ALL
            JAVA_HOME
            GRADLE_LOCAL_JAVA_HOME
            GRADLE_HOME
            GRADLE_OPTS
            ANDROID_HOME
            ANDROID_NDK_ROOT
            ANDROID_SDK_ROOT
            ;
          buildInputs = with pkgs; [
            jdk
            gradle
            lockgradle
            android-studio
            android-studio.sdk
            bun
            nodejs
          ];
          shellHook = ''
            export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${builtins.toString (pkgs.lib.makeLibraryPath emulatorLibs)}"
            export PATH="$PATH:${builtins.toString (pkgs.lib.makeBinPath emulatorBins)}"
            export QT_XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb
            export QT_COMPOSE=${pkgs.xorg.libX11.out}/share/X11/locale
            export JAVA_HOME=${JAVA_HOME}
            export ANDROID_HOME=${ANDROID_HOME}
            export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}
            export ANDROID_NDK_HOME=${ANDROID_NDK_HOME}
            export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}
            export GRADLE_USER_HOME="$(pwd)/.gradle"
            export ANDROID_USER_HOME="$(pwd)/.android"
            export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
            export ANDROID_AVD_HOME=$ANDROID_USER_HOME/avd
            export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1
            export AVD_NAME="Nix_AVD"
            export AVD_PLATFORM_VERSION="34"
            export AVD_SYSTEM_IMAGE_TYPE="google_apis"
            export AVD_ABI_VERSION="x86_64"
            export AVD_IMAGE="system-images;android-$AVD_PLATFORM_VERSION;$AVD_SYSTEM_IMAGE_TYPE;$AVD_ABI_VERSION"
            export AVD_PATH="$ANDROID_AVD_HOME/$AVD_NAME.avd"
            export ANDROID_PACKAGE="thm.mse.spotify-toolbox"
            export ANDROID_ACTIVITY=".MainActivity"
            export NIX_ANDROID_AVD_FLAGS=""
            export NIX_ANDROID_EMULATOR_FLAGS=""

            echo "Looking for a free TCP port in range 5554-5584" >&2

            for i in $(seq 5554 2 5584)
            do
              if [ -z "$(${pkgs.android-studio.sdk}/bin/adb devices | grep emulator-$i)" ]
              then
                port=$i
                break
              fi
            done

            if [ -z "$port" ]
            then
              echo "Unfortunately, the emulator port space is exhausted!" >&2
              exit 1
            else
              echo "We have a free TCP port: $port" >&2
            fi

            export PORT=$port
            export ANDROID_SERIAL="emulator-$PORT"

            if [ "$(${pkgs.android-studio.sdk}/bin/avdmanager list avd | grep 'Name: $AVD_NAME')" = "" ]
            then
              yes "" | ${pkgs.android-studio.sdk}/bin/avdmanager create avd --force -n $AVD_NAME -k "$AVD_IMAGE" -p $AVD_PATH
              echo "hw.gpu.enabled=yes" >> $ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini
              echo "hw.gpu.mode=host" >> $ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini
            fi

            [ -f local.properties ] && chmod +w local.properties
            echo "sdk.dir=${ANDROID_HOME}" > local.properties
            echo "ndk.dir=${ANDROID_NDK_HOME}" >> local.properties
            echo "java.home=${JAVA_HOME}" >> local.properties
            echo "gradle.user.home=$GRADLE_USER_HOME" >> local.properties
            chmod 444 local.properties
          '';
        };
      };
    };
  };
}
