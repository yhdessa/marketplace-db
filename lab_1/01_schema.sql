BEGIN;


CREATE TABLE IF NOT EXISTS public.addresses
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    city character varying(100) COLLATE pg_catalog."default" NOT NULL,
    street character varying(100) COLLATE pg_catalog."default" NOT NULL,
    house character varying(20) COLLATE pg_catalog."default" NOT NULL,
    partment character varying(20) COLLATE pg_catalog."default",
    CONSTRAINT addresses_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.cart_items
(
    cart_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    CONSTRAINT cart_items_pkey PRIMARY KEY (cart_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.carts
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT carts_pkey PRIMARY KEY (id),
    CONSTRAINT carts_user_id_key UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS public.categories
(
    id bigserial NOT NULL,
    name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT categories_pkey PRIMARY KEY (id),
    CONSTRAINT categories_name_key UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS public.deliveries
(
    id bigserial NOT NULL,
    order_id bigint NOT NULL,
    address_id bigint NOT NULL,
    delivery_status character varying COLLATE pg_catalog."default" NOT NULL DEFAULT 'processing'::character varying,
    delivery_date timestamp with time zone,
    CONSTRAINT deliveries_pkey PRIMARY KEY (id),
    CONSTRAINT deliveries_order_id_key UNIQUE (order_id)
);

CREATE TABLE IF NOT EXISTS public.order_items
(
    order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    CONSTRAINT order_items_pkey PRIMARY KEY (order_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.orders
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    status character varying(30) COLLATE pg_catalog."default" NOT NULL DEFAULT 'created'::character varying,
    total_amount numeric(12, 2) NOT NULL DEFAULT 0.00,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT orders_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.payments
(
    id bigserial NOT NULL,
    order_id bigint NOT NULL,
    amount numeric(12, 2) NOT NULL,
    status character varying(30) COLLATE pg_catalog."default" NOT NULL DEFAULT 'pending'::character varying,
    paid_at timestamp with time zone DEFAULT now(),
    CONSTRAINT payments_pkey PRIMARY KEY (id),
    CONSTRAINT payments_order_id_key UNIQUE (order_id)
);

CREATE TABLE IF NOT EXISTS public.products
(
    id bigserial NOT NULL,
    seller_id bigint NOT NULL,
    category_id bigint NOT NULL,
    title character varying(255) COLLATE pg_catalog."default" NOT NULL,
    description text COLLATE pg_catalog."default" NOT NULL,
    price numeric(12, 2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT products_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.reviews
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    product_id bigint NOT NULL,
    score integer NOT NULL,
    comment text COLLATE pg_catalog."default",
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT reviews_pkey PRIMARY KEY (id),
    CONSTRAINT reviews_user_product_key UNIQUE (user_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.sellers
(
    id bigserial NOT NULL,
    user_id bigint NOT NULL,
    store_name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    description text COLLATE pg_catalog."default" NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT sellers_pkey PRIMARY KEY (id),
    CONSTRAINT sellers_store_name_key UNIQUE (store_name),
    CONSTRAINT user_id_unique UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS public.stock
(
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT stock_pkey PRIMARY KEY (product_id)
);

CREATE TABLE IF NOT EXISTS public.users
(
    id bigserial NOT NULL,
    full_name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    email character varying(255) COLLATE pg_catalog."default" NOT NULL,
    phone character varying(30) COLLATE pg_catalog."default",
    role character varying(20) COLLATE pg_catalog."default" NOT NULL DEFAULT 'customer'::character varying,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_email_key UNIQUE (email),
    CONSTRAINT users_phone_key UNIQUE (phone)
);

ALTER TABLE IF EXISTS public.addresses
    ADD CONSTRAINT addresses_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.users (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.cart_items
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id)
    REFERENCES public.carts (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.cart_items
    ADD CONSTRAINT cart_items_product_id_fkey FOREIGN KEY (product_id)
    REFERENCES public.products (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.carts
    ADD CONSTRAINT carts_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.users (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS carts_user_id_key
    ON public.carts(user_id);


ALTER TABLE IF EXISTS public.deliveries
    ADD CONSTRAINT deliveries_address_id_fkey FOREIGN KEY (address_id)
    REFERENCES public.addresses (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;


ALTER TABLE IF EXISTS public.deliveries
    ADD CONSTRAINT deliveries_order_id_fkey FOREIGN KEY (order_id)
    REFERENCES public.orders (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS deliveries_order_id_key
    ON public.deliveries(order_id);


ALTER TABLE IF EXISTS public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id)
    REFERENCES public.orders (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id)
    REFERENCES public.products (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;


ALTER TABLE IF EXISTS public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.users (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;


ALTER TABLE IF EXISTS public.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id)
    REFERENCES public.orders (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS payments_order_id_key
    ON public.payments(order_id);


ALTER TABLE IF EXISTS public.products
    ADD CONSTRAINT "products_category_id_fkey " FOREIGN KEY (category_id)
    REFERENCES public.categories (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;


ALTER TABLE IF EXISTS public.products
    ADD CONSTRAINT products_seller_id_fkey FOREIGN KEY (seller_id)
    REFERENCES public.sellers (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;


ALTER TABLE IF EXISTS public.reviews
    ADD CONSTRAINT reviews_product_id_fkey FOREIGN KEY (product_id)
    REFERENCES public.products (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.reviews
    ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.users (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;


ALTER TABLE IF EXISTS public.sellers
    ADD CONSTRAINT sellers_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.users (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;
CREATE INDEX IF NOT EXISTS user_id_unique
    ON public.sellers(user_id);


ALTER TABLE IF EXISTS public.stock
    ADD CONSTRAINT stock_product_id_fkey FOREIGN KEY (product_id)
    REFERENCES public.products (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS stock_pkey
    ON public.stock(product_id);

END;
