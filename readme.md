## Linux 管理面板脚本

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/panel.sh -o ./panel.sh && bash ./panel.sh
```



## 虚拟空间设置
```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/set_swap.sh -o ./set_swap.sh && bash ./set_swap.sh && rm -f ./set_swap.sh
```



## Linux 一键安全检查脚本

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/linux_security_check.sh -o ./linux_security_check.sh && bash ./linux_security_check.sh && rm -f ./linux_security_check.sh
```



## 端口转发脚本

```
curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/port_forward.sh -o ./port_forward.sh && bash ./port_forward.sh && rm -f ./port_forward.sh
```



## 禁用 PHP 高危函数列表

```
exec,passthru,shell_exec,system,proc_open,popen,show_source,eval,assert,putenv,pcntl_exec,phpinfo
```

