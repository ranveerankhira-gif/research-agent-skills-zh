---
name: meta-analysis
description: 严谨合并多项独立研究的效应量，报告异质性、预测区间和结论边界；也用于明确的元分析方法审计请求。
license: MIT
metadata:
  version: "0.1.0"
---

# 元分析

仅在用户明确要合并两个或更多独立研究的效应量，明确提到元分析、效应量合并、森林图、异质性、预测区间，或明确要求审计元分析方法时使用本 Skill。本 Skill 只允许通过 `$meta-analysis` 显式调用。

不要因普通文献综述、系统综述检索、文献筛选、引用核查、单项研究统计、一般论文分析/润色或普通绘图而自动调用。跨两个以上科研阶段的组织任务交给 `research-workflow`；单项研究的数据分析或统计计划交给 `statistical-analysis`；引用真伪与主张对应关系交给 `literature-evidence-checker`。

## 工作流程

1. 先确认估计目标、效应量尺度与方向、研究单位、独立性、方差来源和缺失情况。按需读取 [references/input-contract.md](references/input-contract.md)。
2. 判断基础独立研究模型是否适用。遇到同一研究多效应量、聚类、多层结构、RVE、诊断试验、剂量反应、网络元分析或 IPD 元分析时，可以做方法判断，但不要把它们偷偷简化成普通独立研究模型；说明需要升级的方法或软件。
3. 只有在研究相互独立、估计目标一致、分析尺度一致且输入字段满足契约时，才可运行 `scripts/meta_analysis.py`。脚本不联网、不安装依赖、不上传数据。
4. 同时报告效应合并值及区间、研究数、Q 与其 p 值、tau²、I²、估计方法、区间方法和假设边界。随机效应优先报告 REML，并用 Paule-Mandel 或 DL 做敏感性检查；小样本优先 HKSJ，并说明 modified-HKSJ 的差异。
5. 如果生成森林图，必须保留研究级数据、方向和尺度说明；图形只展示模型结果，不替代方法判断。
6. 读取输入和写出 JSON、CSV 或 SVG 前确认文件范围与目标路径；默认创建新文件，不扫描相邻目录，也不覆盖已有结果。

## 科学门禁

- 不依据 Q 或 I² 的显著与否机械选择共同效应或随机效应模型；模型来自科学问题和可交换性假设。
- 不静默删除无效行、不自动变换不明尺度、不猜测标准误或方差、不把重复研究 ID 当作独立证据。
- 不把漏斗图不对称或小研究效应检验直接称为“发表偏倚”；研究数过少时不做强推断。
- 不把随机效应总体均值解释为所有场景都成立；存在实质异质性时报告预测区间并讨论来源。
- 不捏造缺失数据、研究结果、亚组、协变量或引用。材料不足时列出缺口并停止数值合并。
- 不自动覆盖输入或已有输出。只有用户明确要求覆盖，才向脚本传 `--overwrite yes`。

## 基础脚本

```powershell
python scripts/meta_analysis.py --input effects.csv --model random --tau-method reml --ci-method hksj --output-json result.json --output-csv weights.csv --forest-svg forest.svg
```

输入至少包含 `study_id,yi`，以及 `vi` 或 `sei`。完整字段、尺度和独立性要求见 [references/input-contract.md](references/input-contract.md)。方法解释、升级条件与权威资料见 [references/methodology.md](references/methodology.md)。

脚本提供共同效应模型，以及 REML、Paule-Mandel、DL 的随机效应估计；区间可选 z、HKSJ、modified-HKSJ。它是透明的基础计算器，不声称替代 `metafor`、`meta`、Stata 或专业统计审查。
