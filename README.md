## Overview

VPNに接続したマシンがホームネットワーク内の特定のマシンに起動中のサービスにアクセスできるようにします。

構成は下記のようになります。

┌──VPN────────────────────────────────────────┐<br>
│                                             │<br>
│ A.VPN Sever(203.0.113.50) ◄── C.VPN Client  │<br>
│     ▲  (10.42.42.1:8097)                    │<br>
└─────┼───────────────────────────────────────┘<br>
      │                                        <br>
      │SSH Forwarding(:8097)                   <br>
      │                                        <br>
┌─B.Home Network──────────────────────────────┐<br>
│     │                                       │<br>
│    Server1(192.168.1.10)                    │<br>
│                                             │<br>
│    Server2(192.168.1.20:8097)               │<br>
│                                             │<br>
└─────────────────────────────────────────────┘<br>

本手順ではホームネットワーク内のjellyfinの起動しているサーバー(192.168.1.20:8097)に外出先からアクセスするというシナリオで説明を進めます。

## System Architecrure

* A. VPN サーバー(203.0.113.50 username: ubuntu)
  AWS、GCP、Oracle、さくらなどのLinuxマシン
  任意のクラウド（AWS・GCP など）を利用できます。
* B. ホームネットワーク
  Server1(Linux 192.168.1.10)
  Server2(Linux 192.168.1.20:8097)
* C. VPN クライアント
  Linux / Android

ABCともにOSはUbuntuを前提としていますが、他のLinuxディストロでもおおむね動作します。

## Installation and Configuration

### A. VPN サーバー


1. VPSを用意します、この説明ではOracle Cloudのコンピュートインスタンス(Ubuntu)を前提に話をすすめますが、AWSでもGCPでもさくらのクラウドでも特に変わりはないと思います。作成したマシのIPは203.0.113.50、ユーザー名はubuntuとして話を進めます。

2. VPSにsshでログインしパッケージのアップデートとインストールを行います
```bash
# パッケージのアップデート
$ sudo apt update
$ sudo apt upgrade

# 使用する可能性のあるパッケージをインストール
$ sudo apt install git vim curl wget htop ncdu lsof

# dockerのインストール
下記公式に従ってインストール
https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

```

3. wireguard-easyのインストールと設定
```bash
# ネットワークを設定
$ docker network create \
  --driver=bridge \
  --subnet=10.42.42.0/24 \
  --ipv6 \
  --subnet=fdcc:ad94:bacf:61a3::/64 \
  --opt com.docker.network.bridge.name=wg0 \
wg

# このレポジトリのwgをホーム（~）に持ってくる
$ git clone <this repository url>
$ cd <cloned repository dir>
$ cd wg
# compose.ymlの編集
$ vim compose.yml
<VPS external IP> をVPSの外部IPに書き換えるこの例だと203.0.113.50
```

4. nginxの設定
```bash
# init.shに実行権限を付与
$ chmow +x init.sh

# 公開ポートの編集
$ vim default.conf
server内のlistenに設定するポートを記述
listen < port 1 >; # 例listen 8097;
いらないlistenの行は消す
ポートは自由に変更可能だが、説明を簡易にするためjellyfinならデフォルトポートである8097で話を進める
```

5. wg-easyコンテナの起動と、コンテナ内nginxの起動
```bash
$ docker compose -f compose.yml up -d
$ docker compose -f compose.yml exec -d wg-eash sh /usr/local/bin/init.sh
```

6. ホスト側の設定変更
```bash
# sysctlでの設定変更
$ sudo vim /etc/sysctl.d/99-sysctl.conf
## 下記に変更
net.ipv4.ip_forward=1
$ sysctl -p /etc/sysctl.d/

# ssh設定の変更
$ sudo vim /etc/ssh/sshd_config
## 下記に変更
GatewayPorts yes
AllowTcpForwarding yes

$ sudo systemctl restart ssh

# iptablesの設定
$ sudo apt install iptables-persistent
$ sudo iptables -I INPUT 1 -i wg0 -j ACCEPT
$ sudo iptables -I INPUT 2 -i wg0 -p icmp -j ACCEPT
$ sudo netfilter-persistent save
```

### B. ホームネットワーク側の設定

ホームネットワーク内のServer1（Ubuntuを想定）を使用。IPは192.168.1.10とする。

1. ホームネットワーク内のサーバーのパッケージのアップデートとdockerのインストール
```bash
# パッケージのアップデート
$ sudo apt update
$ sudo apt upgrade

# 使用する可能性のあるパッケージをインストール
$ sudo apt install git vim curl wget htop ncdu lsof

# dockerのインストール
下記公式に従ってインストール
https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
```

2. sshの設定
```
$ ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
$ cat ~/.ssh/id_rsa.pub
表示された文字列をA. VPN サーバー側の~/.ssh/authrized_keysに追記する

下記でつながるか確認
$ ssh -i ~/.ssh/id_rsa ubuntu@<VPNサーバーのIP>
```

3. このレポジトリのssh-tunnelを~/ssh-tunnelにコピーしてVPN内に公開したいサービスの設定をして起動
```bash
$ git clone <this repository url>
$ cd <cloned respsitory dir>
# ホームネットワーク内のVPN内に公開したいサービスのIPとポートを設定する
$ vim ./ssh-tunnel/compose.ssh.yml
# jellyfinの起動しているサーバーが192.168.1.20でWebサービスが起動しているサーバーが192.168.1.30でポートが3000の場合は下記のようになる
PORT_FORWARD_LIST: < port forward list> #例"8097:192.168.1.20:8097,3000:192.168.1.30:3000"
# 下記も編集 VPNサーバーのユーザー名と外部IPを設定
SSH_USER: <username> # 例 "ubuntu"
SSH_SERVER: <server's IP> # 例 "203.0.113.50"



# dockerの起動 VPNサーバーとホームネットワークにSSHトンネルが作られる
$ docker compose -f ~/ssh-tunnel/compose.ssh.yml up -d
```

### C. VPN クライアントの追加と設定（初回はホームネットワーク内である必要アリ）

ホームネットワーク内にあるLinuxマシン（Ubuntu Desktopを想定）で行う

1. ホームネットワーク内で192.168.1.10:51821(Server1)にブラウザでアクセスするとwireguard-easyの設定画面になる
2. Newボタンでクライアント用の設定を作成
3. ダウンロードボタンで設定をダウンロードする（<設定した名前>.confと言うファイルになる）
4. ダウンロードした<設定した名前>.confをホーム（~）にコピー
5. wireguardのインストールと起動
```bash
$ sudo apt install wireguard
$ cd ~
$ cp ./<設定した名前>.conf /etc/wireguard/wg0.conf
# IPv4 over IPv6環境の場合下記を追記
$ sudo vim /etc/wireguard/wg0.conf
[Interface]内に下記を追記して保存
MTU = 1280

$ wg-quick up wg0
```
6. ブラウザで10.42.42.1:8097でjellyfinが表示されるのを確認する、表示されればホームネットワーク外の外出先でも`wg-quick up wg0`で10.42.42.1:8097でjellyfinにアクセスできる

7. Androidの場合は`WireGuard`を`PlayStore`からインストールして、WireGuardのアプリ画面からwireguard-easyの設定画面上のQRコードの読み込みですぐ設定が可能


VPNサーバー側のwireguard-easy用のcompose.ymlは下記を参照しました。
* https://qiita.com/dxa/items/0fc38c368b1847918035
* https://github.com/wg-easy/wg-easy/blob/badae8b8e4523ff644da80809c2a4a6cc065f320/docker-compose.yml
