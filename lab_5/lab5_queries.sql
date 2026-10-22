-- Задание 1. Транзакция с COMMIT
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

-- Проверка результата транзакции
SELECT o.id AS "Номер заказа", o.total_amount AS "Сумма заказа",
    oi.product_id AS "Товар", oi.quantity AS "Количество",
    s.quantity AS "Остаток на складе"
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock AS s ON s.product_id = oi.product_id
WHERE o.user_id = 42
ORDER BY o.id DESC
LIMIT 1;


-- Задание 1. Транзакция с ROLLBACK
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


-- Задание 2. Функция оформления заказа
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

-- Проверка функции оформления заказа
SELECT place_order(42, 7, 2) AS "Номер заказа";

SELECT quantity AS "Остаток на складе"
FROM stock
WHERE product_id = 7;


-- Задание 3. Функция расчёта выручки продавца
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

-- Проверка выручки продавца
SELECT seller_revenue(1, CURRENT_DATE - 30, CURRENT_DATE) AS "Выручка продавца";


-- Задание 4. Таблица аудита цен
CREATE TABLE IF NOT EXISTS product_price_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price NUMERIC(12, 2) NOT NULL,
    new_price NUMERIC(12, 2) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Функция аудита изменения цены
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

-- Триггер аудита изменения цены
DROP TRIGGER IF EXISTS trg_audit_product_price ON products;

CREATE TRIGGER trg_audit_product_price
AFTER UPDATE OF price ON products
FOR EACH ROW
EXECUTE FUNCTION audit_product_price();

-- Изменение цены товара
UPDATE products
SET price = price + 100
WHERE id = 7;

-- Просмотр истории изменения цен
SELECT
    product_id AS "Товар",
    old_price AS "Старая цена",
    new_price AS "Новая цена",
    changed_at AS "Дата изменения"
FROM product_price_audit
ORDER BY id DESC;


-- Задание 5. Добавление поля рейтинга товара
ALTER TABLE products
ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2);

-- Функция пересчёта среднего рейтинга
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

-- Триггер пересчёта рейтинга
DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;

CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();

-- Добавление отзыва
INSERT INTO reviews (user_id, product_id, score, comment)
VALUES (1, 7, 5, 'Хороший товар')
ON CONFLICT (user_id, product_id)
DO UPDATE SET score = EXCLUDED.score,
              comment = EXCLUDED.comment;

-- Просмотр рейтинга товара
SELECT
    id AS "Номер товара",
    title AS "Товар",
    rating AS "Средний рейтинг"
FROM products
WHERE id = 7;


-- Задание 6. Обоснование размещения логики в БД и приложении
-- В базе данных целесообразно размещать логику, которая непосредственно связана
-- с целостностью данных: проверку складских остатков при оформлении заказа,
-- атомарное изменение связанных таблиц, ведение журнала изменения цен и пересчёт
-- среднего рейтинга товаров. Это позволяет применять единые правила независимо
-- от приложения, которое обращается к базе данных.
-- В приложении удобнее размещать логику взаимодействия с пользователем,
-- отображение информации, обработку пользовательского интерфейса и сценарии
-- работы с сервисами.
-- Таким образом, критичные правила целостности следует контролировать на стороне
-- базы данных, а логику интерфейса и взаимодействия с пользователем — на стороне
-- приложения.
