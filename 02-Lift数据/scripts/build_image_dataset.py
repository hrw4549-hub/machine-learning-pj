from pathlib import Path
import argparse
import hashlib
import json
import os

import h5py
import numpy as np
from PIL import Image
import robosuite as suite
from tqdm import tqdm


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/raw/low_dim_v15.hdf5"
MANIFEST = ROOT / "splits/lift_ph_seed42.json"

CAMERAS = ["agentview", "robot0_eye_in_hand"]
SIZE = 128


def decode(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--limit", type=int, default=0,
        help="只处理前 N 条；默认 0 表示处理全部选中示范",
    )
    args = parser.parse_args()
    assert args.limit >= 0

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert sha256(SOURCE) == manifest["source_sha256"], (
        "原始文件与划分时的文件不一致。"
    )

    splits = manifest["splits"]
    selected = sorted(
        set(splits["train_50"]) | set(splits["valid"]) | set(splits["test"]),
        key=lambda name: int(name.split("_")[-1]),
    )
    if args.limit:
        selected = selected[:args.limit]

    tag = f"smoke_{args.limit}" if args.limit else "90demos"
    destination = ROOT / f"data/processed/lift_ph_image128_{tag}.hdf5"
    temporary = destination.with_suffix(".hdf5.partial")
    preview_dir = ROOT / f"previews/build_{tag}"

    destination.parent.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)

    assert not destination.exists(), (
        f"目标文件已存在，停止以避免覆盖：{destination}"
    )
    assert not temporary.exists(), (
        f"发现上次未完成的文件，请先检查：{temporary}"
    )

    env = None
    total_steps = 0
    max_joint_error = 0.0

    try:
        with h5py.File(SOURCE, "r") as src, h5py.File(temporary, "x") as dst:
            metadata = json.loads(decode(src["data"].attrs["env_args"]))
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

            env = suite.make(
                env_name=metadata["env_name"],
                **kwargs,
            )

            out_data = dst.create_group("data")
            for key, value in src["data"].attrs.items():
                out_data.attrs[key] = value

            metadata["env_kwargs"] = kwargs
            out_data.attrs["env_args"] = json.dumps(metadata)
            dst.attrs["source_sha256"] = manifest["source_sha256"]
            dst.attrs["split_manifest"] = json.dumps(manifest)
            dst.attrs["image_convention"] = (
                "RGB uint8 THWC; vertically flipped from sim.render. "
                "Apply the same convention at policy evaluation."
            )
            dst.attrs["generation_method"] = (
                "Render stored state[t]; preserve original obs[t] and actions[t]. "
                "No action playback validation."
            )
            dst.attrs["next_obs_note"] = (
                "Original low-dimensional next_obs retained; "
                "no next_obs images generated."
            )

            print(f"准备处理 {len(selected)} 条示范", flush=True)

            for demo_id in tqdm(selected, desc="示范进度"):
                demo = src["data"][demo_id]
                states = demo["states"][:]
                n = len(demo["actions"])
                assert len(states) == n

                ep_meta = demo.attrs.get("ep_meta")
                env.set_ep_meta(
                    json.loads(decode(ep_meta)) if ep_meta is not None else {}
                )
                env.reset()
                xml = env.edit_model_xml(decode(demo.attrs["model_file"]))
                env.reset_from_xml_string(xml)
                env.sim.reset()

                # 保留原始动作、低维观测、状态、奖励及示范属性。
                src.copy(demo, out_data, name=demo_id)
                out_demo = out_data[demo_id]
                out_demo.attrs["num_samples"] = n

                image_sets = {}
                for camera in CAMERAS:
                    key = camera + "_image"
                    assert key not in out_demo["obs"]
                    image_sets[camera] = out_demo["obs"].create_dataset(
                        key,
                        shape=(n, SIZE, SIZE, 3),
                        dtype=np.uint8,
                        chunks=(1, SIZE, SIZE, 3),
                        compression="gzip",
                        compression_opts=4,
                    )

                for t in range(n):
                    env.sim.set_state_from_flattened(states[t])
                    env.sim.forward()

                    if t in {0, n // 2, n - 1}:
                        obs = env._get_observations(force_update=True)
                        error = float(np.max(np.abs(
                            np.asarray(obs["robot0_joint_pos"])
                            - demo["obs/robot0_joint_pos"][t]
                        )))
                        assert np.isfinite(error) and error < 1e-5, (
                            f"{demo_id} 第 {t} 帧关节位置不匹配：{error}"
                        )
                        max_joint_error = max(max_joint_error, error)

                    for camera in CAMERAS:
                        image = env.sim.render(
                            width=SIZE,
                            height=SIZE,
                            camera_name=camera,
                        )
                        image = np.ascontiguousarray(image[::-1])

                        assert image.shape == (SIZE, SIZE, 3)
                        assert image.dtype == np.uint8
                        assert image.std() > 1.0, (
                            f"{demo_id}/{camera}/{t} 图像接近纯色"
                        )
                        image_sets[camera][t] = image

                        # 保存第一条示范的首尾双视角，方便检查。
                        if demo_id == selected[0] and t in {0, n - 1}:
                            Image.fromarray(image).save(
                                preview_dir / f"{demo_id}_{t}_{camera}.png"
                            )

                total_steps += n

            out_data.attrs["total"] = total_steps

            mask = dst.create_group("mask")
            selected_set = set(selected)
            for name in ["train_20", "train_50", "valid", "test"]:
                ids = [
                    demo_id for demo_id in splits[name]
                    if demo_id in selected_set
                ]
                mask.create_dataset(name, data=np.asarray(ids, dtype="S"))

            dst.attrs["complete"] = True
            dst.attrs["max_checked_joint_error"] = max_joint_error

        # 重新打开，检查所有示范的图像形状。
        with h5py.File(temporary, "r") as check:
            assert len(check["data"]) == len(selected)
            for demo_id in selected:
                n = len(check["data"][demo_id]["actions"])
                for camera in CAMERAS:
                    images = check["data"][demo_id]["obs"][camera + "_image"]
                    assert images.shape == (n, SIZE, SIZE, 3)
                    assert images.dtype == np.uint8

        os.replace(temporary, destination)

        print("\n生成及结构检查通过")
        print(f"示范数：{len(selected)}")
        print(f"总步数：{total_steps}")
        print(f"检查时刻的最大关节误差：{max_joint_error:.3e}")
        print(f"文件大小：{destination.stat().st_size / 1024**2:.2f} MiB")
        print(f"输出：{destination}")
        print(f"预览：{preview_dir}")
        print("注意：尚未验证动作回放；next_obs 中没有图像。")

    finally:
        if env is not None:
            env.close()


if __name__ == "__main__":
    main()