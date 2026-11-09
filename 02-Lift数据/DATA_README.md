# PJ7 Lift 数据交接说明

## 1. 数据来源

官方仓库：
https://huggingface.co/datasets/robomimic/robomimic_datasets

原始文件：
v1.5/lift/ph/low_dim_v15.hdf5

原始数据包含 200 条示范、9666 步。

原始文件 SHA256：
2067777cb8b532e9263dd09fd6448c41cc31224bb27be4a3b734010ae13eb540

## 2. 正式交付数据

文件：
data/processed/lift_ph_image128_90demos.hdf5

包含 90 条示范、4337 步。
两个相机共 8674 张图像。

正式文件 SHA256：
0924de350abc138d9b49be221512aa3f8eba8278acb46eee3311cc8d22549270

图像由原始示范保存的仿真状态逐帧恢复并渲染得到。
原始动作、状态、奖励、终止标记和低维观测均保持不变。

## 3. 数据划分

固定种子：42。
准确示范 ID 以 splits/lift_ph_seed42.json 为准。

| mask 名称 | 示范数 | 步数 |
|---|---:|---:|
| train_20 | 20 | 961 |
| train_50 | 50 | 2384 |
| valid | 20 | 1026 |
| test | 20 | 927 |

train_20 是 train_50 的子集。
train_50、valid、test 互不重叠。

valid 保留官方的 20 条验证示范。
test 是从官方 train 中划出的自定义离线测试集，
不是官方测试集，也不代替仿真闭环评测。

train_pool 的 160 条 ID 仅用于记录候选训练池，
正式图像文件只包含上述选中的 90 条示范。

注意：
官方 20_percent 和 50_percent 分别是 40、100 条，
与本项目的 train_20、train_50 不同。

## 4. 数据结构

每条示范位于 data/<demo_id>。

主要字段：
- actions：形状 (T, 7)
- states：原始 MuJoCo 保存状态
- obs/agentview_image：形状 (T, 128, 128, 3)
- obs/robot0_eye_in_hand_image：形状 (T, 128, 128, 3)
- obs/robot0_joint_pos：形状 (T, 7)
- obs/robot0_gripper_qpos：形状 (T, 2)
- 其他原始低维观测、rewards、dones、next_obs

图像类型为 uint8，RGB，取值范围 0～255。
next_obs 保留原始低维观测，没有图像。

通过 mask/train_20、mask/train_50、mask/valid、
mask/test 读取对应的示范 ID。
不能直接把 data 下的全部示范用于训练。

## 5. 环境及动作接口

任务：Lift
机器人：Panda
robosuite：1.5.1
MuJoCo：3.2.7
控制频率：20 Hz
lite_physics：false

复合控制器：BASIC
机械臂控制器：OSC_POSE
control_delta：true
input_ref_frame：world

动作共 7 维：
- 前 3 维：末端平移控制输入
- 中间 3 维：末端旋转控制输入
- 最后 1 维：夹爪控制输入

动作不是关节角度目标。
保留原始控制输入，由控制器执行范围映射，
不要提前乘输出缩放系数后再输入同一控制器。

完整控制器配置应读取 data.attrs["env_args"]，
不要用默认配置覆盖它。
夹爪开合方向应在动作回放验收时进一步确认。

## 6. 图像方向与训练读取

图像通过 sim.render 获取后执行 image[::-1]，
再保存为当前预览中使用的方向。

在线评测必须使用一致的图像方向。
如果使用其他封装的相机观测接口，应检查其是否已经翻转，
避免漏翻或重复翻转。

HDF5 图像布局为 THWC。
模型通常需要转换为通道在前的布局。
缩放、标准化和其他预处理由训练代码明确记录，
并在评测中保持一致。

建议状态输入：
7 维 robot0_joint_pos + 2 维 robot0_gripper_qpos，
共 9 维；该方案须由训练负责人最终确认。

动作输出为 7 维，不能直接沿用原始 ACT 的 14 维设置。

动作块从同一示范的 actions[t:t+K] 读取，
不得跨示范边界。
末尾不足 K 步时应补齐并设置有效位置掩码。

归一化统计量只能来自当前训练子集：
20 条实验使用 train_20；
50 条实验使用 train_50。
验证集与测试集不得参与统计量拟合。

## 7. 验收结果与边界

已经完成：
- 数据划分数量、步数和交集检查
- 原始数值数据一致性检查
- 全部图像读取、形状、类型及基础非纯色检查
- 每条示范起始、中间、最后状态的关节位置比较
- 示例相机图像人工检查

检查时刻的最大关节位置误差为 0。

尚未完成：
- 从初态连续执行原始动作的回放验收
- 所有图像逐帧人工检查
- ACT 数据加载器和模型适配
- ACT 训练及仿真闭环成功率评测

不能将保存状态渲染成功解释为动作回放成功，
也不能将官方专家示范解释为本组训练模型的结果。

## 8. 复现与相关文件

Mac 环境版本：
reports/requirements-macos.txt

数据划分记录：
splits/lift_ph_seed42.json

初步检查：
reports/initial_inspection.txt

正式数据验收：
reports/image_dataset_validation.json

示范预览脚本：
scripts/preview_demo.py

图像生成脚本：
scripts/build_image_dataset.py

生成图像前需准备官方原始文件和 splits 中的划分记录。

先进行小规模生成：
python scripts/build_image_dataset.py --limit 2

再生成正式数据：
python scripts/build_image_dataset.py

脚本会拒绝覆盖已有正式文件或未完成的 partial 文件。
复现时应使用新的工作目录。

Mac 环境清单用于记录依赖，
Windows/Linux 用户应沿用各自兼容的环境，
不能直接照搬 Mac 平台依赖清单。