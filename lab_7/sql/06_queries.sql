-- ============================================================
-- Аналитические запросы итогового проекта
-- ============================================================

-- Запрос 1. JOIN трёх таблиц: каталог товаров
SELECT
    p.id AS "Код",
    p.title AS "Товар",
    c.name AS "Категория",
    s.store_name AS "Продавец",
    p.price AS "Цена"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id
ORDER BY p.price DESC
LIMIT 10;


-- Запрос 2. LEFT JOIN: покупатели без магазина
SELECT COUNT(*) AS "Покупателей без магазина"
FROM users AS u
LEFT JOIN sellers AS s ON s.user_id = u.id
WHERE s.id IS NULL;


-- Запрос 3. GROUP BY и HAVING: продавцы с выручкой больше 1 030 000
SELECT
    s.store_name AS "Продавец",
    SUM(oi.quantity * oi.unit_price) AS "Выручка"
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
GROUP BY s.id, s.store_name
HAVING SUM(oi.quantity * oi.unit_price) > 1030000
ORDER BY "Выручка" DESC;


-- Запрос 4. Скалярный подзапрос: товары дороже средней цены
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.price > (SELECT AVG(price) FROM products)
ORDER BY p.price DESC
LIMIT 10;


-- Запрос 5. Подзапрос с IN: товары, которые хотя бы раз заказывали
SELECT COUNT(*) AS "Заказанных товаров"
FROM products AS p
WHERE p.id IN (SELECT oi.product_id FROM order_items AS oi);


-- Запрос 6. Подзапрос с EXISTS: продавцы, у которых есть товары
SELECT
    s.store_name AS "Продавец"
FROM sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
);


-- Запрос 7. CTE: выручка по категориям
WITH category_revenue AS (
    SELECT
        c.id,
        c.name AS "Категория",
        SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM categories AS c
    JOIN products AS p ON p.category_id = c.id
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY c.id, c.name
)
SELECT "Категория", "Выручка"
FROM category_revenue
ORDER BY "Выручка" DESC;


-- Запрос 8. Рекурсивный CTE: дерево категорий
WITH RECURSIVE category_tree AS (
    SELECT
        id,
        name AS "Категория",
        parent_id,
        1 AS "Уровень"
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        c.id,
        c.name,
        c.parent_id,
        t."Уровень" + 1
    FROM categories AS c
    JOIN category_tree AS t ON c.parent_id = t.id
)
SELECT "Уровень", "Категория"
FROM category_tree
ORDER BY "Уровень", id;


-- Запрос 9. Оконные функции ROW_NUMBER, RANK, DENSE_RANK
WITH ranked_products AS (
    SELECT
        c.name AS "Категория",
        p.title AS "Товар",
        p.price AS "Цена",
        ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Номер строки",
        RANK() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Ранг",
        DENSE_RANK() OVER (PARTITION BY c.id ORDER BY p.price DESC) AS "Плотный ранг"
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
)
SELECT *
FROM ranked_products
WHERE "Номер строки" <= 2
ORDER BY "Категория", "Цена" DESC;


-- Запрос 10. SUM() OVER: накопительная выручка по дням
WITH daily_revenue AS (
    SELECT
        o.created_at::date AS "Дата",
        SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    GROUP BY o.created_at::date
)
SELECT
    "Дата",
    "Выручка",
    SUM("Выручка") OVER (ORDER BY "Дата") AS "Накопительная выручка"
FROM daily_revenue
ORDER BY "Дата";


-- Запрос 11. LAG и LEAD: динамика выручки по дням
WITH daily_revenue AS (
    SELECT
        o.created_at::date AS "Дата",
        SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    GROUP BY o.created_at::date
)
SELECT
    "Дата",
    "Выручка",
    LAG("Выручка") OVER (ORDER BY "Дата") AS "Выручка предыдущего дня",
    LEAD("Выручка") OVER (ORDER BY "Дата") AS "Выручка следующего дня",
    "Выручка" - LAG("Выручка") OVER (ORDER BY "Дата") AS "Изменение"
FROM daily_revenue
ORDER BY "Дата";


-- Запрос 12. SUM() OVER (PARTITION BY): доля товара в выручке категории
WITH product_revenue AS (
    SELECT
        c.name AS "Категория",
        p.title AS "Товар",
        SUM(oi.quantity * oi.unit_price) AS "Выручка"
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY p.id, p.title, c.name
)
SELECT
    "Категория",
    "Товар",
    "Выручка",
    SUM("Выручка") OVER (PARTITION BY "Категория") AS "Выручка категории",
    ROUND(
        100.0 * "Выручка"
        / NULLIF(SUM("Выручка") OVER (PARTITION BY "Категория"), 0),
        2
    ) AS "Доля, %"
FROM product_revenue
ORDER BY "Доля, %" DESC
LIMIT 15;


-- Запрос 13. JSONB: оператор -> (jsonb)
SELECT
    p.id AS "Код",
    p.title AS "Товар",
    p.attributes -> 'color' AS "Цвет (jsonb)"
FROM products AS p
WHERE p.attributes IS NOT NULL
ORDER BY p.id
LIMIT 5;


-- Запрос 14. JSONB: оператор ->> (text)
SELECT
    p.id AS "Код",
    p.title AS "Товар",
    p.attributes ->> 'color' AS "Цвет"
FROM products AS p
WHERE p.attributes ->> 'color' = 'black'
ORDER BY p.id
LIMIT 10;


-- Запрос 15. JSONB: оператор @> (вхождение)
SELECT COUNT(*) AS "Чёрных товаров"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'::jsonb;


-- Запрос 16. JSONB: проверка наличия ключа
SELECT COUNT(*) AS "Товаров с памятью"
FROM products AS p
WHERE p.attributes ? 'memory';


-- Запрос 17. Запросы к аналитическим представлениям
SELECT * FROM v_seller_revenue ORDER BY revenue DESC LIMIT 5;
SELECT * FROM v_category_sales ORDER BY revenue DESC LIMIT 5;
SELECT * FROM v_popular_products ORDER BY sold_quantity DESC LIMIT 5;
SELECT * FROM v_order_stats ORDER BY orders_count DESC;
