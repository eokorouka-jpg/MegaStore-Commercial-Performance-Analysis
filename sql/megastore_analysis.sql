USE megastore_analysis;

-- ==================================
-- 1. Load Data
-- ==================================

SHOW VARIABLES LIKE 'local_infile';

LOAD DATA LOCAL INFILE
'C:/Users/Owner/Desktop/MyDataScience_Project/MegaStore Commercial Performance & Profitability Analysis/data/megastore_sales.csv'
INTO TABLE megastore_sales
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    SUM(quantity) AS total_quantity
FROM megastore_sales;

SELECT
    order_id,
    product_name,
    sales,
    profit
FROM megastore_sales
ORDER BY sales DESC
LIMIT 10;

CREATE TABLE megastore_sales_staging LIKE megastore_sales;

ALTER TABLE megastore_sales_staging
MODIFY sales VARCHAR(50);

DESCRIBE megastore_sales_staging;

LOAD DATA LOCAL INFILE
'C:/Users/Owner/Desktop/MyDataScience_Project/MegaStore Commercial Performance & Profitability Analysis/data/megastore_sales.csv'
INTO TABLE megastore_sales_staging
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT
    COUNT(*) AS total_rows,
    MAX(CHAR_LENGTH(sales)) AS max_sales_text_length
FROM megastore_sales_staging;

-- ===========================================
-- 2. Inspect sales values containing commas
-- ===========================================

SELECT
    order_id,
    product_name,
    sales
FROM megastore_sales_staging
WHERE sales LIKE '%,%'
ORDER BY
    CAST(REPLACE(sales, ',', '') AS DECIMAL(12,2)) DESC
LIMIT 10;

-- Clean and convert sales:

UPDATE megastore_sales_staging
SET sales = REPLACE(sales, ',', '');

-- Convert the column to numeric:

ALTER TABLE megastore_sales_staging
MODIFY sales DECIMAL(12,2);

-- Validate the result:

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    SUM(quantity) AS total_quantity
FROM megastore_sales_staging;

-- Replace the corrupted table

DROP TABLE megastore_sales;

RENAME TABLE megastore_sales_staging
TO megastore_sales;

SELECT
    COUNT(*) AS total_rows,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit
FROM megastore_sales;

-- =====================================
-- 3. SQL Executive KPI Summary
-- =====================================

SELECT
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(profit) / SUM(sales) * 100, 2) AS profit_margin_pct,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(quantity) AS total_quantity,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(SUM(shipping_cost), 2) AS total_shipping_cost
FROM megastore_sales;

-- Executive KPI Summary: 
-- MegaStore generated £12.64M in sales and £1.47M in profit across 25,035 orders, producing an overall profit margin of 11.62%. 
-- Average order value was £505.01, while total shipping costs amounted to £1.35M.

-- ===========================================
-- 4. Sub-category profitability
-- ===========================================

SELECT
    sub_category,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    SUM(quantity) AS total_quantity,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0) * 100, 2) AS profit_margin_pct
FROM megastore_sales
GROUP BY sub_category
ORDER BY total_profit DESC;

-- Sub-category Profitability: 
-- Profitability varies substantially across MegaStore's product portfolio. Copiers generated the highest total profit (£258.57K), while Paper achieved the highest profit margin (24.23%). 
-- Tables was the only sub-category that was unprofitable overall, generating £757.03K in sales but a £64.08K loss and a -8.47% margin. 
-- This identifies Tables as a priority area for deeper investigation.

-- ===================================================
-- 5. Investigate Tables by discount level
-- ===================================================

SELECT
    ROUND(discount * 100, 0) AS discount_pct,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0) * 100, 2) AS profit_margin_pct
FROM megastore_sales
WHERE sub_category = 'Tables'
GROUP BY discount
ORDER BY discount;

-- Tables Discount Analysis: 
-- Tables generated a 23.09% profit margin when sold without discount, but profitability declined substantially as discounts increased. 
-- At the observed 30% discount level, margin became negative (-11.42%), and every observed discount level from 30% upward was loss-making. 
-- This shows a strong association between deeper discounting and poor Tables profitability, although the descriptive analysis alone does not establish that discounting is the sole cause of the losses.

-- ========================================
-- 6. Company-wide 30%+ discount analysis
-- ========================================

SELECT
    CASE
        WHEN discount >= 0.30 THEN '30%+ Discount'
        ELSE 'Below 30% Discount'
    END AS discount_group,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0) * 100, 2) AS profit_margin_pct
FROM megastore_sales
GROUP BY
    CASE
        WHEN discount >= 0.30 THEN '30%+ Discount'
        ELSE 'Below 30% Discount'
    END
ORDER BY total_profit DESC;

-- Company-wide Discount Analysis: 
-- Transactions with discounts below 30% generated £10.91M in sales and £2.28M in profit, achieving a 20.93% margin. 
-- In contrast, transactions discounted by 30% or more generated £1.74M in sales but produced an £813.21K loss, equivalent to a -46.83% margin. 
-- This demonstrates a strong association between deep discounting and poor profitability across the business, not just within Tables. 
-- The result supports closer commercial review of high-discount transactions, rather than assuming a universal 30% causal threshold.

-- =============================================================
-- 7. How often are 30%+ discounted lines actually loss-making?
-- =============================================================

SELECT
    COUNT(*) AS high_discount_lines,
    SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) AS loss_making_lines,
    ROUND(
        SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS loss_making_pct,
    ROUND(
        SUM(CASE WHEN profit < 0 THEN sales ELSE 0 END),
        2
    ) AS sales_from_loss_making_lines,
    ROUND(
        SUM(CASE WHEN profit < 0 THEN profit ELSE 0 END),
        2
    ) AS losses_from_loss_making_lines
FROM megastore_sales
WHERE discount >= 0.30;

-- High-Discount Loss Exposure: 
-- Of 10,701 transaction lines discounted by 30% or more, 9,860 (92.14%) were loss-making.
-- These loss-making lines generated £1.54M in sales but £831.86K in losses. 
-- This indicates that losses within the high-discount segment are widespread rather than being driven solely by a small number of extreme transactions.
-- However, the analysis demonstrates association rather than proving discounting alone caused the losses.

-- =================================================
-- 8. Where are the high-discount losses occurring?
-- =================================================

SELECT
    market,
    COUNT(*) AS high_discount_lines,
    ROUND(SUM(sales), 2) AS high_discount_sales,
    ROUND(SUM(profit), 2) AS high_discount_profit,
    ROUND(
        SUM(profit) / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS profit_margin_pct
FROM megastore_sales
WHERE discount >= 0.30
GROUP BY market
ORDER BY high_discount_profit ASC;

-- Market-Level High-Discount Exposure: 
-- High-discount losses occurred across every market where 30%+ discounts were observed. 
-- EU recorded the largest absolute loss (-£164.73K), followed by APAC (-£156.27K), LATAM (-£145.28K), and US (-£135.38K). 
-- Africa and EMEA showed the most severe margins at -148.32% and -96.14%, respectively. 
-- This suggests that high-discount exposure is a broad commercial issue, although its scale and severity vary considerably by market.

-- ===============================
-- 9. Shipping-mode profitability
-- ===============================

SELECT
    ship_mode,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(shipping_cost), 2) AS total_shipping_cost,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0) * 100, 2)
        AS profit_margin_pct,
    ROUND(SUM(shipping_cost) / NULLIF(SUM(sales), 0) * 100, 2)
        AS shipping_cost_pct_sales
FROM megastore_sales
GROUP BY ship_mode
ORDER BY total_sales DESC;

-- Shipping Mode Analysis: 
-- Shipping-cost intensity varies substantially by fulfilment method, ranging from 8.11% of sales for Standard Class to 17.38% for Same Day. 
-- Despite this difference, profit margins remain tightly grouped between 11.37% and 11.75% across all four shipping modes. 
-- This suggests that higher shipping-cost intensity alone does not explain MegaStore's major profitability differences.

-- ====================================
-- 10. Annual sales and profit growth
-- ====================================

SELECT
    year,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(
        SUM(profit) / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS profit_margin_pct,
    COUNT(*) AS transaction_lines
FROM megastore_sales
GROUP BY year
ORDER BY year;

-- Annual Performance: 
-- MegaStore experienced sustained growth from 2011 to 2014, with annual sales increasing from £2.26M to £4.30M and 
-- profit rising from £248.94K to £504.17K. Profit margin improved from 11.02% in 2011 to 11.99% in 2013 before 
-- declining slightly to 11.72% in 2014. This indicates strong overall growth, alongside modest margin compression in the most recent year.

-- ==============================================================
-- 11. Calculate year-over-year growth with a SQL window function
-- ==============================================================

WITH yearly_performance AS (
    SELECT
        year,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit
    FROM megastore_sales
    GROUP BY year
),
growth_analysis AS (
    SELECT
        year,
        total_sales,
        total_profit,
        LAG(total_sales) OVER (ORDER BY year) AS previous_year_sales,
        LAG(total_profit) OVER (ORDER BY year) AS previous_year_profit
    FROM yearly_performance
)
SELECT
    year,
    ROUND(total_sales, 2) AS total_sales,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(
        (total_sales - previous_year_sales)
        / NULLIF(previous_year_sales, 0) * 100,
        2
    ) AS sales_growth_pct,
    ROUND(
        (total_profit - previous_year_profit)
        / NULLIF(previous_year_profit, 0) * 100,
        2
    ) AS profit_growth_pct
FROM growth_analysis
ORDER BY year;

-- Year-over-Year Growth: 
-- MegaStore achieved positive sales and profit growth throughout the period. Sales grew 18.50% in 2012, 27.20% in 2013 and 26.25% in 2014. 
-- Profit grew 23.49%, 32.89% and 23.41%, respectively. In 2014, profit growth lagged sales growth, consistent with the decline in overall profit margin from 11.99% 
-- to 11.72%. This indicates that the business continued to expand strongly, but the profitability of incremental growth weakened slightly in 2014.

-- ============================================
-- 12. Which products are generating losses?
-- ============================================

SELECT
    product_id,
    product_name,
    sub_category,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(
        SUM(profit) / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS profit_margin_pct
FROM megastore_sales
GROUP BY
    product_id,
    product_name,
    sub_category
HAVING SUM(profit) < 0
ORDER BY total_profit ASC
LIMIT 10;

-- Product-Level Profitability: 
-- Loss-making products exist even within profitable sub-categories. The worst-performing product, the Cubify CubeX 3D Printer Double Head Print, 
-- generated £11.10K in sales but an £8.88K loss, equivalent to a -80.00% margin. The ten largest product losses span Machines, Appliances, Phones, 
-- Chairs and Tables, showing that portfolio-level profitability can conceal significant product-level underperformance. This supports targeted product 
-- review rather than treating entire categories uniformly.

-- =================================================
-- 13. Measure the total product-level loss exposure
-- ==================================================

WITH product_profitability AS (
    SELECT
        product_id,
        product_name,
        sub_category,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit
    FROM megastore_sales
    GROUP BY
        product_id,
        product_name,
        sub_category
)
SELECT
    COUNT(*) AS loss_making_products,
    ROUND(SUM(total_sales), 2) AS sales_from_loss_making_products,
    ROUND(SUM(total_profit), 2) AS total_product_losses
FROM product_profitability
WHERE total_profit < 0;

SELECT
    product_id,
    COUNT(DISTINCT product_name) AS distinct_product_names,
    COUNT(DISTINCT sub_category) AS distinct_sub_categories
FROM megastore_sales
GROUP BY product_id
HAVING
    COUNT(DISTINCT product_name) > 1
    OR COUNT(DISTINCT sub_category) > 1
ORDER BY distinct_product_names DESC;

SELECT
    COUNT(*) AS total_product_groups,
    SUM(CASE WHEN total_profit < 0 THEN 1 ELSE 0 END) AS loss_making_groups,
    SUM(CASE WHEN total_profit = 0 THEN 1 ELSE 0 END) AS zero_profit_groups,
    SUM(CASE WHEN total_profit > 0 THEN 1 ELSE 0 END) AS profitable_groups
FROM (
    SELECT
        product_id,
        product_name,
        sub_category,
        SUM(profit) AS total_profit
    FROM megastore_sales
    GROUP BY
        product_id,
        product_name,
        sub_category
) AS product_summary;

SELECT
    product_id,
    product_name,
    sub_category,
    SUM(profit) AS total_profit
FROM megastore_sales
GROUP BY
    product_id,
    product_name,
    sub_category
HAVING ABS(SUM(profit)) < 0.10
ORDER BY total_profit;

-- Product-Level Loss Exposure: 
-- Using the SQL product-level grouping, 3,030 product records were loss-making overall, generating approximately £3.24M in sales and a combined loss of £557.78K. 
-- The losses span multiple sub-categories, demonstrating that profitability issues are not limited to Tables. A small difference from the initial Python product 
-- count was traced to zero/near-zero profit classification; the aggregate loss value remained identical.

-- =======================
-- 14. Loss-making orders
-- =======================

WITH order_profitability AS (
    SELECT
        order_id,
        SUM(sales) AS order_sales,
        SUM(profit) AS order_profit,
        SUM(quantity) AS order_quantity,
        SUM(shipping_cost) AS order_shipping_cost,
        COUNT(*) AS transaction_lines
    FROM megastore_sales
    GROUP BY order_id
)
SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_profit < 0 THEN 1 ELSE 0 END)
        AS loss_making_orders,
    ROUND(
        SUM(CASE WHEN order_profit < 0 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS loss_making_order_pct,
    ROUND(
        SUM(CASE WHEN order_profit < 0 THEN order_sales ELSE 0 END),
        2
    ) AS sales_from_loss_making_orders,
    ROUND(
        SUM(CASE WHEN order_profit < 0 THEN order_profit ELSE 0 END),
        2
    ) AS losses_from_loss_making_orders
FROM order_profitability;

-- Order-Level Profitability: 
-- Of MegaStore's 25,035 orders, 6,124 (24.46%) were loss-making. These orders generated £2.36M in sales but produced approximately £843.61K in combined losses. 
-- This demonstrates that a substantial share of revenue-generating orders failed to translate into profit, reinforcing the importance of evaluating order profitability
-- alongside sales performance.