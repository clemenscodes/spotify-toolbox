{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
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
    flake-parts,
    android-nixpkgs,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem = {system, ...}: let
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
              android-sdk = android-nixpkgs.sdk.${system} (sdkPkgs: [
                sdkPkgs.platform-tools
                sdkPkgs.emulator
                sdkPkgs.cmdline-tools-latest
                sdkPkgs.ndk-27-2-12479018
                sdkPkgs.build-tools-34-0-0
                sdkPkgs.platforms-android-34
                sdkPkgs.sources-android-34
                sdkPkgs.system-images-android-34-google-apis-x86-64
                sdkPkgs.system-images-android-34-default-x86-64
              ]);
            })
          ];
        };
        jdk = pkgs.jdk21;
        gradle = pkgs.callPackage pkgs.gradle-packages.gradle_8 {java = jdk;};
      in {
        devShells = {
          default = pkgs.mkShell rec {
            JAVA_HOME = jdk.home;
            GRADLE_HOME = "${gradle}/lib/gradle";
            GRADLE_LOCAL_JAVA_HOME = JAVA_HOME;
            ANDROID_HOME = "${pkgs.android-sdk}/share/android-sdk";
            ANDROID_SDK_ROOT = ANDROID_HOME;
            ANDROID_NDK_HOME = "${ANDROID_HOME}/ndk/27.2.12479018";
            ANDROID_NDK_ROOT = ANDROID_NDK_HOME;
            NDK_HOME = ANDROID_NDK_HOME;
            AAPT2 = "${ANDROID_HOME}/build-tools/34.0.0/aapt2";
            ANDROID_AAPT2 = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${AAPT2}";
            GRADLE_JAVA_HOME = "-Dorg.gradle.java.home=${JAVA_HOME}";
            GRADLE_OPTS = "${GRADLE_JAVA_HOME} ${ANDROID_AAPT2}";
            buildInputs = [
              pkgs.android-sdk
              pkgs.nodejs
              pkgs.bun
            ];
            shellHook = ''
              ${pkgs.bun}/bin/bun install
            '';
          };
        };
      };
    };
}
