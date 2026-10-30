-- ============================================================
-- Индексы и оптимизация запросов
-- ============================================================
-- Скрипт сначала удаляет индексы, чтобы замеры "до" были
-- воспроизводимы при повторном запуске.

DROP INDEX IF EXISTS idx_products_category_price;
DROP INDEX IF EXISTS idx_orders_created_at;
DROP INDEX IF EXISTS idx_products_attributes;

ANALYZE products;
ANALYZE orders;

-- ------------------------------------------------------------
-- 1. Выборка товаров категории в диапазоне цен
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title, p.price
FROM products AS p
WHERE p.category_id = 5
  AND p.price BETWEEN 500 AND 3000
ORDER BY p.price;

-- ------------------------------------------------------------
-- 2. Заказы за последние сутки
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.total_amount
FROM orders AS o
WHERE o.created_at >= CURRENT_DATE - 1
  AND o.created_at < CURRENT_DATE;

-- ------------------------------------------------------------
-- 3. Поиск по JSONB-характеристикам
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'::jsonb;

-- ------------------------------------------------------------
-- Создание индексов
-- ------------------------------------------------------------
CREATE INDEX idx_products_category_price
    ON products (category_id, price);

CREATE INDEX idx_orders_created_at
    ON orders (created_at);

CREATE INDEX idx_products_attributes
    ON products USING gin (attributes);

ANALYZE products;
ANALYZE orders;

-- ------------------------------------------------------------
-- 1. Повторная выборка товаров категории в диапазоне цен
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title, p.price
FROM products AS p
WHERE p.category_id = 5
  AND p.price BETWEEN 500 AND 3000
ORDER BY p.price;

-- ------------------------------------------------------------
-- 2. Повторная выборка заказов за последние сутки
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.total_amount
FROM orders AS o
WHERE o.created_at >= CURRENT_DATE - 1
  AND o.created_at < CURRENT_DATE;

-- ------------------------------------------------------------
-- 3. Повторный поиск по JSONB
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'::jsonb;

-- При 20% подходящих строк планировщик может оставить Seq Scan.
-- Проверяем, что GIN-индекс вообще применим:
SET enable_seqscan = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'::jsonb;

RESET enable_seqscan;

-- ------------------------------------------------------------
-- 4. Стоимость поддержки индекса при массовой вставке
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_items_no_index;
DROP TABLE IF EXISTS tmp_items_with_index;

CREATE TEMP TABLE tmp_items_no_index (
    id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    unit_price NUMERIC(12, 2)
);

CREATE TEMP TABLE tmp_items_with_index (
    id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    unit_price NUMERIC(12, 2)
);

CREATE INDEX tmp_items_with_index_product_id
    ON tmp_items_with_index (product_id);

EXPLAIN (ANALYZE, TIMING OFF)
INSERT INTO tmp_items_no_index (id, order_id, product_id, quantity, unit_price)
SELECT g, 1 + (g % 1000), 1 + (g % 1000), 1 + (g % 3), 1000.00
FROM generate_series(1, 100000) AS g;

EXPLAIN (ANALYZE, TIMING OFF)
INSERT INTO tmp_items_with_index (id, order_id, product_id, quantity, unit_price)
SELECT g, 1 + (g % 1000), 1 + (g % 1000), 1 + (g % 3), 1000.00
FROM generate_series(1, 100000) AS g;

DROP TABLE tmp_items_no_index;
DROP TABLE tmp_items_with_index;
