#!/bin/bash
# Ubuntu Server 18.04
# AWS EC2 の ステップ3: インスタンスの詳細の設定 高度な詳細 > ユーザーデータ に貼り付けることで、
# インスタンス起動時にsymbol-testnet-bootstrapのpeerノードのセットアップを行います。
# また、動作の確認用に最新ブロック高を外部へ公開するサービスも動作させます。
# http://__ip_addr__:50080/height.txt でブロック高を確認できます。
#
# 次の作業を行います。
# * ノード動作用ユーザの作成
# * ssh接続ポートの変更
# * docker,docker-composeのインストール
# * symbol-testnet-bootstrapのdocker-composeをサービス化
# * 任意のfriendly_nameを設定(変数に値を入れてください)
# * 任意のhostを設定(変数に値を入れてください)
# * (既存ノードを接続先として取得して設定)
# * サーバ情報を外部に公開する仕組みのセットアップ
#
# セキュリティグループでは次のポートを公開してください。
# *  7900 peerノード間の通信用
# *  7902 ブローカーノード間の通信用(API起動時)
# *  3000 ゲートウェイの通信用(API起動時)
# * 50022 sshd (変数で任意に変更可)
# * 50080 ブロック高公開用 (変数で任意に変更可)
DEBUG=on # デバッグ情報を公開する
USER=symbol
PSWD=symbol # 変更を推奨
SSHD_PORT=50022
HTTPD_PORT=50080
DOCKER_COMPOSE_VER=1.25.4
BOOTSTRAP_TAG=0.9.2.1-beta4
ASSEMBLY=api-harvest # peer, api, api-harvest
FRIENDLY_NAME=
NODE_HOST=
# GATEWAY=http://api-xym-harvest-20.ap-northeast-1.nemtech.network

# -------------------------------------------------------------

[ "$ASSEMBLY" = "peer" ] && ROLE=peer || ROLE=api
USER_HOME=/home/$USER
BOOTSTRAP_HOME=$USER_HOME/symbol-testnet-bootstrap-$BOOTSTRAP_TAG
ASSEMBLY_HOME=$BOOTSTRAP_HOME/$ASSEMBLY-assembly

# sshdの接続ポート変更
/bin/sed -i -e "s/^#Port 22$/Port $SSHD_PORT/" /etc/ssh/sshd_config
systemctl restart sshd

# ノード用ユーザ作成

## Ubuntu ---------------------------------------------------- {
adduser --disabled-password --gecos "" "$USER"
echo "$USER:$PSWD" | chpasswd
## }

## CentOS ----------------------------------------------------- {
# useradd "$USER" -c ""
# echo "$PSWD" | passwd --stdin "$USER"
## }


# パッケージを最新へアップデート

## Ubuntu ---------------------------------------------------- {
apt-get update -y && apt-get upgrade -y
## }

## CentOS ----------------------------------------------------- {
# yum upgrade -y
## }


# dockerのインストール

## Ubuntu ---------------------------------------------------- {
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update -y && apt-get install -y docker-ce
## }

## CentOS ----------------------------------------------------- {
# yum remove -y docker \
#               docker-client \
#               docker-client-latest \
#               docker-common \
#               docker-latest \
#               docker-latest-logrotate \
#               docker-logrotate \
#               docker-engine
# yum install -y \
#   yum-utils \
#   device-mapper-persistent-data \
#   lvm2
# yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
# yum install -y \
#   http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.68-1.el7.noarch.rpm \
#   docker-ce docker-ce-cli containerd.io
## }

# -------------------------------------------------------------

# docker設定
usermod -a -G docker "$USER"
## コンテナのログ肥大化回避のため古いログは20MBごと5つまででローテーション
# echo '{"userns-remap":"default","log-driver":"json-file","log-opts":{"max-size":"20m","max-file":"5"}}' > /etc/docker/daemon.json
echo '{"userns-remap":"default","log-driver":"syslog","log-opts":{"tag":"docker/{{.ImageName}}/{{.Name}}/{{.ID}}"}}' > /etc/docker/daemon.json
## journaldに標準出力が流れているのでrsyslogから拾う
cat << \__EOD__ > /etc/rsyslog.d/60-docker.conf
$template DockerLogs, "/var/log/docker/%syslogtag:R,ERE,1,FIELD:docker/(.+)/--end%.log"
if $syslogfacility-text == 'daemon' and $programname contains 'docker' then -?DockerLogs
& stop
__EOD__
## ログローテーション設定
cat << __EOD__ > /etc//etc/logrotate.d/docker
/var/log/docker/*/*.log {
  daily
  rotate 7
  delaycompress
  compress
  notifempty
  missingok
  copytruncate
  dateext
}
__EOD__
systemctl daemon-reload
systemctl restart rsyslog
systemctl restart docker
sed -Ei.bak "/dockremap:/,/:/ s/[0-9]+/$(id -u symbol)/" /etc/subuid
sed -Ei.bak "/dockremap:/,/:/ s/[0-9]+/$(id -g symbol)/" /etc/subgid
systemctl restart docker

# docker-composeのインストール
curl -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VER/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# docker info
# docker-compose --version

# ホームディレクトリへ移動
cd $USER_HOME

# symbolノードブートストラップを取得
curl -L https://github.com/nemfoundation/symbol-testnet-bootstrap/archive/$BOOTSTRAP_TAG.tar.gz | tar zx
chown -R $USER: symbol-testnet-bootstrap-$BOOTSTRAP_TAG
cd $ASSEMBLY_HOME

# knownPeersを取得して設定ファイルを生成
#   リポジトリに入っている設定では都合が悪い場合に有効にしてください。
#   https://github.com/nemfoundation/symbol-testnet-bootstrap/blob/master/peer-assembly/peer-node/userconfig/resources/peers-p2p.json
# curl -o /usr/bin/jq http://stedolan.github.io/jq/download/linux64/jq
# chmod +x /usr/bin/jq
# curl -s $GATEWAY/node/peers \
#   | jq '.[] | {publicKey:.publicKey,endpoint:{host:.host,port:7900},metadata:{name:.friendlyName,roles:"Peer"}}' \
#   | jq -s '{knownPeers:.}' \
#   > $ROLE-node/userconfig/resources/peers-p2p.json
# chown "$USER": $ROLE-node/userconfig/resources/peers-p2p.json

# 設定ファイルの書き換えと更新
#   設定ファイル生成を先に済ませる
sudo -u $USER docker-compose -f docker-compose.yaml up --build generate-raw-addresses store-addresses update_vars
if [ -n "$FRIENDLY_NAME" ]; then
  sed -i.bak "/friendly_name/ s/[0-9A-Z]\{8\}/$FRIENDLY_NAME/" $ROLE-node/config-input.yaml
  # 設定ファイルの適用
  sudo -u $USER docker-compose -f docker-compose.yaml up --build update_vars
fi
if [ -n "$NODE_HOST" ]; then
  mv $ROLE-node/userconfig/resources/config-node.properties.template{,.bak}
  tr -d \\r < $ROLE-node/userconfig/resources/config-node.properties.template.bak | sed "/^host/ s/$/$NODE_HOST/" \
    > $ROLE-node/userconfig/resources/config-node.properties.template
fi

# symbolノードを常時起動させる設定
cat << __EOD__ > /etc/systemd/system/symbol.service
[Unit]
Description=Symbol Node Daemon
After=docker.service
[Service]
Type=simple
User=$USER
WorkingDirectory=$ASSEMBLY_HOME
Environment=COMPOSE_FILE=$ASSEMBLY_HOME/docker-compose.yaml
ExecStartPre=/usr/local/bin/docker-compose -f \$COMPOSE_FILE rm -v -f
ExecStartPre=/usr/local/bin/docker-compose -f \$COMPOSE_FILE down
ExecStart=/usr/local/bin/docker-compose -f \$COMPOSE_FILE up --build
ExecStop=/usr/local/bin/docker-compose -f \$COMPOSE_FILE stop
ExecStopPost=/usr/local/bin/docker-compose -f \$COMPOSE_FILE rm -v -f
ExecStopPost=/usr/local/bin/docker-compose -f \$COMPOSE_FILE down
ExecReload=/usr/local/bin/docker-compose -f \$COMPOSE_FILE restart
Restart=always
RestartSec=120s
[Install]
WantedBy=multi-user.target
__EOD__

# -------------------------------------------------------------

## HTTPサーバで外部からサーバ情報を確認できるような仕組み

sudo -u $USER mkdir -p htdocs/

# symbolノードのブロック高情報をファイルから取り出してheight.txtとして書き込むスクリプト
[ "$ROLE" = "peer" ] && DAT_PATH=data/index.dat || DAT_PATH=data/api-node/index.dat
cat << __EOD__ > height-write.sh
#!/bin/bash
cd \`dirname \$0\`
mkdir -p htdocs/chain
while true; do
  echo "ibase=16;\$(cat $DAT_PATH | xxd -p | fold -w2 | tac | tr -d '\n' | tr '[:lower:]' '[:upper:]')" \
    | bc | echo "{\"height\":\$(cat -)}" \
    > htdocs/chain/height.json
  cat htdocs/chain/height.json
  sleep 20
done
__EOD__
chmod +x height-write.sh && chown "$USER": height-write.sh

# -------------------------------------------------------------

# 情報を公開するためのサービス
cat << __EOD__ > /etc/systemd/system/sym-util.service
[Unit]
Description=Symbol Node Utility
After=symbol.service
[Service]
Type=simple
User=$USER
WorkingDirectory=$ASSEMBLY_HOME
ExecStartPre=/usr/bin/docker run --rm --name sym-util -t -v $ASSEMBLY_HOME/htdocs:/var/www/localhost/htdocs:ro -v $ASSEMBLY_HOME/lighttpd:/etc/lighttpd:ro -p $HTTPD_PORT:80 -d sebp/lighttpd
ExecStart=$ASSEMBLY_HOME/height-write.sh
ExecStopPost=/usr/bin/docker stop sym-util
Restart=always
RestartSec=120s
[Install]
WantedBy=multi-user.target
__EOD__

# lighttpd用コンフィグ
sudo -u $USER mkdir -p lighttpd/

cat << __EOD__ > lighttpd/lighttpd.conf
var.basedir  = "/var/www/localhost"
var.logdir   = "/var/log/lighttpd"
var.statedir = "/var/lib/lighttpd"
server.modules = ("mod_access","mod_accesslog","mod_auth")
include "mime-types.conf"
server.username      = "lighttpd"
server.groupname     = "lighttpd"
server.document-root = var.basedir + "/htdocs"
server.pid-file      = "/run/lighttpd.pid"
server.errorlog      = "/dev/pts/0"
server.indexfiles    = ("index.html","index.htm")
server.follow-symlink = "enable"
static-file.exclude-extensions = (".pl",".cgi",".fcgi")
accesslog.filename   = "/dev/pts/0"
dir-listing.activate = "enable"
url.access-deny = ("~",".inc")
server.network-backend = "writev"
auth.backend = "htdigest"
auth.backend.htdigest.userfile = "/etc/lighttpd/user.htdigest"
auth.require = ("/debug/"=>("method"=>"digest","realm"=>"debug","require"=>"valid-user"))
__EOD__

cat << __EOD__ > lighttpd/mime-types.conf
mimetype.assign = (
  ".svg"     => "image/svg+xml",
  ".svgz"    => "image/svg+xml",
  ".pdf"     => "application/pdf",
  ".sig"     => "application/pgp-signature",
  ".spl"     => "application/futuresplash",
  ".class"   => "application/octet-stream",
  ".ps"      => "application/postscript",
  ".torrent" => "application/x-bittorrent",
  ".dvi"     => "application/x-dvi",
  ".gz"      => "application/x-gzip",
  ".pac"     => "application/x-ns-proxy-autoconfig",
  ".swf"     => "application/x-shockwave-flash",
  ".tar.gz"  => "application/x-tgz",
  ".tgz"     => "application/x-tgz",
  ".tar"     => "application/x-tar",
  ".zip"     => "application/zip",
  ".dmg"     => "application/x-apple-diskimage",
  ".mp3"     => "audio/mpeg",
  ".m3u"     => "audio/x-mpegurl",
  ".wma"     => "audio/x-ms-wma",
  ".wax"     => "audio/x-ms-wax",
  ".ogg"     => "application/ogg",
  ".wav"     => "audio/x-wav",
  ".gif"     => "image/gif",
  ".jpg"     => "image/jpeg",
  ".jpeg"    => "image/jpeg",
  ".png"     => "image/png",
  ".xbm"     => "image/x-xbitmap",
  ".xpm"     => "image/x-xpixmap",
  ".xwd"     => "image/x-xwindowdump",
  ".css"     => "text/css",
  ".html"    => "text/html",
  ".htm"     => "text/html",
  ".js"      => "text/javascript",
  ".json"    => "application/json",
  ".asc"     => "text/plain",
  ".c"       => "text/plain",
  ".h"       => "text/plain",
  ".cc"      => "text/plain",
  ".cpp"     => "text/plain",
  ".hh"      => "text/plain",
  ".hpp"     => "text/plain",
  ".conf"    => "text/plain",
  ".log"     => "text/plain",
  ".text"    => "text/plain",
  ".txt"     => "text/plain",
  ".diff"    => "text/plain",
  ".patch"   => "text/plain",
  ".ebuild"  => "text/plain",
  ".eclass"  => "text/plain",
  ".rtf"     => "application/rtf",
  ".bmp"     => "image/bmp",
  ".tif"     => "image/tiff",
  ".tiff"    => "image/tiff",
  ".ico"     => "image/x-icon",
  ".dtd"     => "text/xml",
  ".xml"     => "text/xml",
  ".mpeg"    => "video/mpeg",
  ".mpg"     => "video/mpeg",
  ".mov"     => "video/quicktime",
  ".qt"      => "video/quicktime",
  ".avi"     => "video/x-msvideo",
  ".asf"     => "video/x-ms-asf",
  ".asx"     => "video/x-ms-asf",
  ".wmv"     => "video/x-ms-wmv",
  ".bz2"     => "application/x-bzip",
  ".tbz"     => "application/x-bzip-compressed-tar",
  ".tar.bz2" => "application/x-bzip-compressed-tar"
)
__EOD__

  # ダイジェスト認証
  printf "$USER:debug:$PSWD" | md5sum | cut -f1 -d" " | echo "$USER:debug:$(cat -)" > lighttpd/user.htdigest
  chown -R "$USER": lighttpd/
  DEBUG_DIR=htdocs/debug
  sudo -u $USER mkdir -p $DEBUG_DIR

if [ "$DEBUG" = "on" ]; then
  # ハードウェア情報出力
  lshw -json | sudo -u $USER tee -a $DEBUG_DIR/hardware.json

  # ログの定期コピー
  cat << __EOD__ > copy-logs.sh
#!/bin/bash
LOG_DIR=htdocs/debug/logs
APPORT_DIR=htdocs/debug/apport
cd \`dirname \$0\`
sudo -u $USER mkdir -p \$LOG_DIR
while true; do
  rsync -a --usermap=*:$USER --groupmap=*:$USER --chmod=F644,D775 /var/log/docker \$LOG_DIR/
  rsync -a --usermap=*:$USER --groupmap=*:$USER --chmod=F644,D775 data/debug/ \$APPORT_DIR/
  sleep 60
done
__EOD__
  chmod +x copy-logs.sh && chown "$USER": copy-logs.sh

  cat << __EOD__ > /etc/systemd/system/copy-logs.service
[Unit]
Description=Copy logs
After=symbol.service
[Service]
Type=simple
User=root
WorkingDirectory=$ASSEMBLY_HOME
ExecStart=$ASSEMBLY_HOME/copy-logs.sh
Restart=always
RestartSec=120s
[Install]
WantedBy=multi-user.target
__EOD__

  systemctl daemon-reload
  systemctl enable copy-logs && systemctl start copy-logs
fi

# -------------------------------------------------------------

# ブートストラップの常時起動設定とサービスの開始
systemctl daemon-reload
systemctl enable symbol && systemctl start symbol
systemctl enable sym-util && systemctl start sym-util

# -------------------------------------------------------------

## Ubuntu ---------------------------------------------------- {
apt-get clean -y && apt-get autoremove -y
dpkg -l 'linux-image-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge
update-grub
## }

## CentOS --------------------------------------------------- {
# # パッケージマネージャキャッシュ削除
# yum clean all
# # 古いカーネルを削除
# package-cleanup --oldkernels --count=1 -y
## }

# symbolサービスログ確認用
# journalctl -fu symbol
