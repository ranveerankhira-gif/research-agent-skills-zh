# 来源与本地改造

上游：`beita6969/ScienceClaw`，目录 `skills/academic-literature-search`，固定修订 `640dfb06a246ebdcf49a469d77b7a4a86e64b5c0`。

上游以 MIT License 发布，保留的版权和许可全文见 [LICENSE.md](LICENSE.md)。本发行副本不是未经修改的上游原版。

本地公开版改造日期：2026-10-23。

主要改造：

- 把宽泛的“文献与引用管理”触发收窄为论文发现、数据库检索、检索式设计和稳定标识符查询；
- 移除对特定 PubMed MCP、内嵌 Python 片段和固定 GB/T 7714 工作流的绑定；
- 新增独立 PowerShell 检索器，统一支持 Crossref、PubMed、arXiv、OpenAlex 和 Semantic Scholar 的公开只读接口；
- 新增不联网的 PowerShell 回归测试，用模拟官方响应覆盖五个来源的解析与参数边界；
- 将综述、引用核验、引文库整理和全文获取拆分给边界明确的其他 Skill；
- 增加查询隐私、元数据与全文证据分层、限流、版本去重和禁止付费墙绕过等边界；
- 文件结构、脚本和参考资料均按公开 Codex 运行方式重新实现。
