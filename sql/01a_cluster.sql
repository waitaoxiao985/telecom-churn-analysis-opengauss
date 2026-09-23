-- =====================================================================
-- 01a_cluster.sql · 集群级对象：建库、建业务用户、授权
-- 执行: gsql -d postgres -p 5432 -f /home/omm/sql/01a_cluster.sql  (以 omm 身份)
-- =====================================================================

-- 业务数据库
CREATE DATABASE telecom OWNER omm;

-- 业务账号（最小权限原则：分析账号只给 CONNECT / SELECT / EXECUTE）
-- 密码脱敏: 部署时把 <DB_PASSWORD> 替换为你自己的密码(openGauss 策略: ≥8 位, 大写/小写/数字/符号 4 类占 3 类)
CREATE USER carrier_analyst WITH PASSWORD '<DB_PASSWORD>' SYSADMIN NOCREATEDB;
GRANT CONNECT ON DATABASE telecom TO carrier_analyst;
