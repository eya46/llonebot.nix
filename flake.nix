{
  description = "llonebot.nix";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # 导入包构建模块
        packageLib = pkgs.callPackage ./package { };

      in
      rec {
        devShells.default = pkgs.mkShell { };

        lib = {
          inherit (packageLib) buildLLOneBot buildLLOneBotSandbox;
        };

        packages = rec {
          pmhq = packageLib.default.pmhq;

          llonebot-service =
            (pkgs.callPackage ./package/llonebot-service.nix {
              config = packageLib.defaultConfig;
            }).service;

          default = packageLib.default.llonebot;

          sandbox = (packageLib.buildLLOneBotSandbox { }).sandbox;

          # 添加 Docker 镜像构建
          dockerImage = pkgs.dockerTools.buildImage {
            name = "llonebot";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "llonebot-env";
              paths = [
                pkgs.mesa.drivers
                llonebot-service
                pkgs.coreutils
                pkgs.bash
              ];
            };
            config = {
              Cmd = [ "/bin/llonebot-service" ]; # 根据实际可执行文件路径调整
              Env = [
                "TZDIR=${pkgs.tzdata}/share/zoneinfo"
                "TZ=Asia/Shanghai"
              ];
              Expose = [
                "3000"
                "3001"
                "5600"
                "3080"
                "13000"
              ]; # 曝露端口
            };
          };
        };
      }
    );
}
