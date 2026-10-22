-- Задание 1
SELECT c.name AS "Категория", p.title AS "Товар", p.price AS "Цена",
    ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Номер строки",
    RANK() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Ранг",
    DENSE_RANK() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS dense_rank
FROM products AS p
JOIN categories AS c ON p.category_id = c.id
ORDER BY c.name, p.price DESC;


-- Задание 2
WITH ranked_products AS (
    SELECT c.name AS "Категория", p.title AS "Товар", p.price AS "Цена",
        ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Номер"
    FROM products AS p
    JOIN categories AS c ON p.category_id = c.id
)
SELECT "Категория", "Товар", "Цена"
FROM ranked_products
WHERE "Номер" <= 3
ORDER BY "Категория", "Цена" DESC;


-- Задание 3
-- Распределяем даты оформления заказов по 14 дням, чтобы выручка считалась по дням
UPDATE orders
SET created_at = CURRENT_DATE - (((id - 1) % 14)::int * INTERVAL '1 day');

WITH daily_revenue AS (
    SELECT o.created_at::date AS "Дата", SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM orders AS o
    JOIN order_items AS oi ON o.id = oi.order_id
    GROUP BY o.created_at::date
)
SELECT "Дата", "Выручка",
    SUM("Выручка") OVER (ORDER BY "Дата") AS "Накопительная_выручка"
FROM daily_revenue
ORDER BY "Дата";


-- Задание 4
WITH seller_revenue AS (
    SELECT c.name AS "Категория", s.store_name AS "Продавец",
        SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM categories AS c
    JOIN products AS p ON c.id = p.category_id
    JOIN sellers AS s ON p.seller_id = s.id
    JOIN order_items AS oi ON p.id = oi.product_id
    GROUP BY c.name, s.id, s.store_name
)
SELECT "Категория", "Продавец", "Выручка",
    SUM("Выручка") OVER (PARTITION BY "Категория") AS "Выручка категории",
    ROUND(100.0 * "Выручка" / NULLIF(SUM("Выручка") OVER (PARTITION BY "Категория"), 0), 2) AS "Доля процентов"
FROM seller_revenue
ORDER BY "Категория", "Выручка" DESC;


-- Задание 5
WITH daily_revenue AS (
    SELECT o.created_at::date AS "Дата", SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM orders AS o
    JOIN order_items AS oi ON o.id = oi.order_id
    GROUP BY o.created_at::date
)
SELECT "Дата", "Выручка",
    LAG("Выручка") OVER (ORDER BY "Дата") AS "Выручка предыдущего дня",
    LEAD("Выручка") OVER (ORDER BY "Дата") AS "Выручка следующего дня",
    "Выручка" - LAG("Выручка") OVER (ORDER BY "Дата") AS "Изменение к предыдущему дню"
FROM daily_revenue
ORDER BY "Дата";


-- Задание 6. Вариант 1
SELECT s.store_name AS "Продавец", SUM(oi.quantity * oi.unit_price) AS "Выручка"
FROM sellers AS s
JOIN products AS p ON s.id = p.seller_id
JOIN order_items AS oi ON p.id = oi.product_id
GROUP BY s.id, s.store_name
ORDER BY "Выручка" DESC;


-- Задание 6. Вариант 2
WITH seller_revenue AS (
    SELECT s.id, s.store_name AS "Продавец", SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM sellers AS s
    JOIN products AS p ON s.id = p.seller_id
    JOIN order_items AS oi ON p.id = oi.product_id
    GROUP BY s.id, s.store_name
)
SELECT "Продавец", "Выручка", SUM("Выручка") OVER () AS "Общая выручка"
FROM seller_revenue
ORDER BY "Выручка" DESC;
