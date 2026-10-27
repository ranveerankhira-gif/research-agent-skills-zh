# 科研智能体 Skills

一套中文优先、证据边界清晰、可审计的科研 Agent Skills，覆盖从文献检索到论文写作的完整研究流程。

> Chinese-first, auditable agent skills for literature discovery, evidence checking, research methods, reproducibility, and scientific writing.

[![Skills](https://img.shields.io/badge/skills-22-2563eb)](#skill-目录)
[![License: MIT](https://img.shields.io/badge/license-MIT-16a34a)](LICENSE)
[![Provenance](https://img.shields.io/badge/provenance-audited-7c3aed)](provenance.json)

## 为什么建立这个仓库

科研任务最危险的问题，不是答案写得不够漂亮，而是把推测写成事实、把题录当成全文、把相关性当成因果，或者生成不存在的引用。

这个仓库将科研工作拆成22个边界明确的 Skill。每个 Skill 都说明何时使用、何时不要使用、需要什么证据，以及哪些结论必须保留不确定性。

## Skill 目录

### 文献、来源与出版核验

| Skill | 用途 |
|---|---|
| `academic-literature-search` | 从公开学术数据库检索论文与题录元数据 |
| `literature-review` | 规划和执行可复现的系统、范围或叙述性综述 |
| `asreview-screening-v3` | 使用 ASReview 3 辅助大规模题录筛选 |
| `citation-management` | 离线规范化、去重并导出参考文献 |
| `citation-analysis` | 开展文献计量、共引与合作网络分析 |
| `literature-evidence-checker` | 核验引用、书目信息及主张与证据的对应关系 |
| `publication-integrity-check` | 核验撤稿、更正、期刊身份和出版诚信风险 |
| `research-source-acquisition` | 获取论文全文或研究数据并记录来源、版本和权限 |
| `dryad-data-fetcher` | 列出或下载用户指定的公开 Dryad 数据文件 |

### 研究设计、分析与证据评价

| Skill | 用途 |
|---|---|
| `causal-inference-analysis` | 规划、审计和解释观察性或准实验因果分析 |
| `meta-analysis` | 合并效应量并报告异质性和预测区间 |
| `qualitative-research-analysis` | 分析访谈、焦点小组、观察和开放题材料 |
| `survey-and-psychometrics` | 设计、修订和验证问卷与测量量表 |
| `research-ethics-consent` | 准备或审计伦理审查与知情同意材料 |
| `scientific-critical-thinking` | 评估风险偏倚与证据确定性 |
| `research-reproducibility-auditor` | 审计方法、分析项目和开放科学材料的复现条件 |

### 阅读、写作与完整科研流程

| Skill | 用途 |
|---|---|
| `scientific-paper-reading` | 深读单篇论文并把判断追踪到原文位置 |
| `scientific-translation` | 忠实翻译论文、图表说明和审稿意见 |
| `scientific-writing` | 根据真实研究材料起草科学论文或报告 |
| `paper-review-reviser` | 审阅和修改已有科研稿件 |
| `research-prose-naturalizer` | 在不改变事实、数据和引用的前提下减少模板腔 |
| `research-workflow` | 协调跨检索、设计、分析、写作和投稿的多阶段任务 |

## 安装

正式发布后，优先从 GitHub Releases 下载固定版本资产并核对 `SHA256SUMS.txt`，不要长期依赖会变化的分支 ZIP。

### 安装单个 Skill

1. 下载 `<skill-name>-<version>.zip`。
2. 核对同一 Release 中公布的 SHA-256。
3. 解压并先阅读 `SKILL.md`、`agents/openai.yaml`、脚本和权限说明。
4. 将完整 Skill 目录复制到你的公共 Skill 目录，例如：

   ```text
   C:\Users\<你的用户名>\.agents\skills\<skill-name>
   ```

5. 如果目标目录已经存在，先逐文件比较，不要静默覆盖。
6. 重启 Codex 后再使用。

### 安装整套合集

下载 `research-agent-skills-zh-v0.1.0.zip`，核对哈希后只安装自己确实需要的 Skill。安装整包不等于授权联网、下载全文、运行外部软件或写入研究文件。

## 安全与证据边界

- Skill 不得虚构论文、DOI、数据、引文位置、检索结果或数据库覆盖范围。
- 题录、摘要、全文和二手转述必须明确区分。
- 因果推断、元分析、风险偏倚和心理测量结论必须报告适用条件与不确定性。
- 登录、机构订阅、付费、验证码和受限数据访问必须由用户明确授权并合法提供。
- 高风险或会写文件的 Skill 默认采用显式调用；静态扫描和单元测试不能代替人工审阅。
- 示例配置不得填写真实账号、路径、Cookie、Token或研究参与者数据。

详见 [安全政策](SECURITY.md)、[贡献指南](CONTRIBUTING.md)、机器可读的 [Skill目录](catalog.json) 与 [来源审计](provenance.json)。

## 许可证与来源

仓库原创内容使用 [MIT License](LICENSE)。重大改编项会在自身目录中保留上游许可证和 `SOURCE.md`，并在 `provenance.json` 固定上游仓库、路径与修订版本。

当前重大改编项：

- `academic-literature-search`
- `citation-analysis`
- `scientific-critical-thinking`

## 开发与验证

```powershell
python -X utf8 scripts/build_catalog.py
python -X utf8 scripts/validate_repo.py
python -X utf8 scripts/package_release.py --release all --verify-only
python -X utf8 -m unittest discover -s scripts/tests -v
```

私有拒绝词清单可以通过 `PUBLICATION_DENYLIST_FILE` 指向仓库外文件；该清单本身不得提交。

