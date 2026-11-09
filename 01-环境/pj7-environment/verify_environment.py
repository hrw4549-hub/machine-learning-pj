"""Check CUDA, Lift camera observations, action stepping, and reset.

Run inside the installed Ubuntu environment. ACT-to-Lift integration is separate.
"""
import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gl", choices=["glfw", "egl", "osmesa"], default="egl")
    parser.add_argument("--output", type=Path, default=Path("verification"))
    parser.add_argument("--allow-cpu", action="store_true")
    args = parser.parse_args()
    os.environ["MUJOCO_GL"] = args.gl
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"python": sys.version, "platform": platform.platform(), "gl": args.gl, "passed": False}
    report_path = args.output / "report.json"
    env = None
    try:
        import numpy as np
        import torch
        import robosuite as suite
        from PIL import Image

        packages = ["torch", "torchvision", "numpy", "mujoco", "robosuite", "h5py", "dm-control"]
        report["versions"] = {name: importlib.metadata.version(name) for name in packages}
        report["cuda_available"] = torch.cuda.is_available()
        if not report["cuda_available"] and not args.allow_cpu:
            raise RuntimeError("CUDA is unavailable; fix GPU access or use --allow-cpu for simulation-only testing.")
        if report["cuda_available"]:
            report["gpu"] = torch.cuda.get_device_name(0)
            x = torch.randn(512, 512, device="cuda")
            y = x @ x.T
            torch.cuda.synchronize()
            assert torch.isfinite(y).all().item()
        env = suite.make(
            env_name="Lift", robots="Panda", has_renderer=False,
            has_offscreen_renderer=True, use_camera_obs=True,
            camera_names=["agentview", "robot0_eye_in_hand"],
            camera_heights=128, camera_widths=128, control_freq=20, horizon=100,
        )
        rng = np.random.default_rng(42)
        reset_checks = []
        for episode in range(2):
            obs = env.reset()
            for camera in ["agentview", "robot0_eye_in_hand"]:
                image = obs[camera + "_image"]
                assert image.shape == (128, 128, 3), image.shape
                assert image.std() > 1.0, "Camera image appears blank."
                Image.fromarray(np.flipud(image)).save(args.output / f"reset{episode}_{camera}.png")
            low, high = env.action_spec
            for _ in range(20):
                action = np.clip(rng.normal(0, 0.03, size=low.shape), low, high)
                action[-1] = low[-1]  # Keep the gripper open during this smoke check.
                obs, reward, done, info = env.step(action)
                assert np.isfinite(obs["robot0_proprio-state"]).all()
            reset_checks.append({"episode": episode, "steps": 20, "action_dim": len(low)})
        report["lift"] = reset_checks
        try:
            import policy  # ACT policy and model imports; no pretrained download or training.
            assert hasattr(policy, "ACTPolicy")
            report["act_import"] = "passed"
        except Exception as exc:
            report["act_import"] = repr(exc)
            raise RuntimeError("ACT import failed; source ~/pj7/activate.sh before verifying.") from exc
        report["passed"] = True
        print(json.dumps(report, indent=2, ensure_ascii=False))
    except Exception as exc:
        report["error"] = repr(exc)
        raise
    finally:
        try:
            if env is not None:
                env.close()
        finally:
            report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
