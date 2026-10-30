# Отчёт по лабораторной работе №6
**Дисциплина:** Математические основы баз данных
**Тема:** Современные возможности PostgreSQL и оптимизация запросов (на примере БД маркетплейса)

---

## 1. Цель работы

Освоить тип данных JSONB и операторы работы с ним (`->`, `->>`, `@>`), научиться анализировать планы выполнения запросов командой `EXPLAIN ANALYZE`, создавать B-tree- и GIN-индексы и оценивать их влияние на чтение и массовую вставку данных.

---

## 2. Постановка задачи (по пособию)

1. Добавить к таблице товаров столбец `attributes` типа JSONB и заполнить характеристики для разных товаров.
2. Выполнить извлечение и фильтрацию JSONB операторами `->`, `->>` и `@>`.
3. Проанализировать планы выполнения запросов через `EXPLAIN ANALYZE`: зафиксировать тип сканирования и фактическое время.
4. Создать B-tree-индексы по категории и цене товара и по дате заказа, сравнить планы до и после.
5. Создать GIN-индекс для JSONB и проверить, использует ли его PostgreSQL при поиске через `@>`.
6. Сравнить массовую вставку в таблицу с индексом и без индекса.
7. Обосновать созданные индексы.

Полный скрипт — в файле [`lab6_queries.sql`](./lab6_queries.sql). Для каждого задания ниже приведены текст, назначение и результаты выполнения (проверено в PostgreSQL 18.6).

---

## 3. Исходные данные

Запросы работают на сквозной базе: схема из лаб 1 (`lab_1/01_schema.sql`), данные из лаб 2 (`lab_2/lab2_requests.sql`) — 1000 товаров, 1000 заказов и 1000 позиций заказов.

Характеристики заполняются для четырёх групп товаров (телефоны, ноутбуки, наушники, клавиатуры) — всего 400 строк из 1000. Для запросов за период даты оформления заказов детерминированно распределяются по 14 дням, чтобы условие на `created_at` отбирало часть строк, а не всю таблицу:

```sql
UPDATE orders
SET created_at = CURRENT_DATE - (((id - 1) % 14)::int * INTERVAL '1 day');
```

---

## 4. JSONB, анализ планов и индексы

### Задание 1. Добавление JSONB и заполнение характеристик

Назначение: добавить столбец `attributes` и заполнить разные наборы характеристик в зависимости от типа товара.

```sql
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
```

Результат: характеристики заполнены у 400 товаров. Фрагмент:

```
 Номер товара |     Товар      |                     Характеристики
--------------+----------------+--------------------------------------------------------
            1 | Ноутбук 1      | {"color": "silver", "memory": "512 GB", "weight": 1500}
            2 | Наушники 2     | {"color": "white", "wireless": true}
            3 | Клавиатура 3   | {"color": "black", "connection": "USB"}
           10 | Телефон 10     | {"color": "black", "memory": "128 GB", "weight": 180}
```

### Задание 2. Извлечение и фильтрация JSONB

Назначение: показать разницу между операторами `->`, `->>` и `@>`.

Извлечение поля через `->` — значение возвращается как JSONB:

```sql
SELECT
    p.title AS "Товар",
    p.attributes -> 'color' AS "Цвет"
FROM products AS p
WHERE p.attributes IS NOT NULL;
```

Результат: 400 строк. Фрагмент:

```
     Товар      |   Цвет
----------------+----------
 Ноутбук 1      | "silver"
 Ноутбук 11     | "silver"
 Ноутбук 21     | "silver"
```

Извлечение поля через `->>` — значение возвращается как текст:

```sql
SELECT
    p.title AS "Товар",
    p.attributes ->> 'color' AS "Цвет"
FROM products AS p
WHERE p.attributes IS NOT NULL;
```

Результат: 400 строк. Фрагмент:

```
     Товар      |  Цвет
----------------+--------
 Ноутбук 1      | silver
 Ноутбук 11     | silver
 Ноутбук 21     | silver
```

Фильтрация по содержимому через `@>`:

```sql
SELECT
    p.title AS "Товар",
    p.price AS "Цена",
    p.attributes AS "Характеристики"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}'
ORDER BY p.price DESC;
```

Результат: 200 строк (телефоны и клавиатуры чёрного цвета). Фрагмент:

```
     Товар      |  Цена   |                    Характеристики
----------------+---------+-------------------------------------------------------
 Клавиатура 693 | 9941.00 | {"color": "black", "connection": "USB"}
 Телефон 970    | 9890.00 | {"color": "black", "memory": "128 GB", "weight": 180}
 Клавиатура 623 | 9851.00 | {"color": "black", "connection": "USB"}
```

Разница между операторами: `->` возвращает значение в формате JSONB (строка в кавычках), `->>` возвращает значение как текст, `@>` проверяет, содержит ли JSONB-документ заданный фрагмент.

### Задание 3. Анализ планов выполнения запросов

Назначение: зафиксировать тип сканирования и фактическое время до создания индексов.

Запрос по категории и цене:

```sql
EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.category_id = 5
  AND p.price < 3000;
```

План: `Seq Scan on products`, отобрано 27 строк, отброшено 973, время выполнения — 0.046 мс.

```
 Seq Scan on products p  (cost=0.00..23.60 rows=1 width=532) (actual time=0.002..0.043 rows=27.00 loops=1)
   Filter: ((price < '3000'::numeric) AND (category_id = 5))
   Rows Removed by Filter: 973
 Execution Time: 0.046 ms
```

Запрос выручки продавцов:

```sql
EXPLAIN ANALYZE
SELECT
    s.store_name AS "Продавец",
    SUM(oi.quantity * oi.unit_price) AS "Выручка"
FROM sellers AS s
JOIN products AS p ON s.id = p.seller_id
JOIN order_items AS oi ON p.id = oi.product_id
GROUP BY s.id, s.store_name
ORDER BY "Выручка" DESC;
```

План: последовательное сканирование `order_items`, `products` и `sellers`, соединения через `Hash Join`, агрегация `HashAggregate`, сортировка; время выполнения — 0.352 мс.

```
 Sort  (cost=86.70..87.03 rows=130 width=556) (actual time=0.333..0.334 rows=10.00 loops=1)
   ->  HashAggregate  (cost=80.51..82.14 rows=130 width=556) (actual time=0.329..0.331 rows=10.00 loops=1)
         ->  Hash Join  (cost=38.33..67.81 rows=1270 width=544) (actual time=0.083..0.233 rows=1000.00 loops=1)
               ->  Hash Join  (cost=25.40..51.49 rows=1270 width=28) (actual time=0.075..0.170 rows=1000.00 loops=1)
                     ->  Seq Scan on order_items oi  (cost=0.00..22.70 rows=1270 width=28) (actual time=0.003..0.035 rows=1000.00 loops=1)
                     ->  Hash  (cost=22.40..22.40 rows=240 width=16) (actual time=0.068..0.068 rows=1000.00 loops=1)
                           ->  Seq Scan on products p  (cost=0.00..22.40 rows=240 width=16) (actual time=0.001..0.033 rows=1000.00 loops=1)
               ->  Hash  (cost=11.30..11.30 rows=130 width=524) (actual time=0.005..0.005 rows=10.00 loops=1)
                     ->  Seq Scan on sellers s  (cost=0.00..11.30 rows=130 width=524) (actual time=0.002..0.003 rows=10.00 loops=1)
 Execution Time: 0.352 ms
```

Запрос заказов за сутки:

```sql
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
```

План: `Seq Scan on orders` (72 строки, отброшено 928), `Seq Scan on order_items`, `Hash Join`, `GroupAggregate`, сортировка; время выполнения — 0.161 мс.

```
 GroupAggregate  (cost=66.47..66.62 rows=5 width=36) (actual time=0.145..0.145 rows=1.00 loops=1)
   ->  Sort  (cost=66.47..66.49 rows=6 width=24) (actual time=0.137..0.138 rows=72.00 loops=1)
         ->  Hash Join  (cost=40.34..66.40 rows=6 width=24) (actual time=0.081..0.132 rows=72.00 loops=1)
               ->  Seq Scan on order_items oi  (cost=0.00..22.70 rows=1270 width=28) (actual time=0.001..0.023 rows=1000.00 loops=1)
               ->  Hash  (cost=40.27..40.27 rows=5 width=16) (actual time=0.079..0.079 rows=72.00 loops=1)
                     ->  Seq Scan on orders o  (cost=0.00..40.27 rows=5 width=16) (actual time=0.020..0.077 rows=72.00 loops=1)
                           Filter: ((created_at >= CURRENT_DATE) AND (created_at < (CURRENT_DATE + 1)))
                           Rows Removed by Filter: 928
 Execution Time: 0.161 ms
```

Для корректного сравнения с заданием 4 дополнительно проанализирована простая выборка заказов за сутки — до создания индекса это `Seq Scan on orders`, время выполнения 0.055 мс.

### Задание 4. Создание B-tree-индексов и сравнение планов

Назначение: ускорить фильтрацию товаров по категории и цене и выборку заказов по дате.

```sql
CREATE INDEX IF NOT EXISTS idx_products_category_price
ON products (category_id, price);

CREATE INDEX IF NOT EXISTS idx_orders_created_at
ON orders (created_at);

ANALYZE products;
ANALYZE orders;
```

Повторный анализ запроса по категории и цене:

```sql
EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.category_id = 5
  AND p.price < 3000;
```

План: `Bitmap Heap Scan` с `Bitmap Index Scan on idx_products_category_price`, 27 строк, время выполнения — 0.018 мс (до индекса — 0.046 мс).

```
 Bitmap Heap Scan on products p  (cost=4.55..25.94 rows=27 width=22) (actual time=0.012..0.015 rows=27.00 loops=1)
   Recheck Cond: ((category_id = 5) AND (price < '3000'::numeric))
   ->  Bitmap Index Scan on idx_products_category_price  (cost=0.00..4.54 rows=27 width=0) (actual time=0.009..0.009 rows=27.00 loops=1)
         Index Cond: ((category_id = 5) AND (price < '3000'::numeric))
 Execution Time: 0.018 ms
```

Повторный анализ выборки заказов по дате:

```sql
EXPLAIN ANALYZE
SELECT
    o.id AS "Номер заказа",
    o.created_at AS "Дата заказа"
FROM orders AS o
WHERE o.created_at >= CURRENT_DATE
  AND o.created_at < CURRENT_DATE + 1;
```

План: `Bitmap Heap Scan` с `Bitmap Index Scan on idx_orders_created_at`, 72 строки, время выполнения — 0.015 мс (до индекса — 0.055 мс).

```
 Bitmap Heap Scan on orders o  (cost=4.90..24.52 rows=72 width=16) (actual time=0.008..0.011 rows=72.00 loops=1)
   Recheck Cond: ((created_at >= CURRENT_DATE) AND (created_at < (CURRENT_DATE + 1)))
   ->  Bitmap Index Scan on idx_orders_created_at  (cost=0.00..4.88 rows=72 width=0) (actual time=0.006..0.006 rows=72.00 loops=1)
         Index Cond: ((created_at >= CURRENT_DATE) AND (created_at < (CURRENT_DATE + 1)))
 Execution Time: 0.015 ms
```

Сравнение: для товаров время уменьшилось с 0.046 до 0.018 мс, для заказов — с 0.055 до 0.015 мс, в обоих случаях PostgreSQL перешёл от последовательного сканирования к индексному. При этом в запросе заказов за сутки с соединением и группировкой (задание 3) основное время приходится на `order_items`, поэтому индекс по `orders.created_at` меняет доступ к заказам, но не убирает соединение.

### Задание 5. Создание GIN-индекса для JSONB

Назначение: ускорить поиск по содержимому JSONB оператором `@>`.

```sql
CREATE INDEX IF NOT EXISTS idx_products_attributes
ON products USING GIN (attributes);

ANALYZE products;

EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}';
```

Фактический план: последовательное сканирование, 200 строк, отброшено 800, время выполнения — 0.053 мс. GIN-индекс не использован.

```
 Seq Scan on products p  (cost=0.00..32.50 rows=200 width=22) (actual time=0.003..0.048 rows=200.00 loops=1)
   Filter: (attributes @> '{"color": "black"}'::jsonb)
   Rows Removed by Filter: 800
 Execution Time: 0.053 ms
```

Причина: условие отбирает 200 из 1000 строк (20%), а таблица небольшая, поэтому стоимость последовательного сканирования (32.50) ниже стоимости индексного доступа (36.47). Чтобы убедиться, что индекс работоспособен, дополнительно выполнен план при отключённом последовательном сканировании:

```sql
SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT
    p.title AS "Товар",
    p.price AS "Цена"
FROM products AS p
WHERE p.attributes @> '{"color": "black"}';

SET enable_seqscan = on;
```

```
 Bitmap Heap Scan on products p  (cost=13.97..36.47 rows=200 width=22) (actual time=0.013..0.031 rows=200.00 loops=1)
   Recheck Cond: (attributes @> '{"color": "black"}'::jsonb)
   ->  Bitmap Index Scan on idx_products_attributes  (cost=0.00..13.92 rows=200 width=0) (actual time=0.010..0.010 rows=200.00 loops=1)
         Index Cond: (attributes @> '{"color": "black"}'::jsonb)
 Execution Time: 0.039 ms
```

Индекс используется как `Bitmap Index Scan`, но при данном объёме данных и такой доле подходящих строк оптимизатор предпочитает последовательное сканирование.

### Задание 6. Сравнение массовой вставки с индексом и без индекса

Назначение: оценить накладные расходы на поддержку индекса при вставке. Создаются две временные таблицы с одинаковой структурой, во вторую добавляется индекс по `category_id`.

```sql
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

CREATE INDEX idx_products_test_category
ON products_test_with_index (category_id);
```

Массовая вставка без индекса:

```sql
EXPLAIN ANALYZE
INSERT INTO products_test_no_index (id, title, price, category_id)
SELECT
    p.id,
    p.title,
    p.price,
    p.category_id
FROM products AS p
CROSS JOIN generate_series(1, 100) AS n;
```

Результат: вставлено 100 000 строк, время выполнения — 17.882 мс.

```
 Insert on products_test_no_index  (cost=0.00..1283.50 rows=0 width=0) (actual time=17.844..17.844 rows=0.00 loops=1)
   Buffers: shared hit=20, local hit=101792 dirtied=857 written=859
 Execution Time: 17.882 ms
```

Массовая вставка с индексом:

```sql
EXPLAIN ANALYZE
INSERT INTO products_test_with_index (id, title, price, category_id)
SELECT
    p.id,
    p.title,
    p.price,
    p.category_id
FROM products AS p
CROSS JOIN generate_series(1, 100) AS n;
```

Результат: вставлено 100 000 строк, время выполнения — 40.095 мс.

```
 Insert on products_test_with_index  (cost=0.00..1283.50 rows=0 width=0) (actual time=40.084..40.085 rows=0.00 loops=1)
   Buffers: shared hit=33, local hit=300625 read=1 dirtied=939 written=1713
 Execution Time: 40.095 ms
```

Сравнение: вставка в таблицу с индексом примерно в 2.2 раза медленнее (40.095 против 17.882 мс) и требует больше операций с буферами (300 625 против 101 792), поскольку PostgreSQL поддерживает индекс при добавлении каждой строки.

### Задание 7. Обоснование созданных индексов

`idx_products_category_price` — составной B-tree-индекс по `(category_id, price)`. Он соответствует условию `WHERE category_id = ... AND price < ...`: сначала выполняется поиск по категории, затем диапазонный поиск по цене внутри неё. На запросе задания 3 он дал выигрыш с 0.046 до 0.018 мс.

`idx_orders_created_at` — B-tree-индекс по дате создания заказа. Условие `created_at >= ... AND created_at < ...` превращается в диапазонный поиск по индексу; на выборке за сутки время уменьшилось с 0.055 до 0.015 мс.

`idx_products_attributes` — GIN-индекс по JSONB. Он хранит отдельные ключи и значения документа и подходит для проверки вложенности оператором `@>`. На текущем объёме данных PostgreSQL выбирает последовательное сканирование, но при отключённом `Seq Scan` индекс используется, то есть он применим к запросам этого вида и станет выгоднее при росте таблицы или более селективном условии.

Индексы ускоряют чтение, но занимают место и замедляют вставку, обновление и удаление (задание 6). Поэтому индексы создаются под конкретные запросы, а решение об их необходимости подтверждается планами `EXPLAIN ANALYZE`.

---

## 5. Как запустить

```bash
psql -U postgres -d marketplace -f lab_1/01_schema.sql
psql -U postgres -d marketplace -f lab_2/lab2_requests.sql
psql -U postgres -d marketplace -f lab_6/lab6_queries.sql
```

Скрипт выполняется в одном сеансе `psql`: временные таблицы задания 6 существуют только в текущем соединении. Индексы создаются через `CREATE INDEX IF NOT EXISTS`, столбец `attributes` — через `ADD COLUMN IF NOT EXISTS`, поэтому повторный запуск не приводит к ошибкам.

---

## 6. Вывод

В ходе работы освоен тип JSONB: характеристики товаров хранятся в структурированном виде, извлекаются операторами `->` и `->>` и фильтруются оператором `@>`. С помощью `EXPLAIN ANALYZE` изучены планы выполнения запросов и зафиксированы типы сканирования и фактическое время. Созданные B-tree-индексы перевели запросы по категории и цене и по дате заказа с последовательного сканирования на индексное, сократив время выполнения с 0.046 до 0.018 мс и с 0.055 до 0.015 мс соответственно. GIN-индекс для JSONB на текущем объёме данных не выбирается оптимизатором из-за низкой селективности условия, но подтверждена его работоспособность при индексном доступе. Сравнение массовой вставки показало, что поддержка индекса замедляет вставку 100 000 строк с 17.882 до 40.095 мс, поэтому индексы следует создавать с учётом частоты запросов и результатов анализа планов. Все задания проверены выполнением в PostgreSQL 18.6.
