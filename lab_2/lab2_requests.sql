-- Задание 1
BEGIN;

-- Сначала очищаем таблицы, чтобы можно было запустить скрипт повторно
TRUNCATE TABLE
    addresses,
    cart_items,
    carts,
    deliveries,
    order_items,
    payments,
    reviews,
    stock,
    orders,
    products,
    sellers,
    categories,
    users
RESTART IDENTITY CASCADE;


-- Пользователи
INSERT INTO users (full_name, email, phone, role)
SELECT
    'Пользователь ' || g,
    'user' || g || '@mail.ru',
    '+7900000' || LPAD(g::text, 4, '0'),
    CASE
        WHEN g <= 10 THEN 'seller'
        ELSE 'customer'
    END
FROM generate_series(1, 100) AS g;


-- Категории товаров
INSERT INTO categories (name)
SELECT 'Категория ' || g
FROM generate_series(1, 10) AS g;


-- Продавцы
INSERT INTO sellers (user_id, store_name, description)
SELECT
    g,
    'Магазин ' || g,
    'Интернет-магазин товаров ' || g
FROM generate_series(1, 10) AS g;


-- Адреса пользователей
INSERT INTO addresses (user_id, city, street, house, partment)
SELECT
    g,
    CASE
        WHEN g % 3 = 0 THEN 'Москва'
        WHEN g % 3 = 1 THEN 'Санкт-Петербург'
        ELSE 'Казань'
    END,
    'Улица ' || g,
    (1 + g % 100)::text,
    CASE
        WHEN g % 5 = 0 THEN NULL
        ELSE (1 + g % 50)::text
    END
FROM generate_series(1, 100) AS g;


-- Корзины
INSERT INTO carts (user_id)
SELECT g
FROM generate_series(1, 100) AS g;


-- Товары
INSERT INTO products (
    seller_id,
    category_id,
    title,
    description,
    price,
    is_active
)
SELECT
    1 + (g % 10),
    1 + (g % 10),
    CASE
        WHEN g % 10 = 0 THEN 'Телефон ' || g
        WHEN g % 10 = 1 THEN 'Ноутбук ' || g
        WHEN g % 10 = 2 THEN 'Наушники ' || g
        WHEN g % 10 = 3 THEN 'Клавиатура ' || g
        ELSE 'Товар ' || g
    END,
    'Описание товара ' || g,
    (500 + (g * 137 % 9500))::numeric(10,2),
    CASE
        WHEN g % 20 = 0 THEN FALSE
        ELSE TRUE
    END
FROM generate_series(1, 1000) AS g;


-- Количество товаров на складе
INSERT INTO stock (product_id, quantity)
SELECT
    g,
    10 + (g % 90)
FROM generate_series(1, 1000) AS g;


-- Товары в корзинах
INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT
    1 + ((g - 1) % 100),
    1 + ((g * 7 - 1) % 1000),
    1 + (g % 5)
FROM generate_series(1, 500) AS g;


-- Заказы
INSERT INTO orders (
    user_id,
    status,
    total_amount
)
SELECT
    1 + ((g - 1) % 100),
    CASE
        WHEN g % 5 = 0 THEN 'cancelled'
        WHEN g % 5 = 1 THEN 'new'
        WHEN g % 5 = 2 THEN 'processing'
        WHEN g % 5 = 3 THEN 'shipped'
        ELSE 'delivered'
    END,
    (
        (1 + (g % 3))
        *
        (500 + (g * 137 % 9500))
    )::numeric(12,2)
FROM generate_series(1, 1000) AS g;


-- Состав заказов
INSERT INTO order_items (
    order_id,
    product_id,
    quantity,
    unit_price
)
SELECT
    g,
    1 + ((g * 7 - 1) % 1000),
    1 + (g % 3),
    (500 + (g * 137 % 9500))::numeric(10,2)
FROM generate_series(1, 1000) AS g;


-- Оплата заказов
INSERT INTO payments (
    order_id,
    amount,
    status,
    paid_at
)
SELECT
    g,
    (
        (1 + (g % 3))
        *
        (500 + (g * 137 % 9500))
    )::numeric(12,2),
    CASE
        WHEN g % 5 = 0 THEN 'failed'
        WHEN g % 5 = 1 THEN 'pending'
        ELSE 'paid'
    END,
    CASE
        WHEN g % 5 = 0 THEN NULL
        ELSE CURRENT_TIMESTAMP - (g || ' days')::interval
    END
FROM generate_series(1, 1000) AS g;


-- Доставка заказов
INSERT INTO deliveries (
    order_id,
    address_id,
    delivery_status,
    delivery_date
)
SELECT
    g,
    1 + ((g - 1) % 100),
    CASE
        WHEN g % 4 = 0 THEN 'pending'
        WHEN g % 4 = 1 THEN 'processing'
        WHEN g % 4 = 2 THEN 'shipped'
        ELSE 'delivered'
    END,
    CASE
        WHEN g % 4 = 0 THEN NULL
        ELSE CURRENT_DATE + (g % 30)
    END
FROM generate_series(1, 1000) AS g;


-- Отзывы
INSERT INTO reviews (
    user_id,
    product_id,
    score,
    comment
)
SELECT
    1 + ((g - 1) % 100),
    1 + ((g - 1) % 1000),
    1 + (g % 5),
    CASE
        WHEN g % 3 = 0 THEN NULL
        ELSE 'Отзыв о товаре ' || g
    END
FROM generate_series(1, 1000) AS g;


COMMIT;

-- Задание 2
SELECT DISTINCT
    category_id AS "Код категории",
    price AS "Цена (руб.)",
	description AS "Описание"
FROM products;

-- Задание 3
SELECT title AS "Наименование", description AS "Описание", price AS "Цена (руб.)"
FROM products
WHERE is_active AND (price < 1000 OR price > 5000);

-- Задание 4
SELECT id, title, category_id, price, description
FROM products
WHERE category_id IN (1, 3, 5, 7, 9) AND price BETWEEN 500 AND 35000 AND description IS NOT NULL
	AND title NOT ILIKE '%Телефон%';

-- Задание 5
SELECT id, city, street, house
FROM addresses
ORDER BY id DESC, house;

-- Задание 6
SELECT  id, title, price
FROM products
ORDER BY id ASC
LIMIT 5 OFFSET 5;
