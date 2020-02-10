# sym-node-setup

Automatically setting up Symbol Testnet node script for Ubuntu 16.04.

- [nemfoundation/symbol\-testnet\-bootstrap](https://github.com/nemfoundation/symbol-testnet-bootstrap)


## Usage

Paste script into startup script on your Cloud Service.

or

execute following command on your server machine.

```shell
# setup peer node
$ curl -s https://raw.githubusercontent.com/44uk/sym-node-setup/master/roles/sym-peer-setup.sh | bash
# setup api node
$ curl -s https://raw.githubusercontent.com/44uk/sym-node-setup/master/roles/sym-api-setup.sh | bash
# setup api-harvest node
$ curl -s https://raw.githubusercontent.com/44uk/sym-node-setup/master/roles/sym-api-harvest-setup.sh | bash
```

*MAKE SURE YOU UNDERSTAND WHAT HAPPENS BEFORE EXECUTE IT.*


## Debug info

http://_your_node_:50080

- `/chain/height.json` current node height
- `/debug/apport/` apport files
- `/debug/logs/` docker log files
- `/debug/hardware.json` result of lshw

`debug/` protected by digest authentication.
You can pass a set of USER and PSWD.


## Ports

Allow outbound transport.

- 7900 peer
- 7902 broker (on setup API)
- 3000 rest-gateway (on setup API)
- 50022 sshd
- 50080 httpd


## Configuration

```shell
DEBUG=on # enable setting up debug info
USER=symbol # user name
PSWD=symbol # user password
SSHD_PORT=50022
HTTPD_PORT=50080
DOCKER_COMPOSE_VER=1.25.4
BOOTSTRAP_TAG=0.9.2.1-beta4
ASSEMBLY=peer # peer, api, api-harvest
FRIENDLY_NAME= # set name as you like
NODE_HOST=
```
