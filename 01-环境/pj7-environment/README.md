# 第七题：WSL 环境安装与复现

用于机器人模仿学习第七题的 Lift 必做任务。环境安装已在本机通过功能验收，日期：2026-11-01。

## 已验证的环境

| 组件 | 版本 / 结果 |
|---|---|
| 系统 | WSL2，Ubuntu 22.04.5，x86_64 |
| Python | 3.10.22，独立 conda 环境 |
| PyTorch / torchvision | 2.5.1+cu121 / 0.20.1+cu121 |
| MuJoCo / robosuite | 3.2.7 / 1.5.1 |
| NumPy / dm-control | 1.26.4 / 1.0.27 |
| ACT 官方源码 | 742c753c0d4a5d87076c8f69e5628c79a8cc5488 |
| 本机显卡 | RTX 4070 Ti SUPER，CUDA 张量运算通过 |
| Lift 仿真 | EGL 离屏渲染、外部/手腕双相机、两次重置、每次 20 步动作通过 |
| ACT 计算 | GPU 前向、反向传播、一次优化更新、推理通过 |

验收使用随机动作和合成训练数据，确认软件可以运行；尚未采集 Lift 示范或训练出抓取策略。
ACT 官方模型使用 14 维状态/动作，而本次 Panda Lift 控制器是 7 维动作，仍需做任务适配。
原始报告和图片在 logs/verification-egl/、logs/verification-act.json。
安装包内 verified-example/ 是本机验收示例，其他机器必须重新验收。

## 本机以后怎么打开

Windows PowerShell：

```powershell
wsl -d Ubuntu-22.04 --cd ~
```

进入 Ubuntu 后：

```bash
source ~/pj7/activate.sh
cd ~/pj7
```

代码放 ~/pj7/src，数据放 ~/pj7/data，训练输出放 ~/pj7/runs。
这些 Linux 文件实际位于 D:\machine learning\.wsl\Ubuntu-22.04\ext4.vhdx 中。
Windows 安装脚本在 D:\machine learning\pj7-environment。
从 Linux 访问 Windows 项目目录使用 /mnt/project。
不要在 Ubuntu 运行期间直接移动或修改 ext4.vhdx。

重新验收本机：

```bash
bash /mnt/project/pj7-environment/Verify-Ubuntu.sh
```

## 给其他电脑安装的通用流程

适用 Windows 11 x86_64；BIOS/UEFI 开启虚拟化，建议至少 16GB 内存、30GB 可用空间。
有 NVIDIA 显卡时先安装支持 WSL 的 Windows 显卡驱动。
Ubuntu 内不用另外安装 NVIDIA 显示驱动或完整 CUDA Toolkit。
安装需要联网访问微软、GitHub、conda-forge、PyPI 和 PyTorch 软件源。
本套版本在上表机器通过验证，其他显卡/驱动以本机验收为准。

### 1. 解压并安装 WSL

将 PJ7-安装与交接.zip 解压到自己的项目文件夹，例如 E:\course-project，
进入解压后的 pj7-environment 文件夹打开 PowerShell。已有可用 WSL2 时跳到下一步。

```powershell
cd 'E:\course-project\pj7-environment'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Windows.ps1
```

将 `E:\course-project\pj7-environment` 换成自己的实际解压路径，路径有空格也保留引号。
`cd` 进入脚本文件夹，`.\` 表示当前文件夹。

按提示同意 UAC。脚本启用 WSL/虚拟机组件，缺少新版 WSL 时安装经 SHA256 和微软签名校验的 WSL 3.0.3；
已有可用新版 WSL 时沿用。脚本不自动重启，看到 reboot-required 后手动重启。
隐藏管理员窗口的进度可查 logs/windows-status.json。
Windows 如果报告组件损坏，应先自行修复；通用安装流程不自动启动系统修复。

### 2. 安装并初始化 Ubuntu

WSL 就绪并完成重启后，在同一文件夹运行：

```powershell
cd 'E:\course-project\pj7-environment'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-UbuntuDistribution.ps1
wsl -d Ubuntu-22.04 --cd ~
```

默认将发行版装到脚本文件夹上一级的 .wsl\Ubuntu-22.04，不放在盘符根目录。
也可传入 -InstallLocation 'E:\course-project\.wsl\Ubuntu-22.04'。
已有同名发行版时会沿用，不覆盖非空目录。
如果当前有不属于本项目的同名 Ubuntu，应先确认适合复用，或另选发行版名称。
首次启动创建自己的 Linux 用户名和密码，输入密码时不显示字符。
使用有 sudo 权限的普通用户安装 Python 环境。

### 3. 安装 Linux 依赖

在 Ubuntu 中进入解压文件夹，按实际盘符和目录修改：

```bash
cd '/mnt/e/course-project/pj7-environment'
bash Install-Ubuntu.sh
source ~/pj7/activate.sh
```

系统依赖阶段会请求自己的 sudo 密码。
脚本安装独立 Miniforge / Python 3.10，先安装指定 CUDA 版 PyTorch，
再安装 requirements-linux.lock.txt 中固定的完整 pip 版本。
requirements.txt 是主要依赖清单，完整锁文件优先使用。
ACT 从包内 act-source.bundle 恢复并核验 SHA256，再核对固定提交；许可证在 ACT-LICENSE。
缺少源码包时才从官方 GitHub 克隆，不覆盖不同提交的现有 ACT 源码。

默认位置为 ~/pj7 和 ~/.local/share/pj7-miniforge，均位于发行版虚拟磁盘内部。
需要变更时，首次安装前设置 PJ7_HOME、PJ7_CONDA_HOME，后续安装和验收使用同一设置。
不要把 Linux conda 环境复制给 Windows Python 使用。

### 4. 实际验收

在脚本文件夹内运行：

```bash
bash Verify-Ubuntu.sh
```

依次检查依赖、GPU 张量运算、Lift 双相机/重置/动作，以及 ACT GPU 训练计算。
通过标准：命令正常结束，logs/verification-egl/report.json 和 logs/verification-act.json
的 passed 都为 true，相机 PNG 能看清桌面、方块或机器人。

EGL 不可用时可尝试软件渲染，PyTorch 仍使用 GPU：

```bash
PJ7_GL=osmesa bash Verify-Ubuntu.sh
```

没有 NVIDIA 显卡时，仅做 CPU 仿真检查：

```bash
source ~/pj7/activate.sh
python verify_environment.py --gl osmesa --allow-cpu --output logs/verification-cpu
```

CPU 模式的 cuda_available 为 false，不算 GPU/ACT 训练验收通过。
robosuite 关于可选机器人模型、GR1 IK、私有 macros 的警告不影响本套 Panda Lift 检查。

## 本机磁盘挂载兼容处理

本机整个 D 盘挂载失败，但项目子文件夹能挂载，已通过 /etc/fstab 持久挂载到 /mnt/project。
因此本机进入脚本目录使用 cd /mnt/project/pj7-environment。
启动时可能仍出现 D 盘与 Windows PATH 翻译警告；本机验收在这些提示存在时已通过。
其他机器通常直接使用 /mnt/d/... 或 /mnt/e/...，无需照做。

如其他机器确有相同问题，可在 Ubuntu 手动挂载项目文件夹，再运行兼容脚本：

```bash
sudo mkdir -p /mnt/project
sudo mount -t drvfs 'E:\course-project' /mnt/project
sudo bash /mnt/project/pj7-environment/Configure-ProjectMount.sh 'E:\course-project'
```

脚本备份 fstab 后添加项目挂载项。这是可选步骤。

## 后续第七题开发与共享机器

下一阶段是固定 Panda Lift 的控制器、相机、观测与动作定义，采集示范，适配 ACT 数据加载与模型维度，
再训练和闭环评估。可比较 20/50 条示范或动作执行长度，保持测试初态和成功标准一致。
不要把 ACT 旧 README 的 MuJoCo 2.3.7 / dm-control 1.0.14 混装进本环境。
robosuite 不自带标准 Push-T，选做时需另行实现或接入。

小组后续可通过 SSH / VS Code Remote - SSH 使用这台机器，同局域网用内网地址，异地可使用 Tailscale 等组网工具。
每人独立账号/代码/输出，共享示范数据，单张显卡排队训练，用 tmux 保持任务运行。
当前没有配置远程账号、远程入口或公网端口，别人暂时不能直接远程登录。

## 文件与来源

- Install-Windows.ps1、Install-UbuntuDistribution.ps1：Windows/发行版安装。
- Install-SystemPackages.sh、Install-Ubuntu.sh：Ubuntu 系统依赖与独立 Python 环境。
- Verify-Ubuntu.sh、verify_environment.py、verify_act.py：功能验收。
- requirements-linux.lock.txt：固定 pip 版本；logs/ 保存安装和验收结果。
- act-source.bundle、ACT-LICENSE：固定官方源码与许可证。

官方参考：

- https://learn.microsoft.com/windows/wsl/install
- https://github.com/microsoft/WSL/releases/tag/3.0.3
- https://github.com/conda-forge/miniforge/releases/tag/25.3.1-0
- https://robosuite.ai/docs/installation.html
- https://github.com/ARISE-Initiative/robosuite/tree/v1.5.1
- https://github.com/tonyzhaozh/act
