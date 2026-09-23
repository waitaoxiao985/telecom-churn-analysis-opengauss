-- =====================================================================
-- 02_etl.sql · 数据入库与 SQL 端清洗
-- 执行: gsql -d telecom -p 5432 -U carrier_analyst -f /home/omm/sql/02_etl.sql
-- 前置: CSV 放到 /home/omm/WA_Fn-UseC_-Telco-Customer-Churn.csv（\copy 走 gsql 客户端路径）
--
-- 清洗逻辑（对应 ML 项目 data_collection.py 的处理，这里用纯 SQL 实现）：
--   TotalCharges 有 11 行是空格 ' '（= 刚入网未出账的新用户）
--   -> NULLIF(TRIM(x), '') 转成 NULL -> COALESCE 补 0
-- =====================================================================

-- 1) 清空并重灌（可重复执行）
TRUNCATE TABLE stg_telco_churn;
\copy stg_telco_churn FROM '/home/omm/WA_Fn-UseC_-Telco-Customer-Churn.csv' WITH (FORMAT csv, HEADER true)

-- 2) staging -> 业务表（含类型转换与脏数据清洗）
TRUNCATE TABLE user_churn;
INSERT INTO user_churn
SELECT
    customer_id,
    gender,
    senior_citizen::smallint,
    partner,
    dependents,
    tenure::integer,
    phone_service,
    multiple_lines,
    internet_service,
    online_security,
    online_backup,
    device_protection,
    tech_support,
    streaming_tv,
    streaming_movies,
    contract,
    paperless_billing,
    payment_method,
    monthly_charges::numeric,
    COALESCE(NULLIF(TRIM(total_charges), '')::numeric, 0) AS total_charges,  -- 空格 -> 0
    churn
FROM stg_telco_churn;

-- 3) ETL 质量校验（结果写入报告）
SELECT '总行数' AS check_item, COUNT(*)::text AS value FROM user_churn
UNION ALL
SELECT '去重用户数', COUNT(DISTINCT customer_id)::text FROM user_churn
UNION ALL
SELECT 'staging 中 TotalCharges 空格行数（已清洗为0）',
       COUNT(*)::text FROM stg_telco_churn WHERE TRIM(total_charges) = ''
UNION ALL
SELECT 'tenure=0 且 total_charges=0（新入网未出账）',
       COUNT(*)::text FROM user_churn WHERE tenure = 0 AND total_charges = 0
UNION ALL
SELECT '流失用户数', COUNT(*)::text FROM user_churn WHERE churn = 'Yes'
UNION ALL
SELECT '在网用户数', COUNT(*)::text FROM user_churn WHERE churn = 'No';
