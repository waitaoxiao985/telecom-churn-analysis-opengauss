-- =====================================================================
-- 01b_schema.sql · 表结构设计（openGauss）
-- 执行: docker exec -u omm opengauss gsql -d telecom -f /sql/01b_schema.sql
--
-- 设计要点（面试可讲）：
--   1. staging 表（全文本） ->  业务表（强类型） 的经典 ETL 分层
--   2. 主键 + CHECK 约束守住数据质量底线
--   3. 每个字段都有 COMMENT —— 运营商数据字典的规范做法
-- =====================================================================

-- ------------------------------------------------------------------
-- 1. staging 层：原样承接 CSV（全 varchar/text），不挑数据毛病
--    列顺序 = CSV 列顺序，便于 \copy 按位置灌入
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS stg_telco_churn;
CREATE TABLE stg_telco_churn (
    customer_id       text,
    gender            text,
    senior_citizen    text,
    partner           text,
    dependents        text,
    tenure            text,
    phone_service     text,
    multiple_lines    text,
    internet_service  text,
    online_security   text,
    online_backup     text,
    device_protection text,
    tech_support      text,
    streaming_tv      text,
    streaming_movies  text,
    contract          text,
    paperless_billing text,
    payment_method    text,
    monthly_charges   text,
    total_charges     text,
    churn             text
);

-- ------------------------------------------------------------------
-- 2. 业务层：强类型 + 约束 + 注释
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS user_churn CASCADE;
CREATE TABLE user_churn (
    customer_id       varchar(20)   PRIMARY KEY,
    gender            varchar(10)   NOT NULL,
    senior_citizen    smallint      NOT NULL CHECK (senior_citizen IN (0, 1)),
    partner           varchar(5)    NOT NULL,
    dependents        varchar(5)    NOT NULL,
    tenure            integer       NOT NULL CHECK (tenure >= 0),
    phone_service     varchar(5)    NOT NULL,
    multiple_lines    varchar(20)   NOT NULL,
    internet_service  varchar(20)   NOT NULL,
    online_security   varchar(20)   NOT NULL,
    online_backup     varchar(20)   NOT NULL,
    device_protection varchar(20)   NOT NULL,
    tech_support      varchar(20)   NOT NULL,
    streaming_tv      varchar(20)   NOT NULL,
    streaming_movies  varchar(20)   NOT NULL,
    contract          varchar(20)   NOT NULL CHECK (contract IN ('Month-to-month', 'One year', 'Two year')),
    paperless_billing varchar(5)    NOT NULL,
    payment_method    varchar(30)   NOT NULL,
    monthly_charges   numeric(8, 2) NOT NULL CHECK (monthly_charges >= 0),
    total_charges     numeric(10, 2) NOT NULL CHECK (total_charges >= 0),
    churn             varchar(5)    NOT NULL CHECK (churn IN ('Yes', 'No'))
);

COMMENT ON TABLE  user_churn IS '电信用户流失分析宽表：7043 用户，来自 IBM Telco 公开数据集';
COMMENT ON COLUMN user_churn.customer_id       IS '用户ID（业务主键）';
COMMENT ON COLUMN user_churn.gender            IS '性别';
COMMENT ON COLUMN user_churn.senior_citizen    IS '是否老年用户：1-是 0-否';
COMMENT ON COLUMN user_churn.partner           IS '是否有伴侣';
COMMENT ON COLUMN user_churn.dependents        IS '是否有家属';
COMMENT ON COLUMN user_churn.tenure            IS '在网月数（入网时长）';
COMMENT ON COLUMN user_churn.phone_service     IS '是否开通电话服务';
COMMENT ON COLUMN user_churn.multiple_lines    IS '是否开通多线路';
COMMENT ON COLUMN user_churn.internet_service  IS '网络接入方式：DSL/Fiber optic/No';
COMMENT ON COLUMN user_churn.online_security   IS '是否开通网络安全增值服务';
COMMENT ON COLUMN user_churn.online_backup     IS '是否开通在线备份';
COMMENT ON COLUMN user_churn.device_protection IS '是否开通设备保修';
COMMENT ON COLUMN user_churn.tech_support      IS '是否开通技术支持';
COMMENT ON COLUMN user_churn.streaming_tv      IS '是否开通流媒体电视';
COMMENT ON COLUMN user_churn.streaming_movies  IS '是否开通流媒体电影';
COMMENT ON COLUMN user_churn.contract          IS '合约类型：月付/一年/两年';
COMMENT ON COLUMN user_churn.paperless_billing IS '是否电子账单';
COMMENT ON COLUMN user_churn.payment_method    IS '支付方式';
COMMENT ON COLUMN user_churn.monthly_charges   IS '月费（元）';
COMMENT ON COLUMN user_churn.total_charges     IS '历史总消费（元）';
COMMENT ON COLUMN user_churn.churn             IS '是否流失（标签）：Yes-流失 No-在网';

-- ------------------------------------------------------------------
-- 3. 业务账号授权（DDL 完成后收权：只读分析）
-- ------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO carrier_analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO carrier_analyst;
