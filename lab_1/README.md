# Отчёт по лабораторной работе №1
**Дисциплина:** Математические основы баз данных
**Тема:** Проектирование реляционной схемы базы данных для маркетплейса

---

## 1. Цель работы

Изучение теоретических основ проектирования реляционных баз данных, освоение принципов нормализации отношений до 3-й нормальной формы (3НФ), разработка концептуальной и логической схемы базы данных для предметной области «Маркетплейс» и её физическая реализация в СУБД PostgreSQL.

---

## 2. Описание предметной области

Предметная область — электронная торговая площадка (маркетплейс), связывающая покупателей и продавцов. Система должна обеспечивать выполнение следующих функций:

* Управление пользователями и их ролями (покупатели, продавцы);
* Ведение каталога товаров, распределенных по категориям;
* Управление профилями магазинов (продавцов);
* Организация корзины товаров для покупателей;
* Оформление и обработка заказов, а также учет позиций заказа;
* Фиксация платежей и статусов доставки;
* Учет остатков товаров на складе;
* Сбор отзывов и оценок покупателей на товары.

---

## 3. Логическое проектирование и нормализация (3НФ)

В результате анализа предметной области выделено **13 сущностей**. Схема базы данных приведена к третьей нормальной форме (3НФ):

1. **1НФ:** Все атрибуты атомарны, у таблиц определены первичные ключи.
2. **2НФ:** Все неключевые атрибуты функционально полно зависят от первичного ключа. Связи «многие-ко-многим» (товары в заказах и корзинах) развязаны через промежуточные таблицы (`order_items`, `cart_items`).
3. **3НФ:** Транзитивные зависимости между неключевыми атрибутами отсутствуют.

### Список таблиц и их назначение

* `users` — учетные записи пользователей системы;
* `sellers` — профили продавцов/магазинов (связь 1:1 с `users`, `UNIQUE(user_id)`);
* `addresses` — адреса доставки пользователей;
* `categories` — плоский справочник категорий товаров;
* `products` — каталог товаров;
* `stock` — учет количества товара на складе (связь 1:1 с `products`, PK по `product_id`);
* `carts` — корзины покупателей (связь 1:1 с `users`, `UNIQUE(user_id)`);
* `cart_items` — товары в корзине (N:M между `carts` и `products`, PK `(cart_id, product_id)`);
* `orders` — оформленные заказы;
* `order_items` — состав заказа с фиксацией цены на момент покупки (`unit_price`, PK `(order_id, product_id)`);
* `payments` — данные об оплате заказов (связь 1:1 с `orders`, `UNIQUE(order_id)`);
* `deliveries` — сведения о доставке заказов (связь 1:1 с `orders`, `UNIQUE(order_id)`, привязка к `addresses`);
* `reviews` — отзывы покупателей на товары (один отзыв пользователя на товар, `UNIQUE(user_id, product_id)`).

---

## 4. ER-диаграмма

Физическая схема базы данных, сгенерированная в pgAdmin 4:

![ER-диаграмма базы данных](./erd_lab1.png)

---

## 5. Физическая реализация (DDL-скрипт)

База данных реализована в **PostgreSQL 18.6**. Полный скрипт — в файле [`01_schema.sql`](./01_schema.sql): транзакционный (`BEGIN; ... END;`), идемпотентный (`CREATE TABLE IF NOT EXISTS`, `ALTER TABLE IF EXISTS`), PK на `bigserial`, деньги — `numeric(12,2)`, целостность — `FOREIGN KEY`. Ниже — ключевые фрагменты из реального скрипта:

```sql
-- Таблица пользователей
CREATE TABLE IF NOT EXISTS public.users
(
    id bigserial NOT NULL,
    full_name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(30),
    role character varying(20) NOT NULL DEFAULT 'customer',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_email_key UNIQUE (email),
    CONSTRAINT users_phone_key UNIQUE (phone)
);

-- Таблица продавцов (1:1 с users)
CREATE TABLE IF NOT EXISTS public.sellers
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    store_name character varying(255) NOT NULL,
    description text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT sellers_pkey PRIMARY KEY (id),
    CONSTRAINT sellers_store_name_key UNIQUE (store_name),
    CONSTRAINT user_id_unique UNIQUE (user_id)
);

-- Таблица категорий (плоский справочник)
CREATE TABLE IF NOT EXISTS public.categories
(
    id bigserial NOT NULL,
    name character varying(255) NOT NULL,
    CONSTRAINT categories_pkey PRIMARY KEY (id),
    CONSTRAINT categories_name_key UNIQUE (name)
);

-- Таблица товаров
CREATE TABLE IF NOT EXISTS public.products
(
    id bigserial NOT NULL,
    seller_id bigint NOT NULL,
    category_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    description text NOT NULL,
    price numeric(12, 2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT products_pkey PRIMARY KEY (id)
);

-- Таблица остатков на складе (1:1 с products)
CREATE TABLE IF NOT EXISTS public.stock
(
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT stock_pkey PRIMARY KEY (product_id)
);

-- Таблица заказов
CREATE TABLE IF NOT EXISTS public.orders
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    status character varying(30) NOT NULL DEFAULT 'created',
    total_amount numeric(12, 2) NOT NULL DEFAULT 0.00,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT orders_pkey PRIMARY KEY (id)
);

-- Позиции в заказе (с фиксацией цены покупки)
CREATE TABLE IF NOT EXISTS public.order_items
(
    order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    CONSTRAINT order_items_pkey PRIMARY KEY (order_id, product_id)
);
```

Остальные таблицы (`addresses`, `carts`, `cart_items`, `payments`, `deliveries`, `reviews`) и все внешние ключи (`ON DELETE CASCADE / RESTRICT / NO ACTION` — см. `ALTER TABLE ... ADD CONSTRAINT` в конце скрипта) — в полном файле [`01_schema.sql`](./01_schema.sql).

Запуск:

```bash
psql -U postgres -d marketplace -f lab_1/01_schema.sql
```

---

## 6. Вывод

В ходе выполнения лабораторной работы №1 была полностью спроектирована реляционная база данных для маркетплейса. Были построены концептуальная, логическая и физическая модели данных, проведена нормализация до 3НФ, а также сформирован и успешно выполнен DDL-скрипт создания структуры в PostgreSQL.
