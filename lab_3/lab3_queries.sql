-- Задание 1
SELECT p.id, p.title AS "Наименование", c.name AS "Категория", s.store_name AS "Продавец", p.price AS "Цена"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id;


-- Задание 2
SELECT p.id, p.title, p.price
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL;


-- Задание 3
SELECT c.name, COUNT(p.id) AS "Количество", ROUND(AVG(p.price), 2) AS "Средняя цена"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WHERE p.is_active
GROUP BY c.name;


-- Задание 4
SELECT s.store_name AS "Продавец", SUM(o.quantity * o.unit_price) AS "Выручка"
FROM products AS p
JOIN sellers AS s ON s.id = p.seller_id
JOIN order_items AS o ON o.product_id = p.id
GROUP BY s.id, s.store_name
HAVING SUM(o.quantity * o.unit_price) > 1030000;


-- Задание 5
SELECT title, price
FROM products
WHERE LENGTH(title) > (SELECT AVG(LENGTH(title)) FROM products)
    AND price > (SELECT AVG(price) FROM products);


SELECT title, seller_id, price
FROM products
WHERE seller_id IN (
    SELECT DISTINCT p.seller_id
    FROM products AS p
    JOIN order_items AS o ON o.product_id = p.id);


SELECT s.id, s.store_name
FROM sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
);


-- Задание 6
WITH seller_revenue AS (
    SELECT p.seller_id,
        SUM(o.quantity * o.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS o ON o.product_id = p.id
    GROUP BY p.seller_id
)
SELECT s.store_name AS "Продавец", sr.revenue AS "Выручка"
FROM seller_revenue AS sr
JOIN sellers AS s ON s.id = sr.seller_id
ORDER BY sr.revenue DESC;


-- Задание 7
ALTER TABLE categories ADD COLUMN IF NOT EXISTS parent_id BIGINT REFERENCES categories(id) ON DELETE RESTRICT;

UPDATE categories
SET parent_id = NULL
WHERE id = 1;

UPDATE categories
SET parent_id = 1
WHERE id IN (2, 3);

UPDATE categories
SET parent_id = 2
WHERE id IN (4, 5);

UPDATE categories
SET parent_id = 3
WHERE id IN (6, 7);

UPDATE categories
SET parent_id = 4
WHERE id IN (8, 9, 10);

WITH RECURSIVE category_tree AS (SELECT id, name, parent_id, 0 AS level
    FROM categories
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, ct.level + 1
    FROM categories AS c
    JOIN category_tree AS ct ON c.parent_id = ct.id)
SELECT id, name AS "Категория", parent_id, level AS "Уровень"
FROM category_tree
ORDER BY level, id;


-- Задание 8
CREATE OR REPLACE VIEW product_catalog AS
SELECT p.id, p.title AS "Товар", c.name AS "Категория", s.store_name AS "Продавец", p.price AS "Цена", p.is_active AS "Активен"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id;


CREATE OR REPLACE VIEW seller_revenue AS
SELECT s.id, s.store_name AS "Продавец", SUM(o.quantity * o.unit_price) AS "Выручка"
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
JOIN order_items AS o ON o.product_id = p.id
GROUP BY s.id, s.store_name;

SELECT * FROM product_catalog LIMIT 2;

SELECT * FROM seller_revenue ORDER BY "Выручка" DESC LIMIT 3;