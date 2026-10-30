-- Задание 1
ALTER TABLE products
ADD COLUMN IF NOT EXISTS attributes JSONB;

UPDATE products
SET attributes = '{"color": "black", "weight": 180, "memory": "128 GB"}'
WHERE title LIKE 'Телефон%';

UPDATE products
SET attributes = '{"color": "silver", "weight": 1500, "memory": "512 GB"}'
WHERE title LIKE 'Ноутбук%';

UPDATE products
SET attributes = '{"color": "white", "wireless": true}'
WHERE title LIKE 'Наушники%';

UPDATE products
SET attributes = '{"color": "black", "connection": "USB"}'
WHERE title LIKE 'Клавиатура%';

-- Проверка характеристик товаров
SELECT
    id AS "Номер товара",
    title AS "Товар",
    attributes AS "Характеристики"
FROM products
WHERE attributes IS NOT NULL
ORDER BY id;


-- Задание 2. Извлечение поля через ->
SELECT
    p.title AS "Товар",
    p.attributes -> 'color' AS "Цвет"
FROM products AS p
WHERE p.attributes IS NOT NULL;

-- Извлечение поля через ->>
SELECT
    p.title AS "Товар",
    p.attributes ->> 'color' AS "Цвет"
FROM products AS p
WHERE p.attributes IS NOT NULL;

-- Фильтрация товаров по характеристикам через @>
SELECT
    p.title AS "Товар",
    p.price AS "Цена",
    p.attributes AS "Характеристики"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'
ORDER BY p.price DESC;


-- Подготовка данных: распределяем даты заказов по 14 дням,
-- чтобы запросы за период работали с разными датами
UPDATE orders
SET created_at = CURRENT_DATE - (((id - 1) % 14)::int * INTERVAL '1 day');


-- Задание 3. Анализ запроса по категории и цене
EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.category_id = 5
  AND p.price < 3000;

-- Анализ выручки продавцов
EXPLAIN ANALYZE
SELECT
    s.store_name AS "Продавец",
    SUM(oi.quantity * oi.unit_price) AS "Выручка"
FROM sellers AS s
JOIN products AS p ON s.id = p.seller_id
JOIN order_items AS oi ON p.id = oi.product_id
GROUP BY s.id, s.store_name
ORDER BY "Выручка" DESC;

-- Анализ заказов за сутки
EXPLAIN ANALYZE
SELECT
    o.created_at::date AS "Дата",
    SUM(oi.quantity * oi.unit_price) AS "Выручка"
FROM orders AS o
JOIN order_items AS oi ON o.id = oi.order_id
WHERE o.created_at >= CURRENT_DATE
  AND o.created_at < CURRENT_DATE + 1
GROUP BY o.created_at::date
ORDER BY "Дата";

-- Анализ простой выборки заказов за сутки до создания индекса
EXPLAIN ANALYZE
SELECT
    o.id AS "Номер заказа",
    o.created_at AS "Дата заказа"
FROM orders AS o
WHERE o.created_at >= CURRENT_DATE
  AND o.created_at < CURRENT_DATE + 1;


-- Задание 4. Создание B-tree-индексов
CREATE INDEX IF NOT EXISTS idx_products_category_price
ON products (category_id, price);

CREATE INDEX IF NOT EXISTS idx_orders_created_at
ON orders (created_at);

ANALYZE products;
ANALYZE orders;

-- Повторный анализ запроса по категории и цене
EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.category_id = 5
  AND p.price < 3000;

-- Повторный анализ запроса по дате
EXPLAIN ANALYZE
SELECT
    o.id AS "Номер заказа",
    o.created_at AS "Дата заказа"
FROM orders AS o
WHERE o.created_at >= CURRENT_DATE
  AND o.created_at < CURRENT_DATE + 1;


-- Задание 5. Создание GIN-индекса
CREATE INDEX IF NOT EXISTS idx_products_attributes
ON products USING GIN (attributes);

ANALYZE products;

-- Анализ поиска по характеристикам
EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}';

-- Проверка работоспособности GIN-индекса при отключённом Seq Scan
SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}';

SET enable_seqscan = on;


-- Задание 6. Создание таблиц для сравнения
DROP TABLE IF EXISTS products_test_no_index;
DROP TABLE IF EXISTS products_test_with_index;

CREATE TEMP TABLE products_test_no_index AS
SELECT id, title, price, category_id
FROM products
WITH NO DATA;

CREATE TEMP TABLE products_test_with_index AS
SELECT id, title, price, category_id
FROM products
WITH NO DATA;

-- Создание индекса для второй таблицы
CREATE INDEX idx_products_test_category
ON products_test_with_index (category_id);

-- Массовая вставка без индекса
EXPLAIN ANALYZE
INSERT INTO products_test_no_index (id, title, price, category_id)
SELECT
    p.id,
    p.title,
    p.price,
    p.category_id
FROM products AS p
CROSS JOIN generate_series(1, 100) AS n;

-- Массовая вставка с индексом
EXPLAIN ANALYZE
INSERT INTO products_test_with_index (id, title, price, category_id)
SELECT
    p.id,
    p.title,
    p.price,
    p.category_id
FROM products AS p
CROSS JOIN generate_series(1, 100) AS n;


-- Задание 7. Обоснование созданных индексов
-- B-tree-индекс idx_products_category_price ускоряет поиск товаров по категории
-- и цене: он соответствует условиям WHERE category_id = ... AND price < ...,
-- поэтому при небольшой доле подходящих строк PostgreSQL может перейти от
-- последовательного сканирования к индексному.
-- B-tree-индекс idx_orders_created_at ускоряет выборку заказов за период,
-- так как условие на created_at превращается в диапазонный поиск по индексу.
-- GIN-индекс idx_products_attributes ускоряет проверку вложенности JSONB
-- оператором @>, поскольку хранит отдельные ключи и значения документа.
-- Индексы ускоряют чтение, но занимают место и замедляют вставку, обновление
-- и удаление, поэтому их создают под конкретные запросы, подтверждённые
-- планами EXPLAIN ANALYZE.
