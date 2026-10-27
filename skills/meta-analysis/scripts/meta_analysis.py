#!/usr/bin/env python3
"""Dependency-free basic meta-analysis for independent study-level effects."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import tempfile
from html import escape
from pathlib import Path
from statistics import NormalDist


class MetaAnalysisError(ValueError):
    """Raised when data or requested analysis violates the input contract."""


def _gammaincc(a: float, x: float) -> float:
    """Regularized upper incomplete gamma Q(a, x)."""
    if a <= 0 or x < 0:
        raise ValueError("invalid gamma arguments")
    if x == 0:
        return 1.0
    eps, fpmin, itmax = 3e-14, 1e-300, 1000
    gln = math.lgamma(a)
    if x < a + 1.0:
        ap, term, total = a, 1.0 / a, 1.0 / a
        for _ in range(itmax):
            ap += 1.0
            term *= x / ap
            total += term
            if abs(term) < abs(total) * eps:
                p = total * math.exp(-x + a * math.log(x) - gln)
                return min(1.0, max(0.0, 1.0 - p))
        raise ArithmeticError("gamma series did not converge")
    b = x + 1.0 - a
    c, d, h = 1.0 / fpmin, 1.0 / b, 1.0 / b
    for i in range(1, itmax + 1):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        if abs(d) < fpmin:
            d = fpmin
        c = b + an / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            q = math.exp(-x + a * math.log(x) - gln) * h
            return min(1.0, max(0.0, q))
    raise ArithmeticError("gamma continued fraction did not converge")


def chi2_sf(x: float, df: int) -> float:
    if df <= 0:
        raise ValueError("df must be positive")
    return _gammaincc(df / 2.0, max(0.0, x) / 2.0)


def _betacf(a: float, b: float, x: float) -> float:
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < 1e-300:
        d = 1e-300
    d = 1.0 / d
    h = d
    for m in range(1, 401):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        c = 1.0 + aa / c
        if abs(d) < 1e-300:
            d = 1e-300
        if abs(c) < 1e-300:
            c = 1e-300
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        c = 1.0 + aa / c
        if abs(d) < 1e-300:
            d = 1e-300
        if abs(c) < 1e-300:
            c = 1e-300
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 3e-14:
            return h
    raise ArithmeticError("beta continued fraction did not converge")


def regularized_beta(x: float, a: float, b: float) -> float:
    if not 0.0 <= x <= 1.0 or a <= 0 or b <= 0:
        raise ValueError("invalid beta arguments")
    if x in (0.0, 1.0):
        return x
    bt = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
                  + a * math.log(x) + b * math.log1p(-x))
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def student_t_cdf(t: float, df: int) -> float:
    if df <= 0:
        raise ValueError("df must be positive")
    if t == 0:
        return 0.5
    x = df / (df + t * t)
    tail2 = regularized_beta(x, df / 2.0, 0.5)
    return 1.0 - tail2 / 2.0 if t > 0 else tail2 / 2.0


def student_t_ppf(p: float, df: int) -> float:
    if not 0.0 < p < 1.0:
        raise ValueError("p must be between 0 and 1")
    if p == 0.5:
        return 0.0
    if p < 0.5:
        return -student_t_ppf(1.0 - p, df)
    lo, hi = 0.0, 1.0
    while student_t_cdf(hi, df) < p:
        hi *= 2.0
        if hi > 1e8:
            raise ArithmeticError("t quantile bracket failed")
    for _ in range(120):
        mid = (lo + hi) / 2.0
        if student_t_cdf(mid, df) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def load_effects(path: Path) -> list[dict[str, float | str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fields = set(reader.fieldnames or [])
            if not {"study_id", "yi"}.issubset(fields) or not ({"vi", "sei"} & fields):
                raise MetaAnalysisError("CSV requires study_id, yi, and vi or sei")
            rows = []
            seen: set[str] = set()
            for line_no, row in enumerate(reader, 2):
                sid = (row.get("study_id") or "").strip()
                if not sid:
                    raise MetaAnalysisError(f"line {line_no}: empty study_id")
                if sid in seen:
                    raise MetaAnalysisError(f"line {line_no}: duplicate study_id {sid!r}; correlated effects need a different model")
                seen.add(sid)
                try:
                    yi = float(row.get("yi", ""))
                    vi_text = (row.get("vi") or "").strip()
                    sei_text = (row.get("sei") or "").strip()
                    vi = float(vi_text) if vi_text else float(sei_text) ** 2
                    if vi_text and sei_text and not math.isclose(vi, float(sei_text) ** 2, rel_tol=1e-6, abs_tol=1e-12):
                        raise MetaAnalysisError(f"line {line_no}: vi and sei^2 disagree")
                except MetaAnalysisError:
                    raise
                except (TypeError, ValueError) as exc:
                    raise MetaAnalysisError(f"line {line_no}: yi/vi/sei must be numeric") from exc
                if not math.isfinite(yi) or not math.isfinite(vi) or vi <= 0:
                    raise MetaAnalysisError(f"line {line_no}: yi must be finite and variance must be finite and positive")
                rows.append({"study_id": sid, "yi": yi, "vi": vi})
    except OSError as exc:
        raise MetaAnalysisError(f"cannot read input: {exc}") from exc
    if len(rows) < 2:
        raise MetaAnalysisError("meta-analysis requires at least two independent studies")
    return rows


def weighted_fit(rows: list[dict[str, float | str]], tau2: float) -> tuple[float, float, list[float], float]:
    weights = [1.0 / (float(r["vi"]) + tau2) for r in rows]
    sw = sum(weights)
    mu = sum(w * float(r["yi"]) for w, r in zip(weights, rows)) / sw
    q = sum(w * (float(r["yi"]) - mu) ** 2 for w, r in zip(weights, rows))
    return mu, math.sqrt(1.0 / sw), weights, q


def tau2_dl(rows: list[dict[str, float | str]]) -> float:
    _, _, weights, q = weighted_fit(rows, 0.0)
    c = sum(weights) - sum(x * x for x in weights) / sum(weights)
    return max(0.0, (q - (len(rows) - 1)) / c) if c > 0 else 0.0


def _bracket_and_bisect(score, initial: float = 1.0) -> tuple[float, bool]:
    if score(0.0) <= 0:
        return 0.0, True
    low, high = 0.0, max(initial, 1e-12)
    for _ in range(100):
        if score(high) <= 0:
            break
        high *= 2.0
    else:
        return high, False
    for _ in range(200):
        mid = (low + high) / 2.0
        value = score(mid)
        if abs(value) < 1e-11 or high - low < 1e-12 * max(1.0, high):
            return mid, True
        if value > 0:
            low = mid
        else:
            high = mid
    return (low + high) / 2.0, False


def tau2_pm(rows: list[dict[str, float | str]]) -> tuple[float, bool]:
    df = len(rows) - 1
    return _bracket_and_bisect(lambda tau: weighted_fit(rows, tau)[3] - df, tau2_dl(rows) or 1.0)


def tau2_reml(rows: list[dict[str, float | str]]) -> tuple[float, bool]:
    def score(tau: float) -> float:
        mu, _, weights, _ = weighted_fit(rows, tau)
        residual = sum((weight * weight) * (float(row["yi"]) - mu) ** 2
                       for weight, row in zip(weights, rows))
        return residual - sum(weights) + sum(x * x for x in weights) / sum(weights)
    return _bracket_and_bisect(score, tau2_dl(rows) or 1.0)


def analyze(rows: list[dict[str, float | str]], model: str = "random", tau_method: str = "reml",
            ci_method: str = "hksj", alpha: float = 0.05) -> dict:
    if not 0 < alpha < 1:
        raise MetaAnalysisError("alpha must be between 0 and 1")
    k, df = len(rows), len(rows) - 1
    common_mu, common_se, _, q = weighted_fit(rows, 0.0)
    i2 = max(0.0, (q - df) / q * 100.0) if q > 0 else 0.0
    converged = True
    if model == "common":
        tau2, tau_method_used = 0.0, "not_applicable"
    elif tau_method == "dl":
        tau2, tau_method_used = tau2_dl(rows), "dl"
    elif tau_method == "pm":
        tau2, converged = tau2_pm(rows)
        tau_method_used = "paule_mandel"
    elif tau_method == "reml":
        tau2, converged = tau2_reml(rows)
        tau_method_used = "reml"
    else:
        raise MetaAnalysisError(f"unsupported tau method: {tau_method}")
    mu, base_se, weights, residual_q = weighted_fit(rows, tau2)
    if ci_method == "z":
        se, critical, interval_method = base_se, NormalDist().inv_cdf(1 - alpha / 2), "z"
    elif ci_method in {"hksj", "modified-hksj"}:
        scale = residual_q / df
        if ci_method == "modified-hksj":
            scale = max(1.0, scale)
        se = math.sqrt(scale / sum(weights))
        critical = student_t_ppf(1 - alpha / 2, df)
        interval_method = ci_method
    else:
        raise MetaAnalysisError(f"unsupported CI method: {ci_method}")
    ci = [mu - critical * se, mu + critical * se]
    prediction = None
    if model == "random" and k >= 3:
        pi_critical = student_t_ppf(1 - alpha / 2, k - 2)
        pi_se = math.sqrt(tau2 + se * se)
        prediction = [mu - pi_critical * pi_se, mu + pi_critical * pi_se]
    total_weight = sum(weights)
    studies = [{"study_id": str(row["study_id"]), "yi": float(row["yi"]), "vi": float(row["vi"]),
                "weight": weight, "weight_percent": 100.0 * weight / total_weight}
               for row, weight in zip(rows, weights)]
    warnings = []
    if not converged:
        warnings.append("tau2 root finder did not fully converge")
    if model == "random" and k < 3:
        warnings.append("prediction interval unavailable with fewer than 3 studies")
    return {
        "k": k, "model": model, "estimate": mu, "standard_error": se,
        "confidence_level": 1 - alpha, "confidence_interval": ci,
        "ci_method": interval_method, "tau2": tau2, "tau_method": tau_method_used,
        "tau_converged": converged, "Q": q, "Q_df": df, "Q_p_value": chi2_sf(q, df),
        "I2_percent": i2, "prediction_interval": prediction,
        "prediction_interval_method": "simple_t_k_minus_2" if prediction else None,
        "common_effect_reference": {"estimate": common_mu, "standard_error": common_se},
        "studies": studies, "warnings": warnings,
    }


def _validate_outputs(input_path: Path, outputs: list[Path | None], overwrite: bool) -> None:
    source = input_path.resolve()
    resolved = [path.resolve() for path in outputs if path is not None]
    if len(resolved) != len(set(resolved)):
        raise MetaAnalysisError("output paths must be distinct")
    for path in resolved:
        if path == source:
            raise MetaAnalysisError("an output path cannot be the input path")
        if path.exists() and not overwrite:
            raise MetaAnalysisError(f"output exists; pass --overwrite yes only after explicit approval: {path}")


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)


def render_csv(result: dict) -> str:
    from io import StringIO
    stream = StringIO(newline="")
    writer = csv.writer(stream)
    writer.writerow(["kind", "study_id", "yi", "vi", "weight", "weight_percent", "estimate", "ci_low", "ci_high"])
    for row in result["studies"]:
        writer.writerow(["study", row["study_id"], row["yi"], row["vi"], row["weight"], row["weight_percent"], "", "", ""])
    writer.writerow(["summary", "", "", "", "", "", result["estimate"], *result["confidence_interval"]])
    return stream.getvalue()


def render_svg(result: dict, width: int = 960) -> str:
    studies = result["studies"]
    confidence_level = float(result["confidence_level"])
    study_critical = NormalDist().inv_cdf(0.5 + confidence_level / 2.0)
    interval_label = f"{100.0 * confidence_level:g}% study intervals"
    lows = [study["yi"] - study_critical * math.sqrt(study["vi"]) for study in studies] + [result["confidence_interval"][0]]
    highs = [study["yi"] + study_critical * math.sqrt(study["vi"]) for study in studies] + [result["confidence_interval"][1]]
    if result["prediction_interval"]:
        lows.append(result["prediction_interval"][0])
        highs.append(result["prediction_interval"][1])
    xmin, xmax = min(lows), max(highs)
    if math.isclose(xmin, xmax):
        xmin -= 1.0
        xmax += 1.0
    left, right, row_h = 250, width - 40, 34
    height = 100 + row_h * (len(studies) + 2)
    scale_x = lambda value: left + (value - xmin) / (xmax - xmin) * (right - left)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
             '<rect width="100%" height="100%" fill="white"/>',
             '<style>text{font-family:Arial,sans-serif;font-size:14px}.axis{stroke:#555}.ci{stroke:#2563eb;stroke-width:2}.sum{fill:#b91c1c}</style>',
             '<text x="20" y="30" font-size="20">Meta-analysis forest plot</text>',
             f'<text x="20" y="50">{escape(interval_label)}; summary interval: {escape(result["ci_method"])}</text>',
             f'<line class="axis" x1="{left}" x2="{right}" y1="{height-45}" y2="{height-45}"/>']
    if xmin <= 0 <= xmax:
        parts.append(f'<line x1="{scale_x(0):.2f}" x2="{scale_x(0):.2f}" y1="45" y2="{height-45}" stroke="#bbb" stroke-dasharray="4 4"/>')
    for index, study in enumerate(studies):
        y = 80 + index * row_h
        yi, sei = study["yi"], math.sqrt(study["vi"])
        lo, hi = yi - study_critical * sei, yi + study_critical * sei
        size = 5 + 8 * math.sqrt(study["weight_percent"] / 100.0)
        parts.extend([f'<text x="20" y="{y+5}">{escape(study["study_id"])}</text>',
                      f'<line class="ci" x1="{scale_x(lo):.2f}" x2="{scale_x(hi):.2f}" y1="{y}" y2="{y}"/>',
                      f'<rect x="{scale_x(yi)-size/2:.2f}" y="{y-size/2:.2f}" width="{size:.2f}" height="{size:.2f}" fill="#2563eb"/>'])
    y = 80 + len(studies) * row_h
    lo, hi = result["confidence_interval"]
    parts.extend([f'<text x="20" y="{y+5}">Summary ({escape(result["model"])})</text>',
                  f'<polygon class="sum" points="{scale_x(lo):.2f},{y} {scale_x(result["estimate"]):.2f},{y-9} {scale_x(hi):.2f},{y} {scale_x(result["estimate"]):.2f},{y+9}"/>',
                  f'<text x="{left}" y="{height-18}">{xmin:.3g}</text>',
                  f'<text x="{right-30}" y="{height-18}">{xmax:.3g}</text>', '</svg>'])
    return "\n".join(parts)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--model", choices=["common", "random"], default="random")
    parser.add_argument("--tau-method", choices=["reml", "pm", "dl"], default="reml")
    parser.add_argument("--ci-method", choices=["z", "hksj", "modified-hksj"], default="hksj")
    parser.add_argument("--alpha", type=float, default=0.05)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-csv", type=Path)
    parser.add_argument("--forest-svg", type=Path)
    parser.add_argument("--overwrite", choices=["yes", "no"], default="no")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        outputs = [args.output_json, args.output_csv, args.forest_svg]
        _validate_outputs(args.input, outputs, args.overwrite == "yes")
        result = analyze(load_effects(args.input), args.model, args.tau_method, args.ci_method, args.alpha)
        payload = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if args.output_json:
            _atomic_write(args.output_json.resolve(), payload)
        if args.output_csv:
            _atomic_write(args.output_csv.resolve(), render_csv(result))
        if args.forest_svg:
            _atomic_write(args.forest_svg.resolve(), render_svg(result))
        if not any(outputs):
            print(payload, end="")
        return 0
    except (MetaAnalysisError, ArithmeticError, OSError) as exc:
        print(f"error: {exc}", file=os.sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
