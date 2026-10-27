# 科研来源矩阵

本页区分“截至 2026-10-23 已实测”与“候选来源”。实际使用前重测具体端点、记录、许可证和访问条件。

## 论文发现与全文

| 来源 | 已知能力与实测状态 | 路由/边界 |
|---|---|---|
| Crossref | 已实测返回 DOI 与完整题录 | 只证明题录，不证明全文 |
| PubMed | 已实测返回 PMID、题名、作者、期刊、DOI | 题录不等于全文；复杂查询同时用 MeSH 与自由词 |
| OpenAlex | 已实测返回题录、开放状态与引用关系 | 开放链接和作者/机构消歧需复核 |
| arXiv | 已实测取得完整 PDF | 记录版本；预印本不等于正式同行评议版 |
| Europe PMC | 已实测取得 `fullTextXML` | 适合结构化全文；核对 PMCID/DOI |
| PMC/NCBI BioC | 已实测取得作者手稿 PDF、补充 PDF 与 BioC XML | JS 检查可能返回 HTML；只保留真实 PDF |
| PLOS | 已实测公开 PDF | 每篇仍检查文件头、题名和 DOI |
| Semantic Scholar | 无密钥 API 曾连续 429；公开论文页可取 Corpus ID、TLDR、引用/参考文献 | API 尝试一次；429 后转公开页。引用数按日期记录 |
| CORE | API 曾在成功与 429 间波动；公开页通过 Cloudflare 后取得官方临时 PDF | 精确 DOI/题名检索；宽泛检索曾命中错误论文 |
| DataCite | 已实测返回论文/数据集 DOI 记录 | 主要是发现与元数据 |
| OpenAIRE | 已实测返回出版物记录 | 发现后继续核验全文位置 |
| bioRxiv | 已实测元数据与摘要 | 记录预印本状态和后续正式版本 |
| ResearchGate | 候选发现入口，未作为通用下载路径实测 | 只使用作者合法上传的版本；逐篇核验版本、许可和文件身份 |

合法全文顺序：出版商开放版 → PMC/Europe PMC → arXiv/bioRxiv/medRxiv/SSRN → 机构仓储/作者手稿 → CORE/OpenAlex/Unpaywall 线索 → 用户合法上传。遇到付费墙不绕过。

### 已验证案例的可复用教训

- DOI `10.1038/nature12373` 的 Nature 出版商排版 PDF 仍付费；合法取得的是 PMC 作者手稿、补充材料、BioC XML、arXiv 预印本和 CORE/Harvard 版本。不要把开放作者手稿称为出版商排版 PDF。
- PDF 链接曾返回 Cookie/验证 HTML；必须核对 `%PDF`、页数、题名与 DOI。

## 通用数据仓库

| 来源 | 状态 | 注意 |
|---|---|---|
| Zenodo | 已实测公开文件 | 新版记录的文件下载地址在 `files[].links.self`，不是 `links.content` |
| Dryad | 已形成专用 `dryad-data-fetcher` | 公开下载可能遇到 Anubis；由专用 Skill 处理，不要求账号 |
| Figshare | 已实测具体 Excel 文件字节 | 若只取得 HTTP 206/Range 片段，不能称完整文件 |
| OSF | 已实测公开文件字节 | 每个项目单独检查权限与完整性 |
| Harvard Dataverse | 已实测具体 ZIP 字节 | Dataverse 页面公开不代表每个文件匿名可取 |
| Kaggle | 已实测一个公开数据集可匿名取得完整 ZIP | 其他数据集可能要求账号或接受规则 |
| GitHub Raw | 已实测完整 CSV | 核对仓库、提交或 Release 版本与许可证 |
| Mendeley Data | 候选，未完成通用实测 | 按具体记录验证 |
| Google Dataset Search、re3data、BASE | 发现入口 | 只负责找线索，不证明文件可得 |
| Internet Archive、Wayback Machine | 失效链接恢复候选 | 只使用合法存档，不用存档规避访问控制 |

## 政府、经济、人口与教育

已实测取得真实响应、数值或文件：World Bank API、FRED CSV、Eurostat、IMF DataMapper、UN Comtrade、OECD SDMX、DHS API 数值、ClinicalTrials.gov JSON、FAOSTAT 批量文件，以及中国国家统计局新版“国家数据”。WHO ICTRP、WHO/CDC 数据入口属于候选，尚未完成通用实测。

国家数据旧 `/easyquery.htm` 已被 WAF 以 `403 UrlACL` 淘汰。使用本 Skill 的 `scripts/Get-NbsPublicData.ps1` 调用 `/dg/website/publicrelease/web/external/...`；已验证年、季、月查询，但使用时仍需重测。

候选而非通用已验证：BIS、WTO Stats、UNData、BEA、BLS、Penn World Table、ECB、SEC EDGAR、各国央行/财政部/统计局/证券监管机构；教育类包括 OECD PISA、TIMSS、PIRLS、TALIS、UNESCO UIS、NCES、IPEDS、EdFacts 和各国教育年鉴。

中国公共来源候选还包括国家统计局专题数据库和统计年鉴、各省市统计局及地方年鉴、国家卫生健康委员会、中国疾控中心、教育部、民政部、生态环境部、水利部、农业农村部、海关总署、中国人民银行、国家金融监督管理总局、国家知识产权局、国家自然科学基金项目查询、各级政府开放数据平台、行业协会和事业单位公开报表。它们常分散为网页、PDF、Excel附件和年度公报，必须逐个核对年份、口径、文件和自动化条件；列入候选不等于已取得。

## 生物医学、组学和化学

已实测：GEO 压缩表达矩阵、ENA 运行记录、GenBank 序列、UniProt TSV、PubChem JSON、ChEMBL JSON、PDB CIF、ClinicalTrials.gov、Europe PMC 全文。

按任务继续核验的候选：WHO ICTRP、Project Data Sphere、SRA、ArrayExpress/BioStudies、PRIDE/ProteomeXchange、MetaboLights、Metabolomics Workbench、AlphaFold DB、STRING、BioGRID、Ensembl、UCSC Genome Browser、GWAS Catalog、dbSNP、ClinVar、TCGA/GDC、GTEx、OpenNeuro、Human Connectome Project、NHANES、MIMIC、SEER、PhysioNet。

## 地球、环境、生态与遥感

已实测：NOAA 完整 CSV、NASA EONET、GBIF JSON、USGS GeoJSON、Copernicus STAC 目录、FAOSTAT 文件。

目录可搜索不等于影像已取得；Copernicus、NASA Earthdata、ERA5/ECMWF 等下载可能需要账号/OAuth。候选还包括 ESA、CMIP6/ESGF、PANGAEA、OBIS、NEON、MODIS、Landsat、Sentinel、WorldClim、CHELSA、Global Forest Watch、OpenStreetMap、THREDDS 和 ERDDAP。

## 社会调查与受限数据

| 来源 | 当前边界 |
|---|---|
| IPUMS | 匿名可看部分样本/变量元数据；真实 Extract API 需要账号、对应集合注册和 API Key。USA/CPS 免费且官方称即时审批；International 需个人申请、英文研究说明和一年期许可。未来需求未知时不预注册；具体研究出现后协助申请与下载 |
| CFPS | 公开文档与元数据可读；公开微观数据也需注册和人工审核，官方平台与北大 Opendata 账号不互通；县/市等限制数据需单独申请，可能只可在指定地点使用。Codex 可协助申请、操作已登录页面并在 `download_only` 模式保存文件，但不得读取受协议限制的微观数据 |
| ICPSR | 一次匿名访问曾 403；具体数据集可能公开、会员或受限，必须逐项判断 |
| UK Biobank | 官方说明需研究者注册、申请、机构协议，部分使用涉及费用；尚未完成逐项实测 |
| EGA | 受控数据通常需账号和数据访问委员会批准；尚未完成逐项实测 |
| dbGaP | 公开信息可查；受控数据需授权；尚未完成逐项实测 |
| Vivli、YODA、CSDR、All of Us | 申请入口已确认，个体级数据需正式申请；尚未完成逐项实测 |
| DHS、World Values Survey、ESS、GSS、LIS、UK Data Service、Australian Data Archive | 按数据集判断公开、注册、申请、机构或安全环境 |
| Integrated European Census Microdata、Pew Research Center datasets | 候选社会调查来源；逐项核验注册、用途限制、版本与下载条件 |
| CHARLS、CGSS、CHNS、CHFS、CLDS | 中国调查候选；逐项核验账号、用途、许可和地理限制 |

商业/机构订阅候选：Wind、CSMAR、CEIC、Bloomberg、Refinitiv、WRDS、Compustat、CRSP、Orbis、Statista。只能使用用户/机构合法权限，不绕过订阅，不自动增加付费后备。

