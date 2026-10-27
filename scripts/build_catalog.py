#!/usr/bin/env python3
"""Build the stable public Skill catalog from curated release metadata."""

from __future__ import annotations

import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "skills"
V01 = [
    "academic-literature-search", "citation-analysis", "citation-management", "literature-evidence-checker",
    "literature-review", "publication-integrity-check", "causal-inference-analysis", "meta-analysis",
    "qualitative-research-analysis", "research-ethics-consent",
    "survey-and-psychometrics", "paper-review-reviser",
    "research-prose-naturalizer", "research-workflow", "scientific-critical-thinking", "scientific-paper-reading",
    "scientific-translation", "scientific-writing", "research-source-acquisition", "asreview-screening-v3",
    "research-reproducibility-auditor", "dryad-data-fetcher",
]
V02 = []

PURPOSE = {
    "academic-literature-search": "从公开学术数据库检索论文与题录元数据",
    "citation-analysis": "开展有边界的文献计量与引文网络分析",
    "citation-management": "离线规范化、去重和导出参考文献",
    "literature-evidence-checker": "核验引用、书目信息与主张对应关系",
    "literature-review": "规划和执行可复现的文献综述",
    "publication-integrity-check": "核验论文状态、期刊身份与出版诚信风险",
    "research-source-acquisition": "寻找并记录论文全文或研究数据的获取证据",
    "asreview-screening-v3": "使用 ASReview 3 辅助题录筛选",
    "causal-inference-analysis": "规划、审计与解释观察性因果分析",
    "meta-analysis": "严谨合并研究效应量并报告异质性",
    "qualitative-research-analysis": "分析访谈、观察和开放题等定性材料",
    "research-ethics-consent": "准备或审计研究伦理与知情同意材料",
    "research-reproducibility-auditor": "审计方法、分析项目与复现条件",
    "survey-and-psychometrics": "设计、修订和审计问卷与心理测量",
    "paper-review-reviser": "审阅或修订现有科研稿件",
    "research-prose-naturalizer": "在保持事实与引用不变时减少科研模板腔",
    "research-workflow": "协调多阶段端到端科研工作流",
    "scientific-critical-thinking": "评估风险偏倚与证据确定性",
    "scientific-paper-reading": "深读单篇科研论文并追踪原文证据",
    "scientific-translation": "忠实翻译科研与学术材料",
    "scientific-writing": "依据真实研究材料起草科研文本",
    "dryad-data-fetcher": "列出或下载公开 Dryad 数据文件",
}

HIGH = {"research-source-acquisition", "asreview-screening-v3", "research-reproducibility-auditor", "dryad-data-fetcher"}
EXPLICIT_ONLY = HIGH | {"causal-inference-analysis", "meta-analysis", "qualitative-research-analysis", "research-ethics-consent", "survey-and-psychometrics", "paper-review-reviser", "research-prose-naturalizer", "research-workflow"}
NETWORK = {"academic-literature-search", "citation-analysis", "literature-evidence-checker", "literature-review", "publication-integrity-check", "research-source-acquisition", "asreview-screening-v3", "research-ethics-consent", "research-reproducibility-auditor", "survey-and-psychometrics", "research-workflow", "scientific-critical-thinking", "scientific-paper-reading", "scientific-writing", "dryad-data-fetcher"}
WRITES = {"citation-management", "research-source-acquisition", "asreview-screening-v3", "causal-inference-analysis", "meta-analysis", "qualitative-research-analysis", "research-ethics-consent", "research-reproducibility-auditor", "survey-and-psychometrics", "paper-review-reviser", "research-prose-naturalizer", "research-workflow", "scientific-paper-reading", "scientific-translation", "scientific-writing", "dryad-data-fetcher"}
NO_FILESYSTEM_READ = {"academic-literature-search"}
CREDENTIALS = {"research-source-acquisition"}
EXTERNAL = {"research-source-acquisition", "asreview-screening-v3", "research-reproducibility-auditor", "dryad-data-fetcher"}
COST = {"research-source-acquisition", "research-reproducibility-auditor", "dryad-data-fetcher"}
DEPENDENCIES = {
    "academic-literature-search": [
        "PowerShell 7+（运行五个公开学术接口的只读检索器）",
    ],
    "citation-analysis": [
        "可选 Skill：academic-literature-search（需要联网补充公开题录或引用关系时）",
    ],
    "citation-management": [
        "Python 3.10+（运行离线 CSL-JSON 台账与 BibTeX 导出脚本）",
    ],
    "research-source-acquisition": [
        "PowerShell 7+（仅在使用国家统计局公开数据辅助脚本时需要）",
        "可选 Skill：academic-literature-search、dryad-data-fetcher、web-tool-router、pdf",
        "受限来源所需账号、机构权限或付费订阅必须由用户自行合法提供",
    ],
    "asreview-screening-v3": [
        "Python 3.10+（仅在用户明确授权安装或真实运行时需要）",
        "ASReview 3.x（执行当日核对官方版本并安装到隔离环境）",
    ],
    "meta-analysis": [
        "Python 3.10+（运行无第三方依赖的基础元分析脚本）",
    ],
    "literature-evidence-checker": [
        "可选 Skill：academic-literature-search（需要公开题录检索时）",
    ],
    "literature-review": [
        "可选 Skill：academic-literature-search（执行公开数据库检索）",
        "可选 Skill：citation-management（整理和去重检索记录）",
        "可选 Skill：literature-evidence-checker（核验关键引用与主张）",
    ],
    "dryad-data-fetcher": [
        "Windows 10/11（当前发布测试平台）",
        "PowerShell 7+",
        "可选：用户自行安装并连接的 OpenCLI（仅 Anubis 浏览器验证回退）",
    ],
}


def display_name(name: str) -> str:
    text = (SKILLS / name / "agents" / "openai.yaml").read_text(encoding="utf-8")
    match = re.search(r'^\s*display_name:\s*["\']?(.+?)["\']?\s*$', text, re.M)
    return match.group(1) if match else name


def main() -> int:
    catalog_path = ROOT / "catalog.json"
    provenance = json.loads((ROOT / "provenance.json").read_text(encoding="utf-8"))
    approved = {row["name"] for row in provenance.get("skills", [])}
    planned = set(V01 + V02)
    directories = {path.name for path in SKILLS.iterdir() if path.is_dir()}
    if approved != planned or directories != approved:
        raise ValueError(
            "publication set differs from provenance approval: "
            f"unplanned={sorted(directories - approved)}, "
            f"missing={sorted(approved - directories)}, "
            f"metadata_gap={sorted(approved ^ planned)}"
        )
    rows = []
    for name in V01 + V02:
        if not (SKILLS / name).is_dir():
            continue
        version = "0.1.0" if name in V01 else "0.2.0"
        high = name in HIGH
        rows.append({
            "name": name,
            "display_name_zh": display_name(name),
            "purpose_zh": PURPOSE[name],
            "release": f"v{version}",
            "platforms": ["windows"] if name == "dryad-data-fetcher" else ["cross-platform"],
            "risk_level": "high" if high else ("medium" if name in NETWORK or name in WRITES else "low"),
            "permissions": {
                "network": name in NETWORK,
                "filesystem_read": name not in NO_FILESYSTEM_READ,
                "filesystem_write": name in WRITES,
                "credentials": name in CREDENTIALS,
                "external_state": name in EXTERNAL,
                "cost_or_quota": name in COST,
            },
            "dependencies": DEPENDENCIES.get(name, []),
            "invocation_policy": "explicit-only" if name in EXPLICIT_ONLY else "narrow-auto-or-explicit",
            "license": ("MIT (adapted; see local license/source files)"
                        if name in {"academic-literature-search", "citation-analysis", "scientific-critical-thinking"} else "MIT"),
            "version": version,
            # A catalog rebuild invalidates prior release archives. The packaging
            # step fills this only after creating and hashing the current ZIP.
            "archive_sha256": None,
        })
    payload = {"schema_version": 1, "repository": "ranveerankhira-gif/research-agent-skills-zh", "skills": rows}
    catalog_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {catalog_path} with {len(rows)} skills")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

