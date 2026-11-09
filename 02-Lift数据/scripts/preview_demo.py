from pathlib import Path
import json

import h5py
import numpy as np
from PIL import Image
import robosuite as suite


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data/raw/low_dim_v15.hdf5"
OUTPUT = ROOT / "previews/demo_0"
CAMERAS = ["agentview", "robot0_eye_in_hand"]
SIZE = 128


def decode_text(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    env = None
    records = []

    try:
        with h5py.File(DATA_PATH, "r") as f:
            metadata = json.loads(
                decode_text(f["data"].attrs["env_args"])
            )
            demo = f["data/demo_0"]

            assert "model_file" in demo.attrs, (
                "demo_0 缺少 model_file，无法恢复原始场景。"
            )
            model_xml = decode_text(demo.attrs["model_file"])
            states = demo["states"][:]

            kwargs = dict(metadata["env_kwargs"])
            kwargs.update(
                has_renderer=False,
                has_offscreen_renderer=True,
                use_camera_obs=True,
                camera_names=CAMERAS,
                camera_heights=SIZE,
                camera_widths=SIZE,
                camera_depths=False,
            )

            print("正在创建数据对应的 Lift 环境……", flush=True)
            env = suite.make(
                env_name=metadata["env_name"],
                **kwargs,
            )

            # 保留数据中可能存在的 episode 元信息。
            ep_meta = demo.attrs.get("ep_meta")
            env.set_ep_meta(
                json.loads(decode_text(ep_meta))
                if ep_meta is not None else {}
            )

            env.reset()

            # 修正模型资源路径，再恢复该示范对应的场景。
            xml = env.edit_model_xml(model_xml)
            env.reset_from_xml_string(xml)
            env.sim.reset()

            indices = [
                ("start", 0),
                ("middle", len(states) // 2),
                ("last", len(states) - 1),
            ]

            for label, index in indices:
                print(
                    f"恢复 {label}：第 {index} 个保存状态",
                    flush=True,
                )

                env.sim.set_state_from_flattened(states[index])
                env.sim.forward()

                # 强制更新观测，检查恢复后的关节位置。
                obs = env._get_observations(force_update=True)
                expected = demo["obs/robot0_joint_pos"][index]
                actual = np.asarray(obs["robot0_joint_pos"])
                joint_error = float(
                    np.max(np.abs(actual - expected))
                )

                record = {
                    "label": label,
                    "state_index": index,
                    "joint_position_max_abs_error": joint_error,
                    "images": [],
                }

                print(f"关节位置最大误差：{joint_error:.3e}")

                for camera in CAMERAS:
                    pixels = env.sim.render(
                        width=SIZE,
                        height=SIZE,
                        camera_name=camera,
                    )

                    # 底层渲染图像上下翻转后保存为正常显示方向。
                    pixels = np.ascontiguousarray(pixels[::-1])

                    assert pixels.shape == (SIZE, SIZE, 3)
                    assert pixels.dtype == np.uint8
                    assert pixels.std() > 1.0, (
                        f"{camera} 图像接近纯色，请检查渲染。"
                    )

                    filename = f"{label}_{camera}.png"
                    Image.fromarray(pixels).save(OUTPUT / filename)
                    record["images"].append(filename)

                records.append(record)

        report = {
            "demo": "demo_0",
            "preview_resolution": [SIZE, SIZE],
            "cameras": CAMERAS,
            "records": records,
            "note": (
                "Saved-state restoration preview only; "
                "action playback and policy success are not tested."
            ),
        }
        (OUTPUT / "preview_report.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        print(f"\n预览生成完成：{OUTPUT}")
        print("请检查 6 张 PNG，确认视角、方向及方块位置。")

    finally:
        if env is not None:
            env.close()


if __name__ == "__main__":
    main()