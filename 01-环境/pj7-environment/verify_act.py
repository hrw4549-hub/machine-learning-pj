"""Verify official ACT GPU forward/backward using synthetic 14D data.

This checks the upstream model runtime, not a trained Lift policy. No weights download.
"""
import argparse
import json
from pathlib import Path
from unittest.mock import patch

import torch


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("verification-act.json"))
    options = parser.parse_args()
    options.output.parent.mkdir(parents=True, exist_ok=True)
    report = {"passed": False, "input": "synthetic data, upstream 14-dimensional state/action", "pretrained_weights": False}
    try:
        from detr.main import get_args_parser
        from detr.models import build_ACT_model

        assert torch.cuda.is_available(), "CUDA unavailable"
        torch.manual_seed(42)
        args = get_args_parser().parse_args([
            "--ckpt_dir", str(options.output.parent), "--policy_class", "ACT",
            "--task_name", "environment_check", "--seed", "42", "--num_epochs", "1",
        ])
        args.camera_names = ["agentview"]
        args.hidden_dim = 64
        args.dim_feedforward = 256
        args.enc_layers = 1
        args.dec_layers = 1
        args.nheads = 4
        args.num_queries = 5
        with patch("detr.models.backbone.is_main_process", return_value=False):
            model = build_ACT_model(args).cuda()
        optimizer = torch.optim.AdamW(model.parameters(), lr=1e-5)
        qpos = torch.randn(2, 14, device="cuda")
        images = torch.rand(2, 1, 3, 64, 64, device="cuda")
        target = torch.randn(2, 5, 14, device="cuda")
        mask = torch.zeros(2, 5, dtype=torch.bool, device="cuda")
        model.train()
        predicted, _, (mu, logvar) = model(qpos, images, None, target, mask)
        kl = -0.5 * (1 + logvar - mu.square() - logvar.exp()).mean()
        loss = (predicted - target).abs().mean() + kl
        assert torch.isfinite(loss).item()
        loss.backward()
        gradients = [param.grad for param in model.parameters() if param.grad is not None]
        assert gradients and all(torch.isfinite(grad).all().item() for grad in gradients)
        optimizer.step()
        model.eval()
        with torch.no_grad():
            actions, _, _ = model(qpos, images, None)
        torch.cuda.synchronize()
        assert actions.shape == (2, 5, 14), actions.shape
        assert torch.isfinite(actions).all().item()
        report.update(passed=True, gpu=torch.cuda.get_device_name(0), loss=float(loss.detach()),
                      prediction_shape=list(actions.shape), finite_gradient_tensors=len(gradients),
                      optimizer_steps=1, inference="passed")
        print(json.dumps(report, indent=2))
    except Exception as exc:
        report["error"] = repr(exc)
        raise
    finally:
        options.output.write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
