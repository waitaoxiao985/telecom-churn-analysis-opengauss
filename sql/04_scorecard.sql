-- =====================================================================
-- 流失风险评分卡（自动生成，勿手工修改）
-- 来源模型 : LogisticRegression(penalty=l1)   run_id=134fb40a747a45ae8a2239666c0cff40
-- 测试集表现: accuracy=0.7644
--   流失类(1): precision=0.548
--              recall=0.639
-- 公式     : risk_score = 1 / (1 + exp(-(b0 + Σ bi*xi)))
-- 生成工具 : tools/export_scorecard.py
-- =====================================================================
CREATE OR REPLACE VIEW v_user_risk_score AS
SELECT
    customer_id,
    1.0 / (1.0 + exp(-(
    2.261200 +
    -0.138460 * senior_citizen::numeric +
    -0.085622 * tenure::numeric +
    -0.342283 * monthly_charges::numeric +
    0.000552 * total_charges::numeric +
    0.314415 * (CASE WHEN gender = 'Male' THEN 1 ELSE 0 END) +
    0.166771 * (CASE WHEN partner = 'Yes' THEN 1 ELSE 0 END) +
    -0.153544 * (CASE WHEN dependents = 'Yes' THEN 1 ELSE 0 END) +
    11.903380 * (CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END) +
    5.721693 * (CASE WHEN multiple_lines = 'No phone service' THEN 1 ELSE 0 END) +
    2.058948 * (CASE WHEN multiple_lines = 'Yes' THEN 1 ELSE 0 END) +
    9.353424 * (CASE WHEN internet_service = 'Fiber optic' THEN 1 ELSE 0 END) +
    -1.273585 * (CASE WHEN internet_service = 'No' THEN 1 ELSE 0 END) +
    -1.159832 * (CASE WHEN online_security = 'No internet service' THEN 1 ELSE 0 END) +
    1.308363 * (CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END) +
    -1.917897 * (CASE WHEN online_backup = 'No internet service' THEN 1 ELSE 0 END) +
    1.538495 * (CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END) +
    -1.163671 * (CASE WHEN device_protection = 'No internet service' THEN 1 ELSE 0 END) +
    1.663749 * (CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END) +
    -1.108181 * (CASE WHEN tech_support = 'No internet service' THEN 1 ELSE 0 END) +
    1.313918 * (CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END) +
    -1.095976 * (CASE WHEN streaming_tv = 'No internet service' THEN 1 ELSE 0 END) +
    3.502547 * (CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END) +
    -1.105462 * (CASE WHEN streaming_movies = 'No internet service' THEN 1 ELSE 0 END) +
    3.536535 * (CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END) +
    -0.394707 * (CASE WHEN contract = 'One year' THEN 1 ELSE 0 END) +
    -0.812075 * (CASE WHEN contract = 'Two year' THEN 1 ELSE 0 END) +
    0.705020 * (CASE WHEN paperless_billing = 'Yes' THEN 1 ELSE 0 END) +
    0.666483 * (CASE WHEN payment_method = 'Credit card (automatic)' THEN 1 ELSE 0 END) +
    1.183607 * (CASE WHEN payment_method = 'Electronic check' THEN 1 ELSE 0 END) +
    0.861383 * (CASE WHEN payment_method = 'Mailed check' THEN 1 ELSE 0 END)
    ))) AS risk_score
FROM user_churn;

COMMENT ON VIEW v_user_risk_score IS '流失风险评分卡视图：LR模型系数下沉为SQL，risk_score为流失概率';
