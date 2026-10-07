-- A1 | Cart leakage and repeat cohorts | Databricks SQL (Free Edition), catalog workspace, schema cart_leakage
-- These are the queries exactly as run, in order.

-- 1. Load all 5 monthly CSVs from the volume
CREATE OR REPLACE TABLE workspace.cart_leakage.events_raw AS
SELECT * FROM read_files('/Volumes/workspace/cart_leakage/raw/',
  format => 'csv', header => true, pathGlobFilter => '*.csv',
  schema => 'event_time STRING, event_type STRING, product_id BIGINT, category_id BIGINT, category_code STRING, brand STRING, price DOUBLE, user_id BIGINT, user_session STRING');

-- 2. Check the load: event mix
SELECT event_type, COUNT(*) AS n FROM workspace.cart_leakage.events_raw GROUP BY event_type ORDER BY n DESC;

-- 3. Profile the dirt
SELECT COUNT(*) AS total_rows,
  COUNT(*) - COUNT(DISTINCT event_time, event_type, product_id, user_id, user_session) AS duplicate_rows,
  SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END) AS bad_price_rows,
  SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS null_user_rows,
  SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS null_brand_rows,
  SUM(CASE WHEN category_code IS NULL THEN 1 ELSE 0 END) AS null_category_code_rows
FROM workspace.cart_leakage.events_raw;

-- 4. Clean events table
CREATE OR REPLACE TABLE workspace.cart_leakage.events AS
SELECT DISTINCT to_timestamp(replace(event_time, ' UTC', '')) AS event_ts, event_type, product_id, category_id,
  COALESCE(category_code, concat('cat_', category_id)) AS category, COALESCE(brand, 'unknown') AS brand,
  price, user_id, user_session
FROM workspace.cart_leakage.events_raw WHERE price IS NOT NULL AND price > 0;

-- 5. Overall funnel (users and sessions)
WITH counts AS (
  SELECT COUNT(DISTINCT CASE WHEN event_type='view' THEN user_id END) AS users_viewed,
         COUNT(DISTINCT CASE WHEN event_type='cart' THEN user_id END) AS users_carted,
         COUNT(DISTINCT CASE WHEN event_type='purchase' THEN user_id END) AS users_purchased,
         COUNT(DISTINCT CASE WHEN event_type='view' THEN user_session END) AS sessions_viewed,
         COUNT(DISTINCT CASE WHEN event_type='cart' THEN user_session END) AS sessions_carted,
         COUNT(DISTINCT CASE WHEN event_type='purchase' THEN user_session END) AS sessions_purchased
  FROM workspace.cart_leakage.events)
SELECT *, ROUND(users_carted/users_viewed,3) AS user_view_to_cart, ROUND(users_purchased/users_carted,3) AS user_cart_to_purchase,
  ROUND(sessions_carted/sessions_viewed,3) AS session_view_to_cart, ROUND(sessions_purchased/sessions_carted,3) AS session_cart_to_purchase
FROM counts;

-- 6. Funnel by brand
SELECT brand,
  COUNT(DISTINCT CASE WHEN event_type='view' THEN user_id END) AS users_viewed,
  COUNT(DISTINCT CASE WHEN event_type='cart' THEN user_id END) AS users_carted,
  COUNT(DISTINCT CASE WHEN event_type='purchase' THEN user_id END) AS users_purchased,
  ROUND(COUNT(DISTINCT CASE WHEN event_type='purchase' THEN user_id END) / COUNT(DISTINCT CASE WHEN event_type='cart' THEN user_id END), 3) AS cart_to_purchase
FROM workspace.cart_leakage.events GROUP BY brand HAVING users_carted >= 5000 ORDER BY users_carted DESC LIMIT 15;

-- 7. Abandoned carts: carted, same user did not buy same product within 7 days (last 7 days of data excluded)
CREATE OR REPLACE TABLE workspace.cart_leakage.cart_outcomes AS
WITH carts AS (
  SELECT user_id, product_id, category, brand, MAX(price) AS price, MIN(event_ts) AS cart_ts
  FROM workspace.cart_leakage.events WHERE event_type = 'cart'
  GROUP BY user_id, product_id, category, brand, to_date(event_ts)),
p AS (SELECT user_id, product_id, event_ts FROM workspace.cart_leakage.events WHERE event_type = 'purchase')
SELECT c.*, CASE WHEN EXISTS (SELECT 1 FROM p WHERE p.user_id = c.user_id AND p.product_id = c.product_id
        AND p.event_ts >= c.cart_ts AND p.event_ts < c.cart_ts + INTERVAL 7 DAYS) THEN 0 ELSE 1 END AS abandoned
FROM carts c WHERE c.cart_ts <= (SELECT MAX(event_ts) FROM workspace.cart_leakage.events) - INTERVAL 7 DAYS;

SELECT COUNT(*) AS carts, SUM(abandoned) AS abandoned_carts, ROUND(SUM(abandoned)/COUNT(*),3) AS abandon_rate,
       ROUND(SUM(price*abandoned)) AS leaked_value FROM workspace.cart_leakage.cart_outcomes;

-- 8. Leaked value per month
SELECT date_trunc('month', cart_ts) AS month, COUNT(*) AS carts, SUM(abandoned) AS abandoned_carts,
  ROUND(SUM(abandoned)/COUNT(*),3) AS abandon_rate, ROUND(SUM(price*abandoned)) AS leaked_value,
  ROUND(SUM(price*abandoned)/SUM(price),3) AS leaked_share_of_cart_value
FROM workspace.cart_leakage.cart_outcomes GROUP BY date_trunc('month', cart_ts) ORDER BY month;

-- 9. Leak by brand, with share of total
SELECT brand, COUNT(*) AS carts, SUM(abandoned) AS abandoned_carts, ROUND(SUM(abandoned)/COUNT(*),3) AS abandon_rate,
  ROUND(SUM(price*abandoned)) AS leaked_value,
  ROUND(100*SUM(price*abandoned)/SUM(SUM(price*abandoned)) OVER (),1) AS pct_of_total_leak
FROM workspace.cart_leakage.cart_outcomes GROUP BY brand ORDER BY leaked_value DESC LIMIT 15;

-- 10. Leak by category, running total (Pareto)
WITH c AS (SELECT category, COUNT(*) AS carts, SUM(abandoned) AS abandoned_carts, ROUND(SUM(price*abandoned)) AS leaked_value
           FROM workspace.cart_leakage.cart_outcomes GROUP BY category)
SELECT category, carts, abandoned_carts, leaked_value,
  ROUND(100*leaked_value/SUM(leaked_value) OVER (),1) AS pct_of_total_leak,
  ROUND(100*SUM(leaked_value) OVER (ORDER BY leaked_value DESC)/SUM(leaked_value) OVER (),1) AS cumulative_pct
FROM c ORDER BY leaked_value DESC LIMIT 15;

-- 11. How many categories make up 50% / 80% of the leak
WITH c AS (SELECT category, SUM(price*abandoned) AS leaked FROM workspace.cart_leakage.cart_outcomes GROUP BY category),
r AS (SELECT leaked, SUM(leaked) OVER (ORDER BY leaked DESC) / SUM(leaked) OVER () AS cum_share FROM c)
SELECT COUNT(*) AS total_categories, SUM(CASE WHEN cum_share < 0.5 THEN 1 ELSE 0 END) + 1 AS categories_for_50pct,
       SUM(CASE WHEN cum_share < 0.8 THEN 1 ELSE 0 END) + 1 AS categories_for_80pct FROM r;

-- 12. First-purchase cohorts Oct-Dec 2019, repeat rate and revenue per user, months 0-3
WITH purch AS (SELECT user_id, price, date_trunc('month', event_ts) AS m FROM workspace.cart_leakage.events WHERE event_type='purchase'),
first_buy AS (SELECT user_id, MIN(m) AS cohort FROM purch GROUP BY user_id),
act AS (SELECT f.cohort, CAST(ROUND(months_between(p.m, f.cohort)) AS INT) AS k, p.user_id, p.price
        FROM purch p JOIN first_buy f ON p.user_id = f.user_id),
size AS (SELECT cohort, COUNT(*) AS cohort_users FROM first_buy GROUP BY cohort)
SELECT a.cohort, a.k, s.cohort_users, COUNT(DISTINCT a.user_id) AS active_users,
  ROUND(COUNT(DISTINCT a.user_id)/s.cohort_users,4) AS repeat_rate, ROUND(SUM(a.price)/s.cohort_users,2) AS revenue_per_cohort_user
FROM act a JOIN size s ON a.cohort = s.cohort
WHERE a.cohort IN (DATE'2019-10-01', DATE'2019-11-01', DATE'2019-12-01') AND a.k BETWEEN 0 AND 3
GROUP BY a.cohort, a.k, s.cohort_users ORDER BY a.cohort, a.k;

-- 13. Price the fix (ASSUMPTIONS: 25% gross margin, $0.01 per reminder)
WITH assumptions AS (SELECT 0.25 AS gross_margin, 0.01 AS cost_per_reminder),
monthly AS (SELECT date_trunc('month', cart_ts) AS m, SUM(abandoned) AS abandoned_carts, SUM(price*abandoned) AS leaked_value
            FROM workspace.cart_leakage.cart_outcomes WHERE cart_ts < TIMESTAMP'2020-02-01' GROUP BY date_trunc('month', cart_ts)),
avg_month AS (SELECT AVG(abandoned_carts) AS abandoned_carts, AVG(leaked_value) AS leaked_value FROM monthly),
recovery AS (SELECT explode(array(0.05, 0.10, 0.15)) AS rate)
SELECT r.rate AS recovery_rate, ROUND(a.leaked_value) AS avg_monthly_leaked_value,
  ROUND(a.leaked_value*r.rate) AS recovered_revenue_per_month, ROUND(a.leaked_value*r.rate*s.gross_margin) AS gross_profit_per_month,
  ROUND(a.abandoned_carts*s.cost_per_reminder) AS reminder_cost_per_month,
  ROUND(a.leaked_value*r.rate*s.gross_margin - a.abandoned_carts*s.cost_per_reminder) AS net_value_per_month
FROM recovery r CROSS JOIN avg_month a CROSS JOIN assumptions s ORDER BY r.rate;
