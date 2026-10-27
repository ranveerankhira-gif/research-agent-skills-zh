---
name: academic-literature-search
description: 通过公开、只读学术数据库查找论文和题录元数据；仅在用户明确要求找论文、检索 Crossref/PubMed/arXiv/OpenAlex/Semantic Scholar、构造数据库检索式，或按 DOI/PMID/arXiv ID 查询记录时使用。
license: MIT
metadata:
  version: "0.1.0"
  upstream: "beita6969/ScienceClaw@640dfb06a246ebdcf49a469d77b7a4a86e64b5c0"
---

# 学术文献检索

从公开学术数据库发现论文并返回可追溯的题录信息。允许自动调用，但只限明确的论文发现、数据库检索、检索式设计或标识符查找。

不要因普通网页搜索、文献综述写作、引用真实性核验、主张—来源核查、引文库整理、已有论文修改或统计分析而自动调用：跨研究综述交给 `literature-review`，引用与主张核验交给 `literature-evidence-checker`，引文库整理交给 `citation-management`，普通网页资料交给 `web-tool-router`。

## 数据源选择

按任务选最小充分来源，不固定要求每次查询所有数据库：

- DOI、期刊题录、出版商、基金信息：Crossref；
- 生物医学、MeSH、PMID：PubMed；
- 物理、数学、计算机及相关预印本：arXiv；
- 跨学科发现、开放获取、机构与引用关系：OpenAlex；
- 相关论文、引用/参考文献网络：Semantic Scholar。

来源覆盖和局限见 [references/source-routing.md](references/source-routing.md)。若用户要求系统或范围综述，由 `literature-review` 先确定协议、来源覆盖和检索日志；本 Skill 只负责实际检索与题录返回。

## 执行

1. 明确主题或标识符、学科范围、年份、文献类型、语言和结果数量。不会改变方向的缺省项可以说明假设后继续。
2. 将概念拆成同义词和受控词；需要可复现检索时，保留数据库、完整检索式、过滤条件、查询时间、命中数及实际取得范围。
3. 普通查询优先使用 PowerShell 7+ 运行 `scripts/search_academic.ps1`。它只向五个已列明的公开官方接口发送查询词或标识符，并把标准化 JSON 输出到终端，不安装依赖、不读取账号、不读写用户文件。
4. 脚本不支持的高级过滤可以直接调用对应官方只读接口，但不要转向收费 API、登录态数据库或未审计脚本。网络失败最多重试一次；限流后停止或改用另一项适合的公开来源。
5. 返回结果时保留来源、检索时间、稳定标识符和记录 URL。去重前不要把同一研究的预印本、会议版和期刊版计算成多项独立证据。

示例：

```powershell
pwsh -File scripts/search_academic.ps1 -Source crossref -Query "causal inference education" -Limit 10
pwsh -File scripts/search_academic.ps1 -Source pubmed -Query "diabetes mellitus[mh] AND randomized controlled trial[pt]" -Limit 10
pwsh -File scripts/search_academic.ps1 -Source arxiv -Identifier "1706.03762"
pwsh -File scripts/search_academic.ps1 -Source openalex -Query "urban heat mortality" -Limit 10
pwsh -File scripts/search_academic.ps1 -Source semantic-scholar -Identifier "DOI:10.1038/nature12373"
```

## 证据与隐私边界

- 数据库返回的是发现或题录证据，不等于论文结论已经核验；标题和摘要不等于全文。
- DOI/PMID/arXiv ID 能解析只证明记录存在，不证明元数据完全正确、论文未更正/撤回或用户的主张受支持。
- 引用量必须标注数据库和检索日期；不同平台覆盖不同，引用量不是研究质量、因果强度或纳入标准。
- 不虚构搜索结果、作者、标题、标识符、摘要、命中数或全文内容。缺失字段保持缺失。
- 查询词会发送给所选公共服务。不要发送未发表稿件全文、个人信息、受限数据或机密项目描述；必要时只使用最少、去敏的主题词。
- 不自动下载 PDF、绕过付费墙、登录账户、申请 API 密钥、保存检索、创建提醒、上传文件或写入 Zotero。需要这些动作时另行确认。

更详细的证据状态和交付字段见 [references/evidence-boundaries.md](references/evidence-boundaries.md)。

## 交付

简要报告实际查询的来源与时间、检索式、过滤条件、取得数量、结果清单、可能重复/版本关系和覆盖局限。若只执行探索性查询，明确写“探索性检索”，不要声称检索全面或系统综述已经完成。

## 来源说明

本 Skill 以 ScienceClaw 的同名 MIT Skill 为起点进行了实质性重做：移除 PubMed MCP、内嵌 Python 引用格式化、固定 GB/T 7714 工作流和宽泛触发，改为五个公开接口的独立 PowerShell 检索器，并重新划分检索、综述、引文管理、证据核验和全文获取边界。详见 [来源与改造说明](SOURCE.md)，上游许可证见 [LICENSE.md](LICENSE.md)。
