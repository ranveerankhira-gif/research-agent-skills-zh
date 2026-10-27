---
name: dryad-data-fetcher
description: 通过 Dryad 官方匿名 API 列出或下载用户明确指定的公开数据集文件，并核验大小与摘要；仅当公开下载端点返回 Anubis HTML 验证页时，可使用用户已有的 OpenCLI 浏览器会话完成验证。仅用于公开读取，不处理登录、私有数据、数据提交或访问控制绕过。
---

# Dryad 数据获取

列目录或下载前读取 [安全与权限](references/security-and-permissions.md)。

用于公开 Dryad 数据集的可重复文件获取。文件发现始终使用 Dryad 官方匿名 API；只有下载端点实际返回 Anubis HTML 验证页时，才调用用户已有的 OpenCLI 浏览器会话。官方 API 说明见 [Dryad API documentation](https://github.com/datadryad/dryad-app/blob/main/documentation/apis/README.md)。

## 执行

1. 运行 `scripts/Get-DryadData.ps1`，传入 Dryad DOI 或数据集 URL。`-ListOnly` 不需要 OpenCLI，也不写文件。
2. 多文件数据集先列目录；除非用户明确要求全部下载，否则用区分大小写的完整 `-FileName` 选择文件。
3. 下载必须显式传入 `-OutputDirectory`。默认单文件上限为 10 GiB；只有用户确认磁盘、带宽与文件用途后，才可用 `-MaxBytes` 提高。
4. 下载后报告实际路径、字节数、SHA-256、内容类型、是否复用已有文件及是否使用浏览器回退。只有取得文件字节并通过大小、摘要和 HTML 检查，才能写“已取得数据”。

```powershell
# 列出文件
pwsh -File scripts/Get-DryadData.ps1 -Dataset "10.5068/D1RH4K" -ListOnly

# 下载单个文件
pwsh -File scripts/Get-DryadData.ps1 -Dataset "10.5068/D1RH4K" -FileName "<从列表复制的完整文件名>" -OutputDirectory "D:\Example\Dryad"

# 可选：将 config.example.json 复制到仓库外，再显式加载
pwsh -File scripts/Get-DryadData.ps1 -Dataset "10.5068/D1RH4K" -ListOnly -ConfigPath "D:\Example\dryad-fetcher.json"
```

## 边界

- 只访问 `datadryad.org` 的公开 API/下载端点，以及经逐跳复核的 Dryad S3 资产主机；不自动信任重定向目标。
- 不输入账号、密码、API Token，不破解验证码，不复用或导出用户身份凭据。
- 不安装或升级 OpenCLI、浏览器扩展及其他依赖。普通 API 列表与直接下载无需 OpenCLI；只有 Anubis 回退时若工具缺失才停止并报告。
- 多个 Browser Bridge 配置并存且无法确认默认项时，要求用户传 `-Profile`；脚本不改变全局默认配置，也不在 JSON 结果中暴露配置名。
- 不覆盖同名但内容不同的文件；相同内容复用现有文件，不同内容使用哈希后缀保存。
- 拒绝写入 Skill 目录、重解析点路径、保留设备名、路径穿越式名称和超长名称；临时文件与最终文件位于同一输出目录，失败时清理 `.partial`。
- 每次浏览器回退使用唯一会话名，只关闭本次创建的标签页并释放该会话。
- 登录、私有或申请型数据不属于本 Skill；遇到这些状态应停止并请用户决定。

## 依赖

必需：PowerShell 7+。可选：`PATH` 中已有的 `opencli`，或通过 `OPENCLI_BIN`、`-OpenCli`、仓库外配置文件显式指定；仅用于 Anubis 回退。Skill 不再依赖 `ketch`，也不负责安装或升级工具。

脚本的结构化 JSON 输出是交付依据；不要把网页可打开、元数据可见或 HTTP 200 单独当成文件已取得。
