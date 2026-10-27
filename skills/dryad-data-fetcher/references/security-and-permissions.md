# 安全与权限

## 权限清单

- **读取**：读取用户给出的 DOI/数据集 URL、仓库外的可选 JSON 配置、Dryad 公开元数据，以及显式输出目录内的同名候选文件。不会扫描其他个人文件。
- **写入**：下载时只写用户显式给出的输出目录。临时文件采用随机 `.partial` 名并与最终文件同目录；失败会清理。拒绝 Skill 目录、现有重解析点路径、目录型同名目标和文件型符号链接。
- **网络**：元数据仅访问 `https://datadryad.org/api/v2/`。下载逐跳允许 `datadryad.org` 官方端点或 `dryad-assetstore-*.s3[.region].amazonaws.com`；每次重定向都重新验证。离线测试的回环地址开关是隐藏测试参数，不用于正常调用。
- **浏览器**：正常列目录和直接下载不使用浏览器。只有公开下载端点返回 HTML 验证页时，才调用用户已安装并连接的 OpenCLI；每个文件使用唯一会话，只关闭本次创建的页面和会话。
- **凭据**：不要求 Dryad 登录或 API Token，不读取、打印、导出 Cookie、Token、密码或浏览器登录态。结果只记录是否使用浏览器回退，不记录 OpenCLI profile 名。
- **费用与资源**：Dryad 匿名 API 本身不收费。下载会消耗网络带宽、磁盘和可能的计量网络费用；默认单文件最多 10 GiB。Dryad 当前也建议单文件不超过 10 GB，但整个数据包可很大。

## 确认与停止边界

- `-ListOnly` 是只读操作，可在用户给出公开 DOI 后执行，且不解析 OpenCLI。
- 下载单个文件需要明确文件或单文件数据集，并必须显式指定输出目录。
- `-All`、提高 `-MaxBytes`、覆盖资源预算或批量下载必须有用户明确要求。
- 遇到登录、私有/受限数据、账号申请、验证码破解、意外主机、摘要不一致、HTML 错误页、超限、重解析点或同名不同内容时停止；不得降低检查强行继续。

官方依据：[Dryad API](https://github.com/datadryad/dryad-app/blob/main/documentation/apis/README.md)；[Dryad 文件大小说明](https://dev.datadryad.org/help/requirements/files)。
