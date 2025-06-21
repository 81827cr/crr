## Linux 管理面板

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/panel.sh -o ./panel.sh && chmod +x ./panel.sh && ./panel.sh
```



## 虚拟空间设置
```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/set_swap.sh -o ./set_swap.sh && bash ./set_swap.sh && rm -f ./set_swap.sh
```



## Linux 一键安全检查

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/linux_security_check.sh -o ./linux_security_check.sh && bash ./linux_security_check.sh && rm -f ./linux_security_check.sh
```



## 端口转发设置

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/port_forward.sh -o ./port_forward.sh && bash ./port_forward.sh && rm -f ./port_forward.sh
```



## caddy反代设置

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/setup_caddy.sh -o ./setup_caddy.sh && bash ./setup_caddy.sh && rm -f ./setup_caddy.sh
```

## 开启bbr

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/tcp.sh -o ./tcp.sh && bash ./tcp.sh && rm -f ./tcp.sh
```



## 禁用 PHP 高危函数列表

```
exec,passthru,shell_exec,system,proc_open,popen,show_source,eval,assert,putenv,pcntl_exec,phpinfo
```

