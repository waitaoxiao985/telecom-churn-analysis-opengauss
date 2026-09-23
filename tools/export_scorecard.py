# -*- coding: utf-8 -*-
"""
[构建期工具] 评分卡导出：把 ML 项目（~/telecom-churn）训练的最优逻辑回归模型
系数导出为纯 SQL 评分卡（sql/04_scorecard.sql）。

为什么这么做？
  运营商生产环境常把流失风险评分"下沉"到数据库——用一条 SQL 直接算出
  每个用户的风险分，不依赖 Python 服务。逻辑回归天然可解释：
      p = 1 / (1 + exp(-(b0 + b1*x1 + ... + bn*xn)))
  所以模型 = 一组系数，可以翻译成 SQL 表达式。

运行（使用 ML 项目的虚拟环境）：
  ~/telecom-churn/.venv/bin/python tools/export_scorecard.py
"""
import json
import pickle
from pathlib import Path

CHURN_DIR = Path.home() / "telecom-churn"
OUT_SQL = Path(__file__).resolve().parents[1] / "sql" / "04_scorecard.sql"

# ------------------------------------------------------------------
# 特征名 -> SQL 表达式 的映射
# 数值特征直接取列；类别特征的哑变量用 CASE WHEN 还原
# （对应 data_prep.py 的 pd.get_dummies(drop_first=True) 逻辑：
#   参考类 = 每个类别变量字典序第一个取值，哑变量=1 表示"非参考类"）
# ------------------------------------------------------------------
FEATURE_TO_SQL = {
    # 数值特征（原样入模）
    "SeniorCitizen":    "senior_citizen::numeric",
    "tenure":           "tenure::numeric",
    "MonthlyCharges":   "monthly_charges::numeric",
    "TotalCharges":     "total_charges::numeric",
    # 用户画像哑变量
    "gender_Male":              "(CASE WHEN gender = 'Male' THEN 1 ELSE 0 END)",
    "Partner_Yes":              "(CASE WHEN partner = 'Yes' THEN 1 ELSE 0 END)",
    "Dependents_Yes":           "(CASE WHEN dependents = 'Yes' THEN 1 ELSE 0 END)",
    "PhoneService_Yes":         "(CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END)",
    # 增值服务哑变量（参考类均为 'No'）
    "MultipleLines_No_phone_service": "(CASE WHEN multiple_lines = 'No phone service' THEN 1 ELSE 0 END)",
    "MultipleLines_Yes":             "(CASE WHEN multiple_lines = 'Yes' THEN 1 ELSE 0 END)",
    "InternetService_Fiber_optic":   "(CASE WHEN internet_service = 'Fiber optic' THEN 1 ELSE 0 END)",
    "InternetService_No":            "(CASE WHEN internet_service = 'No' THEN 1 ELSE 0 END)",
    "OnlineSecurity_No_internet_service": "(CASE WHEN online_security = 'No internet service' THEN 1 ELSE 0 END)",
    "OnlineSecurity_Yes":                 "(CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END)",
    "OnlineBackup_No_internet_service":   "(CASE WHEN online_backup = 'No internet service' THEN 1 ELSE 0 END)",
    "OnlineBackup_Yes":                   "(CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END)",
    "DeviceProtection_No_internet_service": "(CASE WHEN device_protection = 'No internet service' THEN 1 ELSE 0 END)",
    "DeviceProtection_Yes":                 "(CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END)",
    "TechSupport_No_internet_service":  "(CASE WHEN tech_support = 'No internet service' THEN 1 ELSE 0 END)",
    "TechSupport_Yes":                  "(CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END)",
    "StreamingTV_No_internet_service":  "(CASE WHEN streaming_tv = 'No internet service' THEN 1 ELSE 0 END)",
    "StreamingTV_Yes":                  "(CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END)",
    "StreamingMovies_No_internet_service": "(CASE WHEN streaming_movies = 'No internet service' THEN 1 ELSE 0 END)",
    "StreamingMovies_Yes":                 "(CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END)",
    # 合同/账单哑变量
    "Contract_One_year":        "(CASE WHEN contract = 'One year' THEN 1 ELSE 0 END)",
    "Contract_Two_year":        "(CASE WHEN contract = 'Two year' THEN 1 ELSE 0 END)",
    "PaperlessBilling_Yes":     "(CASE WHEN paperless_billing = 'Yes' THEN 1 ELSE 0 END)",
    "PaymentMethod_Credit_card__automatic_": "(CASE WHEN payment_method = 'Credit card (automatic)' THEN 1 ELSE 0 END)",
    "PaymentMethod_Electronic_check":        "(CASE WHEN payment_method = 'Electronic check' THEN 1 ELSE 0 END)",
    "PaymentMethod_Mailed_check":            "(CASE WHEN payment_method = 'Mailed check' THEN 1 ELSE 0 END)",
}


def main():
    best = json.loads((CHURN_DIR / "reports" / "best_model.json").read_text(encoding="utf-8"))
    run_id, name = best["best_run_id"], best["best_model_name"]
    model_path = CHURN_DIR / "mlruns" / "1" / run_id / "artifacts" / f"model_{name}" / "model.pkl"
    model = pickle.loads(model_path.read_bytes())

    feats = list(model.feature_names_in_)
    coefs = list(model.coef_[0])
    intercept = float(model.intercept_[0])

    missing = [f for f in feats if f not in FEATURE_TO_SQL]
    if missing:
        raise SystemExit(f"特征映射缺失，请补充 FEATURE_TO_SQL: {missing}")

    # 生成 SQL
    terms = [f"    {c:.6f} * {FEATURE_TO_SQL[f]}" for f, c in zip(feats, coefs) if abs(c) > 1e-9]
    linear_expr = f"{intercept:.6f} +\n" + " +\n".join(terms)

    sql = f"""-- =====================================================================
-- 流失风险评分卡（自动生成，勿手工修改）
-- 来源模型 : LogisticRegression(penalty={name})   run_id={run_id}
-- 测试集表现: accuracy={best['metrics']['accuracy']:.4f}
--   流失类(1): precision={best['metrics']['1']['precision']:.3f}
--              recall={best['metrics']['1']['recall']:.3f}
-- 公式     : risk_score = 1 / (1 + exp(-(b0 + Σ bi*xi)))
-- 生成工具 : tools/export_scorecard.py
-- =====================================================================
CREATE OR REPLACE VIEW v_user_risk_score AS
SELECT
    customer_id,
    1.0 / (1.0 + exp(-(
{linear_expr}
    ))) AS risk_score
FROM user_churn;

COMMENT ON VIEW v_user_risk_score IS '流失风险评分卡视图：LR模型系数下沉为SQL，risk_score为流失概率';
"""
    OUT_SQL.write_text(sql, encoding="utf-8")
    print(f"评分卡 SQL 已生成: {OUT_SQL}")
    print(f"模型: penalty={name}, run_id={run_id}, 特征数={len(feats)}, 非零系数={sum(1 for c in coefs if abs(c) > 1e-9)}")
    print(f"截距 b0 = {intercept:.6f}")


if __name__ == "__main__":
    main()
