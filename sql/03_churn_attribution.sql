-- =====================================================================
-- 03_churn_attribution.sql · 流失归因分析（纯 SQL）
-- 执行: docker exec -u omm opengauss gsql -d telecom -f /sql/03_churn_attribution.sql
--
-- 方法论（报告核心章节）：
--   流失率  = 该群体内流失占比（群体自己跟自己比）
--   Lift    = 群体流失率 / 整体流失率（>1 说明高于大盘，是风险信号）
--   贡献度  = 该群体流失人数 / 全部流失人数（>它的用户占比，说明是流失"大头"）
--   归因要同时看 Lift（谁最危险）和 贡献度（谁是大头），只看一个会误判！
-- =====================================================================

-- 0) 基准：整体流失率（后面所有 Lift 的分母）
CREATE OR REPLACE VIEW v_overall AS
SELECT COUNT(*)::numeric                          AS total_users,
       SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END)::numeric AS churn_users,
       AVG(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0 END)        AS churn_rate
FROM user_churn;

SELECT '【基准】整体流失率' AS section,
       total_users, churn_users, ROUND(churn_rate * 100, 2) AS churn_rate_pct
FROM v_overall;

-- 1) 各维度流失率 / Lift / 贡献度 —— 汇总成一张归因宽表
CREATE OR REPLACE VIEW v_churn_attribution AS
WITH per_dim AS (
    SELECT 'contract' AS dim, contract AS val, * FROM user_churn
    UNION ALL SELECT 'internet_service',  internet_service,  * FROM user_churn
    UNION ALL SELECT 'payment_method',    payment_method,    * FROM user_churn
    UNION ALL SELECT 'multiple_lines',    multiple_lines,    * FROM user_churn
    UNION ALL SELECT 'online_security',   online_security,   * FROM user_churn
    UNION ALL SELECT 'online_backup',     online_backup,     * FROM user_churn
    UNION ALL SELECT 'device_protection', device_protection, * FROM user_churn
    UNION ALL SELECT 'tech_support',      tech_support,      * FROM user_churn
    UNION ALL SELECT 'streaming_tv',      streaming_tv,      * FROM user_churn
    UNION ALL SELECT 'streaming_movies',  streaming_movies,  * FROM user_churn
    UNION ALL SELECT 'paperless_billing', paperless_billing, * FROM user_churn
    UNION ALL SELECT 'gender',            gender,            * FROM user_churn
    UNION ALL SELECT 'senior_citizen',    senior_citizen::text, * FROM user_churn
    UNION ALL SELECT 'partner',           partner,           * FROM user_churn
    UNION ALL SELECT 'dependents',        dependents,        * FROM user_churn
    UNION ALL SELECT 'tenure_band',
           CASE WHEN tenure <= 6  THEN 'a. 0-6月(新客)'
                WHEN tenure <= 12 THEN 'b. 7-12月'
                WHEN tenure <= 24 THEN 'c. 13-24月'
                WHEN tenure <= 48 THEN 'd. 25-48月'
                ELSE 'e. 49-72月(老客)' END, * FROM user_churn
    UNION ALL SELECT 'monthly_band',
           CASE WHEN monthly_charges < 35.5  THEN 'a. 低(<35.5)'
                WHEN monthly_charges < 70.35 THEN 'b. 中(35.5-70.35)'
                ELSE 'c. 高(>=70.35)' END, * FROM user_churn
)
SELECT dim                                    AS 维度,
       val                                    AS 取值,
       COUNT(*)                               AS 用户数,
       SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS 流失人数,
       ROUND(AVG(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0 END) * 100, 2) AS 流失率pct,
       ROUND(AVG(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0 END)
             / (SELECT churn_rate FROM v_overall), 2)                   AS Lift,
       ROUND(100.0 * SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END)
             / (SELECT churn_users FROM v_overall), 2)                  AS 流失贡献度pct
FROM per_dim
GROUP BY dim, val;

-- 归因结果：按 Lift 降序看"谁最危险"
SELECT * FROM v_churn_attribution ORDER BY Lift DESC, 用户数 DESC;

-- 2) 贡献度 Top10：按"贡献度"降序看"流失大头在哪"
SELECT * FROM v_churn_attribution
WHERE 取值 NOT LIKE '0'  -- 排除 senior_citizen=0 等基准组噪音
ORDER BY 流失贡献度pct DESC
LIMIT 10;

-- 3) 高危组合画像：月付 + 光纤 + 电子支票（文献与业界公认三大风险因子）
SELECT '月付+光纤+电子支票' AS 风险组合, COUNT(*) AS 用户数,
       SUM(CASE WHEN churn='Yes' THEN 1 ELSE 0 END) AS 流失人数,
       ROUND(AVG(CASE WHEN churn='Yes' THEN 1.0 ELSE 0 END) * 100, 2) AS 流失率pct
FROM user_churn
WHERE contract = 'Month-to-month'
  AND internet_service = 'Fiber optic'
  AND payment_method = 'Electronic check'
UNION ALL
SELECT '月付+光纤+电子支票+无技术支持', COUNT(*),
       SUM(CASE WHEN churn='Yes' THEN 1 ELSE 0 END),
       ROUND(AVG(CASE WHEN churn='Yes' THEN 1.0 ELSE 0 END) * 100, 2)
FROM user_churn
WHERE contract = 'Month-to-month'
  AND internet_service = 'Fiber optic'
  AND payment_method = 'Electronic check'
  AND tech_support = 'No'
UNION ALL
SELECT '全体用户', COUNT(*),
       SUM(CASE WHEN churn='Yes' THEN 1 ELSE 0 END),
       ROUND(AVG(CASE WHEN churn='Yes' THEN 1.0 ELSE 0 END) * 100, 2)
FROM user_churn;
