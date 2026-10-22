# Отчёт по лабораторной работе №5
**Дисциплина:** Математические основы баз данных
**Тема:** Транзакции, целостность данных и серверная логика (на примере БД маркетплейса)

---

## 1. Цель работы

Освоить механизм транзакций PostgreSQL (`BEGIN`, `COMMIT`, `ROLLBACK`, свойства ACID), разработку функций на языке PL/pgSQL для атомарного выполнения связанных изменений и триггеры для аудита данных и поддержки денормализованных полей, а также принципы распределения бизнес-логики между базой данных и приложением.

---

## 2. Постановка задачи (по пособию)

1. Продемонстрировать работу транзакции: выполнить связанные изменения между `BEGIN` и `COMMIT`, затем повторить сценарий с намеренной ошибкой и `ROLLBACK`, показав, что изменения отменены.
2. Реализовать функцию на PL/pgSQL, атомарно оформляющую заказ: она создаёт заказ и его позиции и уменьшает остаток, а при нехватке товара возбуждает исключение и не оставляет частичных изменений.
3. Реализовать функцию, возвращающую сводный показатель (например, выручку продавца за период) с использованием переменных и запроса внутри функции.
4. Создать триггер аудита: при изменении цены товара старое и новое значение автоматически заносятся в таблицу журнала.
5. Создать триггер, поддерживающий денормализованное поле (например, средний рейтинг товара пересчитывается при добавлении отзыва).
6. В отчёте обосновать, какую логику уместно держать в базе данных, а какую — в приложении.

Полный скрипт — в файле [`lab5_queries.sql`](./lab5_queries.sql). Для каждого задания ниже приведены текст, назначение и результат выполнения (проверено в PostgreSQL 18.6).

---

## 3. Исходные данные

Запросы работают на сквозной базе: схема из лаб 1 (`lab_1/01_schema.sql`), данные из лаб 2 (`lab_2/lab2_requests.sql`). В тестовом наборе существуют пользователь `id = 42`, товар `id = 7` с остатком на складе 17 единиц и ценой 1459.00. Скрипт воспроизводим: объекты создаются через `CREATE OR REPLACE`, `CREATE TABLE IF NOT EXISTS`, а триггеры перед повторным созданием удаляются через `DROP TRIGGER IF EXISTS`.

---

## 4. Транзакции, функции и триггеры

### Задание 1. Транзакции `COMMIT` и `ROLLBACK`

Назначение: показать, что связанные изменения применяются только после `COMMIT` и полностью отменяются при `ROLLBACK`.

Вариант с `COMMIT` — создание заказа, его позиции и уменьшение остатка в одной транзакции:

```sql
BEGIN;

WITH new_order AS (
    INSERT INTO orders (user_id, status, total_amount)
    VALUES (42, 'new', 3000.00)
    RETURNING id
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT n.id, 7, 2, 1500.00
FROM new_order AS n;

UPDATE stock
SET quantity = quantity - 2
WHERE product_id = 7
  AND quantity >= 2;

COMMIT;
```

Результат: заказ создан, позиция добавлена, остаток товара уменьшен с 17 до 15.

```
 Номер заказа | Сумма заказа | Товар | Количество | Остаток на складе
--------------+--------------+-------+------------+-------------------
         1001 |      3000.00 |     7 |          2 |                15
```

Вариант с `ROLLBACK` — создание заказа, после которого изменения отменяются:

```sql
SELECT COUNT(*) AS "Заказов до отката"
FROM orders
WHERE user_id = 42;

BEGIN;

INSERT INTO orders (user_id, status, total_amount)
VALUES (42, 'new', 1500.00);

ROLLBACK;

SELECT COUNT(*) AS "Заказов после отката"
FROM orders
WHERE user_id = 42;
```

Результат: число заказов пользователя 42 до и после отката одинаково — 11 (10 исходных и 1 заказ из транзакции с `COMMIT`). Вставка внутри отменённой транзакции в таблицу не попала.

```
 Заказов до отката
-------------------
                11

 Заказов после отката
----------------------
                   11
```

### Задание 2. Функция оформления заказа

Назначение: атомарно оформить заказ средствами PL/pgSQL — проверить количество, цену и остаток, создать заказ и позицию, уменьшить остаток. При нехватке товара функция возбуждает исключение, и все изменения отменяются.

```sql
CREATE OR REPLACE FUNCTION place_order(
    p_user BIGINT,
    p_product BIGINT,
    p_qty INT
)
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_price NUMERIC(12, 2);
    v_quantity INT;
BEGIN
    IF p_qty <= 0 THEN
        RAISE EXCEPTION 'Количество товара должно быть больше нуля';
    END IF;

    SELECT price
    INTO v_price
    FROM products
    WHERE id = p_product
      AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар не найден или неактивен';
    END IF;

    SELECT quantity
    INTO v_quantity
    FROM stock
    WHERE product_id = p_product
    FOR UPDATE;

    IF NOT FOUND OR v_quantity < p_qty THEN
        RAISE EXCEPTION 'Недостаточно товара на складе';
    END IF;

    INSERT INTO orders (user_id, status, total_amount)
    VALUES (p_user, 'new', v_price * p_qty)
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product, p_qty, v_price);

    UPDATE stock
    SET quantity = quantity - p_qty
    WHERE product_id = p_product;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;
```

Вызов функции:

```sql
SELECT place_order(42, 7, 2) AS "Номер заказа";
```

Результат: создан заказ № 1003, остаток товара уменьшился с 15 до 13.

```
 Номер заказа
--------------
         1003

 Остаток на складе
-------------------
                13
```

Замечание: блокировка строки склада `FOR UPDATE` не даёт двум параллельным транзакциям одновременно списать один и тот же остаток. Если товара меньше запрошенного, выполнение прерывается через `RAISE EXCEPTION`, и вставки в `orders`/`order_items` не фиксируются.

### Задание 3. Функция расчёта выручки продавца за период

Назначение: вернуть суммарную выручку продавца за заданный период, используя переменную и запрос внутри функции.

```sql
CREATE OR REPLACE FUNCTION seller_revenue(
    p_seller BIGINT,
    p_date_start DATE,
    p_date_end DATE
)
RETURNS NUMERIC(12, 2) AS $$
DECLARE
    v_revenue NUMERIC(12, 2);
BEGIN
    IF p_date_start > p_date_end THEN
        RAISE EXCEPTION 'Начальная дата не может быть позже конечной';
    END IF;

    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0)
    INTO v_revenue
    FROM orders AS o
    JOIN order_items AS oi ON o.id = oi.order_id
    JOIN products AS p ON oi.product_id = p.id
    WHERE p.seller_id = p_seller
      AND o.created_at >= p_date_start
      AND o.created_at < p_date_end + INTERVAL '1 day';

    RETURN v_revenue;
END;
$$ LANGUAGE plpgsql;
```

Вызов функции за последние 30 дней:

```sql
SELECT seller_revenue(1, CURRENT_DATE - 30, CURRENT_DATE) AS "Выручка продавца";
```

Результат:

```
 Выручка продавца
------------------
       1028790.00
```

Замечание: верхняя граница периода задана как `p_date_end + INTERVAL '1 day'` с условием `<`, поэтому в расчёт попадают все заказы последнего дня независимо от времени оформления.

### Задание 4. Триггер аудита изменения цены товара

Назначение: автоматически сохранять старое и новое значения цены в журнале при каждом изменении цены товара.

Таблица журнала:

```sql
CREATE TABLE IF NOT EXISTS product_price_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price NUMERIC(12, 2) NOT NULL,
    new_price NUMERIC(12, 2) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Функция и триггер аудита:

```sql
CREATE OR REPLACE FUNCTION audit_product_price()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.price IS DISTINCT FROM NEW.price THEN
        INSERT INTO product_price_audit (
            product_id,
            old_price,
            new_price
        )
        VALUES (
            OLD.id,
            OLD.price,
            NEW.price
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_product_price ON products;

CREATE TRIGGER trg_audit_product_price
AFTER UPDATE OF price ON products
FOR EACH ROW
EXECUTE FUNCTION audit_product_price();
```

Проверка — изменение цены товара и просмотр журнала:

```sql
UPDATE products
SET price = price + 100
WHERE id = 7;

SELECT
    product_id AS "Товар",
    old_price AS "Старая цена",
    new_price AS "Новая цена",
    changed_at AS "Дата изменения"
FROM product_price_audit
ORDER BY id DESC;
```

Результат:

```
 Товар | Старая цена | Новая цена |        Дата изменения
-------+-------------+------------+-------------------------------
     7 |     1459.00 |    1559.00 | 2026-10-22 12:02:35.596837+03
```

Условие `IS DISTINCT FROM` не даёт записать в журнал операцию, в которой цена фактически не изменилась.

### Задание 5. Триггер пересчёта среднего рейтинга товара

Назначение: поддерживать денормализованное поле `products.rating` в актуальном состоянии при добавлении, изменении и удалении отзывов. В исходной схеме такого столбца нет, поэтому он добавляется.

```sql
ALTER TABLE products
ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2);
```

Функция и триггер пересчёта:

```sql
CREATE OR REPLACE FUNCTION refresh_product_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_product_id BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_product_id := OLD.product_id;
    ELSE
        v_product_id := NEW.product_id;
    END IF;

    UPDATE products
    SET rating = (
        SELECT ROUND(AVG(r.score), 2)
        FROM reviews AS r
        WHERE r.product_id = v_product_id
    )
    WHERE id = v_product_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;

CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();
```

Проверка — добавление отзыва и просмотр рейтинга:

```sql
INSERT INTO reviews (user_id, product_id, score, comment)
VALUES (1, 7, 5, 'Хороший товар')
ON CONFLICT (user_id, product_id)
DO UPDATE SET score = EXCLUDED.score,
              comment = EXCLUDED.comment;

SELECT
    id AS "Номер товара",
    title AS "Товар",
    rating AS "Средний рейтинг"
FROM products
WHERE id = 7;
```

Результат: у товара 7 был один отзыв с оценкой 3, после добавления оценки 5 средний рейтинг стал 4.00.

```
 Номер товара |  Товар  | Средний рейтинг
--------------+---------+-----------------
            7 | Товар 7 |            4.00
```

Ограничение `UNIQUE (user_id, product_id)` не позволяет одному пользователю оставить несколько отдельных отзывов на товар, поэтому повторная вставка через `ON CONFLICT` обновляет существующую оценку, а триггер пересчитывает среднее значение.

### Задание 6. Размещение логики в базе данных и приложении

В базе данных целесообразно размещать логику, которая непосредственно связана с целостностью данных: проверку складских остатков при оформлении заказа, атомарное изменение связанных таблиц, ведение журнала изменения цен и пересчёт среднего рейтинга товаров. Это позволяет применять единые правила независимо от приложения, которое обращается к базе данных.

В приложении удобнее размещать логику взаимодействия с пользователем, отображение информации, обработку пользовательского интерфейса и сценарии работы с сервисами.

Таким образом, критичные правила целостности следует контролировать на стороне базы данных, а логику интерфейса и взаимодействия с пользователем — на стороне приложения.

---

## 5. Как запустить

```bash
psql -U postgres -d marketplace -f lab_1/01_schema.sql
psql -U postgres -d marketplace -f lab_2/lab2_requests.sql
psql -U postgres -d marketplace -f lab_5/lab5_queries.sql
```

Скрипт можно выполнять повторно: функции пересоздаются через `CREATE OR REPLACE`, таблица аудита — через `CREATE TABLE IF NOT EXISTS`, триггеры — через `DROP TRIGGER IF EXISTS` перед созданием.

---

## 6. Вывод

В ходе работы освоены транзакции PostgreSQL и их свойства ACID: показано, что изменения применяются только после `COMMIT` и полностью отменяются при `ROLLBACK`. Реализована функция `place_order`, атомарно оформляющая заказ с проверкой остатка и блокировкой строки склада, и функция `seller_revenue`, возвращающая выручку продавца за период. Созданы триггер аудита изменения цен с журналом `product_price_audit` и триггер пересчёта среднего рейтинга товара при изменении отзывов. Определено, что критичные правила целостности должны выполняться на стороне СУБД, а пользовательские сценарии и представление данных — на стороне приложения. Все задания проверены выполнением в PostgreSQL 18.6.
