-- =====================================================================
-- 05_value_tiering.sql · 客户价值分层 + 风险×价值 优先挽留名单
-- 执行: docker exec -u omm opengauss gsql -d telecom -f /sql/05_value_tiering.sql
--
-- 方法论：可解释的规则评分卡（电信分群常用做法，避免黑盒）
--   tenure_score  在网时长贡献    （在网越久，存量价值越高）
--   charge_score  月费贡献        （ARPU 越高，收入贡献越大）
--   service_score 增值服务粘性    （办的业务越多，换网成本越高）
--   value_score = 三项之和(3~15) -> 韭/中/高价值三档
--
-- 再与 04 的风险评分卡交叉 -> 2x2 矩阵：
--   高价值 x 高风险 = P0 优先挽留名单（花最多钱挽留这群人最划算）
-- =====================================================================

-- 1) 价值评分与分层
CREATE OR REPLACE VIEW v_user_value_tier AS
SELECT
    customer_id,
    tenure,
    monthly_charges,
    (CASE WHEN tenure <= 6  THEN 1
          WHEN tenure <= 12 THEN 2
          WHEN tenure <= 24 THEN 3
          WHEN tenure <= 48 THEN 4
          ELSE 5 END) AS tenure_score,
    (CASE WHEN monthly_charges < 35.5  THEN 1
          WHEN monthly_charges < 70.35 THEN 2
          WHEN monthly_charges < 90    THEN 3
          WHEN monthly_charges < 105   THEN 4
          ELSE 5 END) AS charge_score,
    ((CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN internet_service <> 'No' THEN 1 ELSE 0 END)
     + (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)
     + (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END)) AS service_cnt,
    (CASE WHEN (CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN internet_service <> 'No' THEN 1 ELSE 0 END)
                + (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END) <= 2 THEN 1
          WHEN (CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN internet_service <> 'No' THEN 1 ELSE 0 END)
                + (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END) <= 4 THEN 2
          WHEN (CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN internet_service <> 'No' THEN 1 ELSE 0 END)
                + (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END) = 5 THEN 3
          WHEN (CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN internet_service <> 'No' THEN 1 ELSE 0 END)
                + (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)
                + (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END) = 6 THEN 4
          ELSE 5 END) AS service_score
FROM user_churn;

-- 分层结果视图
CREATE OR REPLACE VIEW v_value_tier AS
SELECT v.*,
       (v.tenure_score + v.charge_score + v.service_score) AS value_score,
       CASE WHEN v.tenure_score + v.charge_score + v.service_score >= 11 THEN '1-高价值'
            WHEN v.tenure_score + v.charge_score + v.service_score >= 7  THEN '2-中价值'
            ELSE '3-低价值' END AS value_tier
FROM v_user_value_tier v;

SELECT '价值分层分布' AS 报告项;
SELECT value_tier, COUNT(*) AS 用户数,
       ROUND(AVG(monthly_charges), 2) AS 平均月费,
       ROUND(AVG(tenure), 1)          AS 平均在网月数
FROM v_value_tier
GROUP BY value_tier
ORDER BY value_tier;

-- 2) 风险 x 价值 2x2 矩阵（风险评分来自 04_scorecard.sql 的模型视图）
CREATE OR REPLACE VIEW v_risk_value_matrix AS
SELECT t.value_tier,
       CASE WHEN r.risk_score >= 0.5 THEN '1-高风险' ELSE '2-低风险' END AS risk_level,
       COUNT(*) AS 用户数,
       ROUND(AVG(r.risk_score), 4) AS 平均风险分
FROM v_value_tier t
JOIN v_user_risk_score r ON r.customer_id = t.customer_id
GROUP BY t.value_tier,
         CASE WHEN r.risk_score >= 0.5 THEN '1-高风险' ELSE '2-低风险' END;

SELECT '风险 x 价值 2x2 矩阵' AS 报告项;
SELECT * FROM v_risk_value_matrix ORDER BY value_tier, risk_level;

-- 3) P0 优先挽留名单落表（可直接交付运营执行）
DROP TABLE IF EXISTS retention_priority_list;
CREATE TABLE retention_priority_list AS
SELECT c.customer_id,
       t.value_tier,
       ROUND(r.risk_score, 4)      AS risk_score,
       t.value_score,
       c.tenure,
       c.monthly_charges,
       c.total_charges,
       c.contract,
       c.internet_service,
       c.payment_method,
       c.tech_support
FROM user_churn c
JOIN v_user_risk_score r ON r.customer_id = c.customer_id
JOIN v_value_tier     t ON t.customer_id = c.customer_id
WHERE t.value_tier = '1-高价值'
  AND r.risk_score >= 0.5
ORDER BY r.risk_score DESC;

GRANT SELECT ON retention_priority_list TO carrier_analyst;

SELECT 'P0 优先挽留名单(高价值x高风险) 人数' AS 报告项, COUNT(*)::text AS value
FROM retention_priority_list;

SELECT * FROM retention_priority_list LIMIT 10;
