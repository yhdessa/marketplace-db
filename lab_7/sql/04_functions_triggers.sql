-- ============================================================
-- Транзакции, функции PL/pgSQL и триггеры
-- ============================================================

-- ------------------------------------------------------------
-- 1. Явная транзакция с COMMIT: оформление заказа
-- ------------------------------------------------------------
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
SET quantity = quantity - 2,
    updated_at = CURRENT_TIMESTAMP
WHERE product_id = 7
  AND quantity >= 2;

COMMIT;

SELECT
    o.id AS "Номер заказа",
    o.total_amount AS "Сумма заказа",
    oi.product_id AS "Товар",
    oi.quantity AS "Количество",
    s.quantity AS "Остаток на складе"
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock AS s ON s.product_id = oi.product_id
WHERE o.user_id = 42
ORDER BY o.id DESC
LIMIT 1;


-- ------------------------------------------------------------
-- 2. Явная транзакция с ROLLBACK
-- ------------------------------------------------------------
SELECT quantity AS "Остаток до отката"
FROM stock
WHERE product_id = 7;

BEGIN;

UPDATE stock
SET quantity = quantity - 1
WHERE product_id = 7;

ROLLBACK;

SELECT quantity AS "Остаток после отката"
FROM stock
WHERE product_id = 7;


-- ------------------------------------------------------------
-- 3. Функция оформления заказа с проверкой остатка
-- ------------------------------------------------------------
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
    SET quantity = quantity - p_qty,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = p_product;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

SELECT place_order(42, 7, 2) AS "Номер заказа";

SELECT quantity AS "Остаток на складе"
FROM stock
WHERE product_id = 7;


-- ------------------------------------------------------------
-- 4. Функция расчёта выручки продавца за период
-- ------------------------------------------------------------
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

SELECT seller_revenue(1, CURRENT_DATE - 30, CURRENT_DATE) AS "Выручка продавца";


-- ------------------------------------------------------------
-- 5. Аудит изменения цены товара
-- ------------------------------------------------------------
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

UPDATE products
SET price = price + 100
WHERE id = 7;

SELECT
    product_id AS "Товар",
    old_price AS "Старая цена",
    new_price AS "Новая цена",
    changed_at AS "Дата изменения"
FROM product_price_audit
ORDER BY id DESC
LIMIT 5;


-- ------------------------------------------------------------
-- 6. Автоматический пересчёт среднего рейтинга товара
-- ------------------------------------------------------------
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
