# 来源与本地改造

上游：`K-Dense-AI/scientific-agent-skills`，目录 `scientific-critical-thinking`，固定修订 `a92663a0214b3b9fa1ba6b958284ffd919c00a0c`。

上游由 K-Dense Inc. 以 MIT License 发布，保留的版权和许可全文见 [LICENSE.md](LICENSE.md)。本发行副本不是未经修改的上游原版。

本地公开版改造日期：2026-10-23。

主要改造：

- 将自动触发收窄到明确的偏倚风险、证据确定性和具体科学主张方法学批判；
- 移除 OpenRouter、生图、自动上传和默认写入路线；
- 将 RoB 2、ROBINS-I、QUADAS-3 与 GRADE 的适用单位和职责边界分开；
- 增加“已核验 / 待核验 / 信息不足”状态，禁止用猜测填补信号问题；
- 禁止把检查项相加成通用质量分数，也不把报告规范、期刊声誉、引用量或显著性当作低偏倚证据；
- 针对本仓库其他科研 Skill 重新划分触发范围，减少重复自动介入。
