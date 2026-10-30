-- ============================================================
-- Аналитические представления
-- ============================================================
BEGIN;

CREATE OR REPLACE VIEW v_product_catalog AS
SELECT
    p.id AS product_id,
    p.title,
    c.name AS category,
    s.store_name AS seller,
    p.price,
    p.rating,
    p.is_active,
    p.attributes
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id;


CREATE OR REPLACE VIEW v_seller_revenue AS
SELECT
    s.id AS seller_id,
    s.store_name,
    COUNT(DISTINCT p.id) AS products_count,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
LEFT JOIN order_items AS oi ON oi.product_id = p.id
GROUP BY s.id, s.store_name;


CREATE OR REPLACE VIEW v_category_sales AS
SELECT
    c.id AS category_id,
    c.name AS category,
    COUNT(DISTINCT p.id) AS products_count,
    COALESCE(SUM(oi.quantity), 0) AS sold_quantity,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
FROM categories AS c
JOIN products AS p ON p.category_id = c.id
LEFT JOIN order_items AS oi ON oi.product_id = p.id
GROUP BY c.id, c.name;


CREATE OR REPLACE VIEW v_popular_products AS
SELECT
    p.id AS product_id,
    p.title,
    c.name AS category,
    COALESCE(SUM(oi.quantity), 0) AS sold_quantity,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
LEFT JOIN order_items AS oi ON oi.product_id = p.id
GROUP BY p.id, p.title, c.name;


CREATE OR REPLACE VIEW v_order_stats AS
SELECT
    o.status,
    COUNT(*) AS orders_count,
    COALESCE(SUM(o.total_amount), 0) AS total_amount,
    ROUND(AVG(o.total_amount), 2) AS avg_amount
FROM orders AS o
GROUP BY o.status;


CREATE OR REPLACE VIEW v_daily_revenue AS
SELECT
    o.created_at::date AS order_date,
    COUNT(DISTINCT o.id) AS orders_count,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
GROUP BY o.created_at::date;

COMMIT;


-- Демонстрация представлений
SELECT * FROM v_seller_revenue ORDER BY revenue DESC LIMIT 5;
SELECT * FROM v_category_sales ORDER BY revenue DESC LIMIT 5;
SELECT * FROM v_popular_products ORDER BY sold_quantity DESC LIMIT 5;
SELECT * FROM v_order_stats ORDER BY orders_count DESC;
SELECT * FROM v_daily_revenue ORDER BY order_date LIMIT 5;
