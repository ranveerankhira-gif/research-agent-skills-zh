---
name: research-reproducibility-auditor
description: Audit whether a supplied Methods section, analysis project, or proposed replication package contains enough evidence to reproduce the work. Invoke automatically only when the user explicitly asks about research reproducibility, replication readiness, Methods completeness for replication, computational provenance, preregistration, FAIR data, or an open-science package. Do not invoke for ordinary manuscript revision, statistical analysis, study design, citation checking, or figure creation.
license: MIT
metadata:
  version: "0.2.0"
  last-reviewed: "2026-10-26"
---

# 科研复现审计

判断现有材料是否足以让独立研究者复现方法、计算过程或研究产物。只审计有证据的内容；不要把“写得完整”“方法有效”“结果可重复”和“独立复制得到相同结论”混为一谈。本 Skill 只允许通过 `$research-reproducibility-auditor` 显式调用。

## 路由边界

只有用户表达明确的复现审计或复现规划意图时才使用。根据目标选择一个或多个模式：

- **方法复现审计**：检查 Methods、补充材料、实验记录或协议能否支持独立复现。读取 [references/methods-reproducibility.md](references/methods-reproducibility.md)。
- **计算复现审计**：检查代码、数据清单、依赖、环境、随机性和输出来源。读取 [references/computational-reproducibility.md](references/computational-reproducibility.md)。
- **复现包与开放科学规划**：规划预注册、FAIR 数据、代码归档、受控访问和复现说明。读取 [references/open-science-package.md](references/open-science-package.md)。

不要因为请求中只出现“论文”“Methods”“代码”“开放科学”或“复现结果”就触发。相邻任务应交给现有专用 Skill：

- 普通论文审阅、润色或回复审稿意见：`paper-review-reviser`
- 数据采集前的分组、随机化和实验设计：`experimental-design`
- 统计检验、模型、功效或重新计算结果：`statistical-analysis`
- DOI、引用、元数据和主张—来源核验：`literature-evidence-checker`
- 跨多个科研阶段的完整工作流：`research-workflow`
- 科研图表创建或审查：`scientific-visualization`

显式调用 `$research-reproducibility-auditor` 时仍须遵守本 Skill 的权限和证据边界。

## 权限与安全边界

默认执行只读审计。

执行任何项目代码前，读取 [references/security-and-permissions.md](references/security-and-permissions.md)。真实重跑是高风险模式，不属于默认审计。

- 可以读取用户置于范围内的论文、代码、配置、清单和日志，并运行不会改变项目状态的检查。
- 不自动执行项目代码、Notebook、构建、容器、渲染、迁移或包安装；这些操作可能改写缓存、输出或环境。需要真实重跑时，先说明将执行什么、写到哪里、可能联网下载什么以及预计计算成本，再取得当前任务所需授权，优先在隔离副本中运行。
- 不上传论文、代码或数据，不创建外部项目，不进行预注册，不创建 GitHub Issue、分支或 PR，不修改账号、仓库或云端设置。
- 不读取未获授权的浏览器、邮箱、Notion、私有仓库、密钥目录或账号数据。
- 只有用户明确要求核对最新规范、仓库或公开来源时才联网；保持只读，不要求凭据，不将本地材料发给第三方。安装依赖、拉取容器、下载数据或调用外部服务均须单独列明，不得混入“只读核验”。
- OSF、Zenodo、GitHub、GitLab、Dryad、Docker、Conda 等均属候选方案，不得成为默认路线或强制依赖。
- 涉及敏感数据时，优先提出受控访问、数据字典、去标识说明和可共享的派生产物；不要把“完全公开数据”当作唯一合格答案。

## 工作方法

1. 明确审计对象、目标模式、材料范围和用户希望达到的复现层级。
2. 盘点实际提供的证据，不因文件名、模板或声明推定内容已经存在。
3. 只读取与当前模式对应的参考文件；多模式任务才组合读取。
4. 将每项判断标为：
   - `已核验`：当前材料直接支持，或相关只读检查已经成功完成。
   - `待核验`：存在可行的验证方法，但本轮尚未执行或需要额外授权。
   - `材料缺失`：作出判断或完成复现所需的材料没有提供。
5. 给出最小、可操作的修复建议，并指出哪些信息需由作者、数据持有人或实验执行者补充。

## 输出契约

形式随任务调整，不强制使用统一表格或总分。每个实质发现至少包含：

- 发现及其文件、段落、配置项或产物位置；
- 支持判断的证据；
- 对复现的具体影响；
- `已核验 / 待核验 / 材料缺失`；
- 最小修复建议和责任人类型。

只有在干净或等价环境中真实完成端到端运行、确认退出状态并比较关键产物后，才可表述为“已成功复现”。仅存在锁文件、README、容器定义、测试或成功构建记录，都不能单独证明真实复现成功。

## 来源与改写说明

本地版本借鉴并重新收窄了以下 MIT 来源的复现审计思路：

- AIPOCH `reproducibility-check`，提交 `686e09dfdb45d9fa1a08664f06bb93769b3c9d91`。
- Morrison Lab `reproducibility-audit`，提交 `04eae32140ff8b1c679b134e38e540c854da4f99`。

没有复制其自动外部操作、预设平台路线或宽泛触发条件；使用本 Skill 的成果时不要求引用上述 Skill。
