# Отчёт по лабораторной работе №3
**Дисциплина:** Математические основы баз данных
**Тема:** Многотабличные запросы и аналитические представления (на примере БД маркетплейса)

---

## 1. Цель работы

Освоить многотабличные выборки в PostgreSQL: соединения таблиц (`JOIN`), агрегатные функции с группировкой (`GROUP BY`, `HAVING`), подзапросы (скалярные, с `IN`, с `EXISTS`), общие табличные выражения (`CTE`, включая рекурсивные) и представления (`VIEW`) для типовых отчётов.

---

## 2. Постановка задачи (по пособию)

1. Запрос с внутренним соединением не менее трёх таблиц (товар — категория — продавец).
2. Запрос с `LEFT JOIN`, показывающий строки без соответствий в связанной таблице (товары без отзывов).
3. Запрос с группировкой и агрегацией: по каждой категории — количество товаров и средняя цена.
4. `HAVING` для фильтрации групп (продавцы с выручкой выше заданной).
5. По одному запросу с подзапросом каждого вида: скалярным, с `IN` и с `EXISTS`.
6. `CTE` для разбиения сложного запроса на шаги; рекурсивный `CTE` для обхода дерева категорий.
7. Не менее двух представлений для типовых отчётов и демонстрация обращений к ним.

Полный скрипт — в файле [`lab3_queries.sql`](./lab3_queries.sql). Для каждого запроса ниже приведены текст, назначение и фрагмент результата (проверено выполнением в PostgreSQL 18.6).

---

## 3. Исходные данные

Запросы работают на сквозной базе: схема из лаб 1 (`lab_1/01_schema.sql`), данные из лаб 2 (`lab_2/lab2_requests.sql`) — 1000 товаров, 1000 заказов, 1000 позиций заказов, 1000 отзывов, 10 категорий, 10 продавцов. Иерархия категорий для рекурсивного обхода задана в задании 7 через столбец `parent_id`: категория 1 — корневая, уровни 0–3.

---

## 4. Многотабличные и аналитические запросы

### Задание 1. Внутреннее соединение трёх таблиц

Назначение: каталог товаров с категорией и продавцом.

```sql
SELECT p.id, p.title AS "Наименование", c.name AS "Категория",
    s.store_name AS "Продавец", p.price AS "Цена"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id;
```

Результат: 1000 строк. Фрагмент:

```
 id |    title     |    name     | store_name | price
----+--------------+-------------+------------+--------
  1 | Ноутбук 1    | Категория 2 | Магазин 2  | 637.00
  2 | Наушники 2   | Категория 3 | Магазин 3  | 774.00
  3 | Клавиатура 3 | Категория 4 | Магазин 4  | 911.00
```

### Задание 2. `LEFT JOIN`: товары без отзывов

Назначение: товары, на которые нет ни одного отзыва с комментарием.

```sql
SELECT p.id, p.title, p.price
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL;
```

Результат: 0 строк — в тестовых данных у каждого товара есть отзыв.

Замечание: условие именно по `r.id`, а не по nullable-столбцу вроде `comment`, чтобы отбирать товары без отзывов, а не отзывы без текста.

### Задание 3. Группировка и агрегация по категориям

Назначение: по каждой категории — количество активных товаров и средняя цена.

```sql
SELECT c.name, COUNT(p.id) AS "Количество",
    ROUND(AVG(p.price), 2) AS "Средняя цена"
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WHERE p.is_active
GROUP BY c.name;
```

Результат: 10 строк. Фрагмент:

```
     name     | count |  round
--------------+-------+---------
 Категория 1  |    50 | 5160.00
 Категория 10 |   100 | 5138.00
 Категория 2  |   100 | 5182.00
```

### Задание 4. Фильтрация групп через `HAVING`

Назначение: продавцы с выручкой выше 1 030 000. Выручка считается по позициям заказов: `SUM(quantity * unit_price)`.

```sql
SELECT s.store_name AS "Продавец",
    SUM(o.quantity * o.unit_price) AS "Выручка"
FROM products AS p
JOIN sellers AS s ON s.id = p.seller_id
JOIN order_items AS o ON o.product_id = p.id
GROUP BY s.id, s.store_name
HAVING SUM(o.quantity * o.unit_price) > 1030000;
```

Результат: 5 строк. Фрагмент:

```
 store_name |    sum
------------+------------
 Магазин 5  | 1050494.00
 Магазин 6  | 1047605.00
 Магазин 7  | 1044716.00
```

### Задание 5. Подзапросы: скалярный, `IN`, `EXISTS`

Назначение: три вида подзапросов — сравнение со средними значениями (два скалярных подзапроса), проверка вхождения во множество (`IN`), проверка существования связанных строк (коррелированный `EXISTS`).

```sql
SELECT title, price
FROM products
WHERE LENGTH(title) > (SELECT AVG(LENGTH(title)) FROM products)
    AND price > (SELECT AVG(price) FROM products);
```

Результат: 193 строки. Фрагмент:

```
     title     |  price
---------------+---------
 Наушники 42   | 6254.00
 Клавиатура 43 | 6391.00
 Наушники 52   | 7624.00
```

```sql
SELECT title, seller_id, price
FROM products
WHERE seller_id IN (
    SELECT DISTINCT p.seller_id
    FROM products AS p
    JOIN order_items AS o ON o.product_id = p.id
);
```

Результат: 1000 строк (все товары продаваемых продавцов). Фрагмент:

```
    title     | seller_id | price
--------------+-----------+--------
 Ноутбук 1    |         2 | 637.00
 Наушники 2   |         3 | 774.00
 Клавиатура 3 |         4 | 911.00
```

```sql
SELECT s.id, s.store_name
FROM sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
);
```

Результат: 10 строк (у каждого продавца есть товары). Фрагмент:

```
 id | store_name
----+------------
  1 | Магазин 1
  2 | Магазин 2
  3 | Магазин 3
```

### Задание 6. `CTE`: выручка продавцов по шагам

Назначение: разбить расчёт на шаги через `WITH` — сначала выручка по продавцам, затем присоединение названий магазинов с сортировкой.

```sql
WITH seller_revenue AS (
    SELECT p.seller_id,
        SUM(o.quantity * o.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS o ON o.product_id = p.id
    GROUP BY p.seller_id
)
SELECT s.store_name AS "Продавец",
    sr.revenue AS "Выручка"
FROM seller_revenue AS sr
JOIN sellers AS s ON s.id = sr.seller_id
ORDER BY sr.revenue DESC;
```

Результат: 10 строк. Фрагмент:

```
 store_name |  revenue
------------+------------
 Магазин 5  | 1050494.00
 Магазин 6  | 1047605.00
 Магазин 7  | 1044716.00
```

### Задание 7. Иерархия категорий и рекурсивный `CTE`

Назначение: задать дерево категорий через самоссылку `parent_id` и обойти его рекурсивным запросом с указанием уровня.

```sql
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
```

Результат: 10 строк, 4 уровня (0–3).

```
 id |     name     | parent_id | level
----+--------------+-----------+-------
  1 | Категория 1  |           |     0
  2 | Категория 2  |         1 |     1
  3 | Категория 3  |         1 |     1
  4 | Категория 4  |         2 |     2
  5 | Категория 5  |         2 |     2
  6 | Категория 6  |         3 |     2
  7 | Категория 7  |         3 |     2
  8 | Категория 8  |         4 |     3
  9 | Категория 9  |         4 |     3
 10 | Категория 10 |         4 |     3
```

### Задание 8. Представления для типовых отчётов

Назначение: сохранить типовые отчёты как представления — каталог товаров и выручка продавцов — и обратиться к ним.

```sql
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
```

Обращение к представлениям:

```sql
SELECT * FROM product_catalog LIMIT 2;
```

```
 id |   title    |  category   |  seller   | price  | is_active
----+------------+-------------+-----------+--------+-----------
  1 | Ноутбук 1  | Категория 2 | Магазин 2 | 637.00 | t
  2 | Наушники 2 | Категория 3 | Магазин 3 | 774.00 | t
```

```sql
SELECT * FROM seller_revenue ORDER BY "Выручка" DESC LIMIT 3;
```

```
 id | store_name |  revenue
----+------------+------------
  5 | Магазин 5  | 1050494.00
  6 | Магазин 6  | 1047605.00
  7 | Магазин 7  | 1044716.00
```

---

## 5. Как запустить

```bash
psql -U postgres -d marketplace -f lab_1/01_schema.sql
psql -U postgres -d marketplace -f lab_2/lab2_requests.sql
psql -U postgres -d marketplace -f lab_3/lab3_queries.sql
```

---

## 6. Вывод

В ходе работы составлен набор многотабличных и аналитических запросов к базе маркетплейса: соединение трёх таблиц, `LEFT JOIN` для строк без соответствий, группировка с агрегацией и фильтрацией групп через `HAVING`, подзапросы трёх видов, разбиение сложного расчёта на шаги через `CTE`, рекурсивный обход дерева категорий и два представления для типовых отчётов. Все запросы проверены выполнением в PostgreSQL 18.6.
