---
name: citation-management
description: 离线整理、规范化、去重和导出科研参考文献；仅在用户明确要求管理参考文献表、DOI/PMID/arXiv 标识、BibTeX、RIS、CSL-JSON、引文键或版本关系时使用。
license: MIT
metadata:
  version: "0.1.0"
---

# 参考文献管理

管理参考文献记录及其来源状态，不把“看起来完整”当成“已经核验”。允许自动调用，但只限参考文献库整理、元数据规范化、重复项识别、预印本—正式发表版本关联、引文键管理或 BibTeX/RIS/CSL-JSON 转换与导出。

不要因普通论文写作、文献综述、找论文或核验某条主张而自动调用。跨研究检索与综合交给 `literature-review`；来源存在性和主张支持关系交给 `literature-evidence-checker`；现有论文改写交给 `paper-review-reviser`。

## 工作方式

1. 先确定输入格式、目标格式、引用样式或投稿规范，以及是否允许联网补全。未获授权时按离线模式处理。
2. 保留原始记录与来源；规范化标识符和字段时不要覆盖原件。字段与状态契约见 [references/metadata-contract.md](references/metadata-contract.md)。
3. 先识别完全重复、可能重复与版本关系，再决定是否合并。判断规则见 [references/dedup-and-versions.md](references/dedup-and-versions.md)。
4. 缺失元数据标为缺失或不适用；不要猜测 DOI、作者、年份、卷期页码、文章号、出版社或访问日期。
5. BibTeX/CSL-JSON 是交换格式，不等于已经满足 APA、Vancouver、Chicago 或具体期刊版式。投稿前使用目标期刊当前样式规则或可靠的引用处理器渲染并复核。

## 离线脚本

只有输入是 CSL-JSON 数组时，才可使用 Python 3.10+ 运行 `scripts/citation_ledger.py`。它使用 Python 标准库，规范 DOI/URL、检查记录 ID、标出确定/可能重复、生成审计报告，并可导出保守的 BibTeX。当前脚本不解析 RIS 或现有 BibTeX；这两类输入先保留原文件并进行格式适配，不要冒充已被脚本验证。脚本不联网、不查询数据库、不删除记录，也不自动合并重复项。

```powershell
python scripts/citation_ledger.py --input citations.json --normalized-json normalized.json --report-json audit.json --bibtex references.bib
```

默认拒绝覆盖已有文件；只有用户明确要求覆盖时才传 `--overwrite yes`。输入与任何输出路径相同，或多个输出路径相同，脚本会拒绝执行。

脚本只读取 `--input` 明确指定的文件，只向 `--normalized-json`、`--report-json` 和 `--bibtex` 明确指定的路径写入；不会扫描引用管理器资料库、主目录或相邻目录。输出目录不存在时会按指定路径创建，因此运行前应先确认目标位置。原始输入始终保留不变。

## 证据门禁

- 标识符能解析与元数据正确、文献未撤回、被引用主张受支持是不同问题。
- DOI 相同通常是确定重复；标题近似只表示可能重复，不能据此自动删项。
- 预印本、会议摘要、注册记录、正式论文、更正和撤稿通知可能相互关联，但不是可随意互换的重复项。
- 发现正式发表版本时，保留预印本到正式版本的映射及实际引用选择理由，不静默替换。
- 从网页片段、搜索结果或二手文献得到的字段标为 `待核验`；只有核对权威元数据或原始来源后才标为 `已核验`。
- 不自动登录 Zotero、Mendeley、EndNote、图书馆数据库或外部 API，不读取现有账号库，不上传用户文稿。需要外部写入或账号访问时另行取得授权。

## 交付

根据任务给出：规范化后的记录、确定重复组、可能重复组、版本关系、字段冲突、缺失字段、来源与核验状态、未解决问题和导出文件。任何自动生成的 BibTeX 都标明它来自现有结构化元数据，并不证明引文内容已经核验。
