# 元数据与核验状态契约

## 推荐交换格式

离线脚本接受一个 CSL-JSON 记录数组。每条记录必须包含非空且在当前数组内唯一的 `id` 和非空 `title`；并建议包含 `type`、`author`、`issued`、`container-title`、`volume`、`issue`、`page`、`DOI`、`URL` 等字段。

`author` 使用 CSL 对象数组，例如 `[{"family":"Wang","given":"Li"}]`；机构作者使用 `literal`。`issued` 使用 `{"date-parts":[[2024,5,1]]}`。不要把作者列表压成未经解析的一整串文本后假装结构已经可靠。

## 审计字段

本 Skill 使用 `_audit` 保存过程信息：

```json
{
  "verification_status": "待核验",
  "metadata_source": "用户提供",
  "checked_at": "",
  "notes": []
}
```

允许的状态：

- `已核验`：已与权威元数据或原始出版物核对；
- `待核验`：结构可用，但身份或字段尚未充分核对；
- `材料缺失`：完成核验所需的原始记录、全文或标识符不存在。

`checked_at` 在实际核验发生时使用 ISO 日期；不要用当前日期冒充核验日期。`metadata_source` 记录字段来自出版商、Crossref、PubMed、用户文件或其他具体来源。

## 字段处理

- DOI 去除 `doi:` 与 `https://doi.org/` 前缀并统一小写；这只是格式规范化。
- PMID、PMCID、arXiv ID、ISBN 等保留在 `note` 或明确的扩展字段中，并写明命名空间。
- 在线优先文章可能没有卷期页码；缺失不等于错误。文章号不能伪装成页码。
- 姓名顺序、复姓、粒子、机构作者和非拉丁文字需要保留原始形式；无法可靠拆分时不要猜。
- 标题大小写应保留语义与专名。批量改成标题式大小写可能破坏化学式、基因名和缩写。
