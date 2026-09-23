# 基于 openGauss 的运营商用户流失归因与价值分层分析

> 一句话：用 **纯 SQL** 在信创栈（openEuler + openGauss）上完成 7,043 户流失归因、价值分层、
> 风险×价值圈人，把机器学习评分卡下沉成 SQL 视图，产出可直接交运营的 P0 挽留名单。
> 附完整中文分析报告（Markdown + Word）。

本 README 解决一个问题：**以后怎么用这个项目**（日常查询 / 换机器重建 / 模型更新 / 报告再生成）。

> 🔒 本仓库已做**密码脱敏**：文中所有 `<...>` 占位符（如 `<VM_ROOT_PASSWORD>`、`<DB_PASSWORD>`）
> 在部署时替换成你自己的密码即可，真实密码一律不入库。

---

## 1. 目录结构

```
vm_staging_telecom-analytics/
├── README.md                 ← 本文件
├── sql/                      ← 全部数据库脚本（按编号顺序执行）
│   ├── 01a_cluster.sql       建库 telecom + 业务账号（一次性，⚠️ 内含旧密码见 §6）
│   ├── 01b_schema.sql        staging 表 + 分析宽表（PK/CHECK/COMMENT）
│   ├── 02_etl.sql            \copy 灌数 + TotalCharges 脏数据清洗 + 质量校验
│   ├── 03_churn_attribution.sql  17 维流失归因视图（Lift / 贡献度）
│   ├── 04_scorecard.sql      ⭐SQL 评分卡视图（自动生成，勿手改，见 §5）
│   ├── 05_value_tiering.sql  价值三档分层 + 风险×价值矩阵 + P0 挽留名单
│   └── 06_index_tuning.sql   复合索引 + EXPLAIN ANALYZE 前后对比
├── tools/
│   ├── export_scorecard.py   模型 → 04_scorecard.sql 一键生成器
│   └── md2docx.py            Markdown → Word 转换器
├── 报告-运营商用户流失归因与价值分层分析.md    ← 分析报告（Markdown）
└── 报告-运营商用户流失归因与价值分层分析.docx  ← 分析报告（Word）
```

## 2. 运行环境（本项目现成的这套）

| 项 | 值 |
|---|---|
| 虚拟机 | 192.168.159.134（openEuler 24.03 LTS，root / `<VM_ROOT_PASSWORD>`） |
| 数据库 | openGauss 6.0.6 单机，数据目录 `/opt/openGauss-simple/server/data/single_node` |
| 数据库 / 端口 | `telecom`（UTF8）/ 5432 |
| 业务账号 | `carrier_analyst` / **`<DB_PASSWORD>`** |
| 运维账号 | OS 用户 `omm`（gsql 免密本地登录） |
| 脚本位置（VM 上） | `/home/omm/sql/`，CSV 在 `/home/omm/WA_Fn-UseC_-Telco-Customer-Churn.csv` |
| 数据集 | IBM Telco Customer Churn：7,043 行 × 21 列 |

启动数据库（如果虚拟机重启后连不上）：

```bash
ssh root@192.168.159.134
su - omm
gs_ctl start -D /opt/openGauss-simple/server/data/single_node -Z single_node
```

## 3. 日常怎么用（最高频）

```bash
ssh root@192.168.159.134        # 登虚拟机
su - omm                        # 切 omm（数据库运维身份）
gsql -d telecom -p 5432 -U carrier_analyst    # 连库，密码 <DB_PASSWORD>
```

进 gsql 后的常用查询（记住纪律：**先 count 再 limit 看明细**，7043 行会刷屏）：

```sql
-- 全盘概况（7043 户 / 流失 1869 / 26.54%）
SELECT * FROM v_overall;

-- 流失归因 17 维：按 Lift 降序看谁最危险
SELECT * FROM v_churn_attribution ORDER BY lift DESC;

-- 风险 × 价值 2×2 矩阵
SELECT * FROM v_risk_value_matrix ORDER BY value_tier, risk_level;

-- P0 优先挽留名单（297 户）
SELECT COUNT(*) FROM retention_priority_list;
SELECT * FROM retention_priority_list ORDER BY risk_score DESC LIMIT 15;

-- 查单个用户：流失概率 / 价值分层
SELECT * FROM v_user_risk_score  WHERE customer_id = '7590-VHVEG';
SELECT * FROM v_value_tier       WHERE customer_id = '7590-VHVEG';

-- 自定义圈选示例：高风险的新客名单
SELECT r.customer_id, r.risk_score, c.tenure, c.monthly_charges
FROM v_user_risk_score r JOIN user_churn c USING (customer_id)
WHERE r.risk_score >= 0.8 AND c.tenure <= 6
ORDER BY r.risk_score DESC;

-- 导出 P0 名单给运营（生成 /home/omm/p0_list.csv）
\copy (SELECT * FROM retention_priority_list ORDER BY risk_score DESC) TO '/home/omm/p0_list.csv' WITH CSV HEADER
```

其他小抄：`\dv` 看所有视图，`\dt` 看表，`\d user_churn` 看表结构，`\q` 退出。

## 4. 换新虚拟机 / 从零重建

1. **装 openGauss 6.0.6**（极简安装）：
   - 下载：`https://opengauss.obs.cn-south-1.myhuaweicloud.com/6.0.6/openEuler24.03/x86/openGauss-All-6.0.6-openEuler24.03-x86_64.tar.gz`
   - 前置：`yum install -y openblas`（缺它 gs_initdb 会报 `libopenblas.so.0` 找不到）；系统没有 `tar` 就用 `python3 -m tarfile -e <包> <目录>`
   - 以 **omm** 用户执行：`echo no | sh install.sh -w <密码>`（root 跑会被拒；`echo no` 必须有，否则 demo 提示会卡死）
   - ⚠️ 结尾显示 exit 1 是正常的（`Input no, operation skip.`），用 gsql 连上验证即可
2. **传文件**：本目录 `sql/` → VM `/home/omm/sql/`，数据集 CSV → VM `/home/omm/`，然后 `chown -R omm:omm /home/omm/sql /home/omm/*.csv`
3. **按顺序执行**（每步确认成功再下一步）：

```bash
su - omm
gsql -d postgres -p 5432 -f /home/omm/sql/01a_cluster.sql     # 建库+建用户
gsql -d telecom -p 5432 -c "ALTER USER carrier_analyst PASSWORD '<DB_PASSWORD>';"   # ⚠️ 必做：01a 里是占位符
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/01b_schema.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/02_etl.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/03_churn_attribution.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/04_scorecard.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/05_value_tiering.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/06_index_tuning.sql
```

4. **验收**：`SELECT * FROM v_overall;` 应显示 7043 / 1869 / 26.54%；`SELECT COUNT(*) FROM retention_priority_list;` 应为 297。

## 5. 模型重训后怎么更新评分卡

`04_scorecard.sql` 是**生成物**（LR 系数固化成 SQL），重训模型后要重新生成：

1. 在 ML 项目（`telecom-customer-churn-prediction`，模型产物含 `reports/best_model.json` + `mlruns/.../model.pkl`）训练出新模型；
2. 跑生成器（会自动读最佳 run 的系数并**覆盖** `sql/04_scorecard.sql`）：

```bash
python tools/export_scorecard.py
```

3. 把新的 `04_scorecard.sql` 放到 VM 执行，**然后必须重跑 05**（P0 名单要用新风险分重新落表）：

```bash
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/04_scorecard.sql
gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/05_value_tiering.sql
```

4. 报告里的数字（P0 人数、矩阵等）同步更新。

## 6. 报告再生成（改了 .md 想重新出 Word）

```powershell
E:\CTF\conda\python.exe tools\md2docx.py "报告-运营商用户流失归因与价值分层分析.md" "报告-运营商用户流失归因与价值分层分析.docx"
```

## 7. 踩坑备忘（都是实际遇到的）

| 坑 | 结论 |
|---|---|
| openGauss 密码设不进 | 默认策略：≥8 位且大写/小写/数字/符号 4 类占 3 类 |
| install.sh 最后 exit 1 | 答 `no` 跳过 demo 导入的正常现象，别当失败 |
| 02_etl.sql 报 CSV 找不到 | `\copy` 走 gsql **客户端**路径，CSV 必须先放到 `/home/omm/` |
| `select * from v_value_tier` 刷屏 | 明细 7043 行！一律先 `count(*)` 再 `limit 15` |
| 05 报 `v_user_risk_score does not exist` | 必须**先跑 04 再跑 05**（05 的矩阵/名单依赖风险分视图） |
| 重建时密码又变回旧的 | `01a_cluster.sql` 里是占位符 `<DB_PASSWORD>`，按 §4 的 ALTER 命令设置真实密码 |
| `enable_seqscan = off` | 只是演示索引计划可用，**不是**常规性能手段；小表不走索引往往是优化器的正确选择 |
| 报告口径 | 业务结论以 Lift 归因为准；评分卡系数受共线性影响只做排序、不做因果解读 |

## 8. 面试一句话讲法

> "在 openEuler + openGauss 信创环境用纯 SQL 完成 7,043 户流失分析：17 维 Lift/贡献度归因定位
> 月付合约（贡献 88.55% 流失）与新客期（Lift 1.99）两大风险源；三维规则评分做价值分层，
> 与 LR 评分卡（30 系数下沉为 SQL 视图）交叉出 297 人 P0 挽留名单；配套 ETL 质检、
> 复合索引调优与 EXPLAIN ANALYZE 实录。"

核心数据：流失率 26.54%｜月付 Lift 1.61｜新客 0-6 月 Lift 1.99｜安全服务粘性 -27pp｜高价值 1,919 户｜P0 297 户｜模型 accuracy 0.7644｜索引代价 -18.8%。
