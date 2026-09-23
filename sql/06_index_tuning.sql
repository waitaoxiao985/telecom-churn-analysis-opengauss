-- =====================================================================
-- 06_index_tuning.sql · 复合索引优化 + 执行计划对比（数据库维护能力项）
-- 执行: docker exec -u omm opengauss gsql -d telecom -f /sql/06_index_tuning.sql
--
-- 业务场景：运营侧高频圈选查询 —— "月付合约 + 入网 12 个月以内的新客"
--   （新客是流失最高发群体，首年关怀活动的固定圈选口径）
-- 优化思路：WHERE contract = ? AND tenure <= ? 是"等值 + 范围"组合，
--   复合索引 (contract, tenure) 的列顺序 = 等值列在前、范围列在后，
--   这样两列都能用上（顺序反了只能用到第一列 —— 面试高频考点）。
-- =====================================================================

-- 圈选查询（前后用同一条 SQL 对比）
-- Q1: 按 tenure 明细统计新客月费与流失情况
EXPLAIN (ANALYZE, BUFFERS)
SELECT tenure,
       COUNT(*)                                   AS 用户数,
       ROUND(AVG(monthly_charges)::numeric, 2)    AS 平均月费,
       SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS 流失人数
FROM user_churn
WHERE contract = 'Month-to-month'
  AND tenure <= 12
GROUP BY tenure
ORDER BY tenure;

-- Q2: 点查场景（按主键/业务键定位单个用户）
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM user_churn WHERE customer_id = '7590-VHVEG';

-- ------------------------------------------------------------------
-- 优化动作：创建复合索引 + 刷新统计信息
-- ------------------------------------------------------------------
CREATE INDEX idx_contract_tenure ON user_churn (contract, tenure);
ANALYZE user_churn;

-- 优化后：再次查看执行计划
EXPLAIN (ANALYZE, BUFFERS)
SELECT tenure,
       COUNT(*)                                   AS 用户数,
       ROUND(AVG(monthly_charges)::numeric, 2)    AS 平均月费,
       SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS 流失人数
FROM user_churn
WHERE contract = 'Month-to-month'
  AND tenure <= 12
GROUP BY tenure
ORDER BY tenure;

-- ------------------------------------------------------------------
-- 补充实验：小表场景的优化器行为分析（报告"踩坑实录"章节）
-- 7043 行的小表上，优化器可能仍选顺序扫描（成本模型认为全表扫更快，
-- 这不是索引失效！）。强制关闭顺序扫描可见索引计划：
--   结论写进报告：生产千万级表上复合索引必然生效，小表上的"不走索引"
--   是优化器的正确选择 —— 理解成本模型比背结论更重要。
-- ------------------------------------------------------------------
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT tenure, COUNT(*)
FROM user_churn
WHERE contract = 'Month-to-month' AND tenure <= 12
GROUP BY tenure
ORDER BY tenure;
RESET enable_seqscan;

-- 索引清单确认
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'user_churn';
