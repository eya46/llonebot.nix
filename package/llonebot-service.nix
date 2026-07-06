# This configuration file is derived from someone else's work. Thanks to the original author for their contribution.
# Original Author: Anillc
# Link: https://github.com/Anillc/chronocat.nix/blob/master/modules/chronocat.nix

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config;
  pmhq = pkgs.callPackage ./pmhq.nix {
    inherit pkgs lib config;
  };
  llonebot-js = pkgs.callPackage ./llonebot-js.nix { inherit pkgs lib; };
  fonts = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [ source-han-sans ];
  };
  # 基础环境设置脚本
  setupEnvironment = ''
    export PATH=${
      lib.makeBinPath (
        with pkgs;
        [
          pkgs.nodejs_24
          busybox
          xorg.xorgserver
          dbus
          dunst
          ffmpeg
          jq
        ]
      )
    }
    export FFMPEG_PATH=${pkgs.ffmpeg}/bin/ffmpeg
    export HOME=/root
    export XDG_DATA_HOME=/root/.local/share
    export XDG_CONFIG_HOME=/root/.config
    export TERM=xterm
    export DBUS_SESSION_BUS_ADDRESS='unix:path=/run/dbus/system_bus_socket'
    export DISPLAY='${toString cfg.display}'
    export LIBGL_ALWAYS_SOFTWARE=1

    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export SSL_CERT_DIR=/etc/ssl/certs
    export REQUESTS_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export CURL_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    : ''${QUICK_LOGIN_QQ:="${toString cfg.quick_login_qq}"}
    export ENV_QUICK_LOGIN_QQ=$QUICK_LOGIN_QQ
  '';

  # 创建必要的目录和文件
  setupDirectories = ''
    mkdir -p /root/{.local/share,.config} /etc/{ssl/certs,fonts,dbus} /run/dbus
    mkdir -p /tmp /usr/bin /bin

    # 基础系统文件
    echo "root:x:0:0::/root:${pkgs.runtimeShell}" > /etc/passwd
    echo "root:x:0:" > /etc/group
    echo "nameserver 114.114.114.114" > /etc/resolv.conf
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "172.17.0.1 host.docker.internal" >> /etc/hosts
    echo "::1 localhost" >> /etc/hosts

    # SSL证书目录设置
    mkdir -p /etc/ssl/certs /etc/pki/tls/certs
    # 符号链接
    ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
    ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
    ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt
    # 为Python设置默认证书位置
    ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/cert.pem
    ln -s ${fonts} /etc/fonts/fonts.conf
    ln -s $(which env) /usr/bin/env
    ln -s $(which sh) /bin/sh

    # PMHQ 配置：禁用 headless 模式
    cat > /pmhq_config.json << PMHQEOF
{
  "headless": false,
  "qq_console": true
}
PMHQEOF

    # llonebot 工作目录
    mkdir -p /root/llonebot
    cp -rf ${llonebot-js}/js/* /root/llonebot/
    sed -i "s|\"ffmpeg\":\s*\"\"|\"ffmpeg\": \"${pkgs.ffmpeg}/bin/ffmpeg\"|g" "/root/llonebot/default_config.json"
  '';

  # 配置 DBUS
  setupDbus = ''
    cp ${pkgs.dbus}/share/dbus-1/system.conf /etc/dbus/system.conf
    sed -i 's/<user>messagebus<\/user>/<user>root<\/user>/' /etc/dbus/system.conf
    sed -i 's/<deny/<allow/' /etc/dbus/system.conf
    rm -rf /run/dbus/pid
  '';

  # 创建服务函数
  servicesScript = ''
    createService() {
      mkdir -p /services/$1
      echo -e "#!${pkgs.runtimeShell}\n$2" > /services/$1/run
      chmod +x /services/$1/run
    }

    export XDG_RUNTIME_DIR=/tmp/runtime
    
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR
    
    rm -rf /tmp/.X11-unix
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
    
    createService xvfb "${pkgs.xorg.xorgserver}/bin/Xvfb ${toString cfg.display} -screen 0 1024x768x24 +extension GLX +render"

    # QQ with libpmhq.so directly (NO source-pmhq — avoids --disable-gpu injection!)
    # libpmhq.so starts its own WebSocket server on port 23456
    QQ_PATH=$(jq -r '.qq_path' ${pmhq}/bin/config.json)
    # Set up version config so QQ won't auto-update
    _QQ_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$(dirname $QQ_PATH)/../resources/app/package.json" 2>/dev/null || echo "3.2.25-45758")
    mkdir -p $HOME/.config/QQ/versions
    cat > $HOME/.config/QQ/versions/config.json << EOF
{"baseVersion": "$_QQ_VER", "curVersion": "$_QQ_VER"}
EOF
    LD_PRELOAD=${pmhq}/bin/libpmhq.so $QQ_PATH --no-sandbox &

    createService llonebot "cd /root/llonebot && node --enable-source-maps llbot.js --pmhq-host=${cfg.pmhq_host} --pmhq-port=23456"
  '';

in
{
  service = pkgs.writeScriptBin "llonebot-service" ''
    #!${pkgs.runtimeShell}

    ${setupEnvironment}
    ${setupDirectories}
    ${setupDbus}
    ${servicesScript}

    # 启动所有服务
    runsvdir /services
  '';
}
