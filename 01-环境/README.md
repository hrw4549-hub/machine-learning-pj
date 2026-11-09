# 环境

此目录归档安装脚本、依赖锁定、ACT 上游源码包和原机器验收样例。先阅读 `安装说明.md` 与 `项目交接.md`。

交接记录：原机器 WSL2 Ubuntu 22.04、Python 3.10、MuJoCo 3.2.7、robosuite 1.5.1、Panda Lift 双相机与动作 smoke test 通过；ACT 仅以合成 14 维数据通过前向/反向检查，不代表 Lift 策略训练完成。

接手机器必须自行运行 `pj7-environment/Verify-Ubuntu.sh` 并保存新验收报告。Windows、Linux、macOS 依赖环境不可互相照搬。

