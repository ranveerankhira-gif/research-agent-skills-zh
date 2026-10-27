# ASReview 3 本地工作流

本参考用于安装、启动或真实运行，不用于普通方案咨询。ASReview 接口会变化；执行前必须核对官方文档和 PyPI 当前版本，不复用旧 Skill 中的 API 名称。

## 当前基线

截至 2026-10-16，已核验 PyPI 当前版本为 ASReview 3.0.8，Python 要求为 3.10 及以上；官方文档使用 `asreview lab` 启动本地界面。这个版本号是历史基线，不是未来自动升级许可。

官方来源：

- 文档：https://asreview.readthedocs.io/en/stable/
- 源码：https://github.com/asreview/asreview
- PyPI：https://pypi.org/project/asreview/

执行前重新核对安装命令、兼容 Python 版本、插件要求、迁移说明和安全公告。不要使用旧版示例中的 `ASReviewData`、`ReviewSimulate`、`NBModel` 等 API，除非当前官方版本仍明确支持。

## Windows 安装门禁

只有用户明确要求安装时才安装。遵循本机约定：

1. 使用用户明确指定的独立目录；不要自行选择盘符。先检查目标是否已存在，存在时比较并报告，不覆盖。
2. 创建隔离虚拟环境，不向全局 Python 安装，也不改写其他项目环境。
3. 记录 Python、ASReview 和插件的准确版本以及安装来源。
4. 验证启动与退出；只有用户另行要求时才创建桌面快捷方式。

安装或升级前列出准确目标目录、版本和预计下载量。不要为了满足示例而自动安装 `asreview-insights`、`asreview-datatools` 或其他插件；仅在任务确实需要并得到授权时加入。

## 官方 v3 命令形态

下面仅用于核对当前文档，不代表自动执行许可：

```text
asreview lab
asreview simulate MY_DATASET.csv -o MY_SIMULATION.asreview
asreview algorithms
```

模拟适用于已经完整标注、可计算真实性能的数据集；不得在未完成筛选的真实综述数据上把模拟召回率冒充实际召回率。当前 v3 Python API 以 `import asreview as asr` 和 `asr.Simulate(...)` 为官方示例，具体参数须以执行当日文档为准。

## 文件与进程

- 原始题录只读；标准化或去重结果写入新文件。
- 输出目录中保存配置、版本、日志、导出文件和哈希或其他身份信息。
- 启动本地服务后报告端口和进程；任务结束按用户要求关闭，不遗留不明后台服务。
- 不把本地界面称为云服务，不因浏览器打开而推定数据已上传。
