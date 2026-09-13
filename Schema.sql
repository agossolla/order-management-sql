-- =========================================================
-- Order management system
-- Relational database with views, roles, stored procedures,
-- functions, triggers, and transaction control.
-- =========================================================

-- Create the database
CREATE DATABASE pedidos
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_unicode_ci;

USE pedidos;

-- =========================================================
-- Tables
-- =========================================================

CREATE TABLE clientes (
    idcliente int primary key auto_increment,
    apellido_c varchar (50) not null,
    nombre_c varchar (50) not null,
    direccion_c varchar (50),
    mail_c varchar (50) not null UNIQUE
);

CREATE TABLE vendedor (
    idvendedor int primary key auto_increment,
    apellido_v varchar (50) not null,
    nombre_v varchar (50) not null,
    mail_v varchar (50) not null UNIQUE,
    comision float not null
    CONSTRAINT chk_comision CHECK (comision between 0 and 100)
);

CREATE TABLE proveedor (
    idproveedor int primary key auto_increment,
    nombre_p varchar (50) not null,
    direccion_p varchar (50),
    mail_p varchar (50) not null UNIQUE
);

CREATE TABLE productos(
    idproducto int primary key auto_increment,
    descripcion varchar (200) not null,
    precio_unitario float not null,
    stock int not null,
    stock_min int not null,
    stock_max int not null,
    idproveedor int not null, constraint fk_idproveedor foreign key (idproveedor) references proveedor,
    origen varchar (50) not null,
    CONSTRAINT chk_precio CHECK (precio_unitario >=0),
    CONSTRAINT chk_stock CHECK (stock>= 0 AND stock_min >= 0 AND stock_max>=0),
    CONSTRAINT chk_origen CHECK (origen in ('Nacional', 'Importado'))
);

CREATE TABLE pedidos(
    numero_pedido int primary key auto_increment,
    idcliente int not null, constraint fk_cliente foreign key (idcliente) references clientes ON DELETE restrict ON UPDATE CASCADE,
    idvendedor int not null, constraint fk_idvendedor foreign key (idvendedor) references vendedor ON DELETE restrict ON UPDATE CASCADE,
    fecha date not null,
    estado varchar (20) not null
);

CREATE TABLE detalle_pedidos(
    renglon int not null,
    numero_pedido int not null, constraint fk_numpedido foreign key (numero_pedido) references pedidos ON DELETE restrict ON UPDATE CASCADE,
    idproducto int not null, constraint fk_idproducto foreign key (idproducto) references productos ON DELETE restrict ON UPDATE CASCADE,
    cantidad int not null,
    precio_unitario_dp float not null,
    total float not null,
    primary key (numero_pedido, renglon)
);

-- =========================================================
-- Views
-- =========================================================

-- Customers with at least one order within a given date range
CREATE VIEW vw_clientes_activos AS
SELECT DISTINCT c.idcliente as ID, CONCAT(c.nombre_c, ' ', c.apellido_c) AS nombre_completo, c.mail_c AS mail
FROM clientes AS c
INNER JOIN pedidos AS p USING (idcliente)
WHERE p.fecha> '2025-11-20' AND p.fecha<'2025-12-10';

-- Number of orders handled by each sales rep, ranked by performance
CREATE VIEW vw_rendimiento_vendedores AS
SELECT v.idvendedor AS ID, CONCAT(v.nombre_v, ' ', v.apellido_v) AS nombre_completo, COUNT(p.numero_pedido) AS cantidad_pedidos
FROM vendedor AS v
INNER JOIN pedidos AS p USING (idvendedor)
GROUP BY v.idvendedor, nombre_completo
ORDER BY cantidad_pedidos DESC;

-- Orders whose total exceeds a high-value threshold
CREATE VIEW vw_pedidos_alto_valor AS
SELECT p.numero_pedido, SUM(dp.total) AS total
FROM pedidos AS p
INNER JOIN detalle_pedidos AS dp USING (numero_pedido)
GROUP BY p.numero_pedido
HAVING SUM(dp.total) > 500000;

-- Units sold per product within a given period
CREATE VIEW vw_productos_vendidos_periodo AS
SELECT pr.idproducto, pr.descripcion, pr.origen, SUM(dp.cantidad) AS total_unidades
FROM pedidos AS p
INNER JOIN detalle_pedidos AS dp USING (numero_pedido)
INNER JOIN productos AS pr ON pr.idproducto=dp.idproducto
WHERE p.fecha>= '2025-11-20' AND p.fecha<='2025-12-10'
GROUP BY pr.idproducto, pr.descripcion, pr.origen;

-- Customers who have never placed an order
CREATE VIEW vw_clientes_sin_pedidos AS
SELECT c.idcliente, CONCAT(c.nombre_c, ' ', c.apellido_c)
FROM clientes AS c
WHERE NOT EXISTS(
    SELECT *
    FROM pedidos AS p
    WHERE p.idcliente=c.idcliente
);

-- Customers with fewer than 2 orders in total
CREATE VIEW vw_clientes_ocacionales AS
SELECT c.idcliente, CONCAT(c.nombre_c, ' ', c.apellido_c) AS nombre_completo, COUNT(p.numero_pedido) AS cantidad_pedidos
FROM clientes AS c
INNER  JOIN pedidos AS p USING (idcliente)
GROUP BY c.idcliente, nombre_completo
HAVING cantidad_pedidos<2;

-- =========================================================
-- Roles and users
-- =========================================================

CREATE ROLE 'rol_auditor';
GRANT SELECT ON pedidos.* TO 'rol_auditor';

CREATE ROLE 'rol_vendedor';
GRANT SELECT, UPDATE, INSERT ON pedidos TO 'rol_vendedor';
GRANT SELECT, UPDATE ON clientes TO 'rol_vendedor';
GRANT SELECT, UPDATE, INSERT ON detalle_pedidos TO 'rol_vendedor';

CREATE ROLE 'rol_admin';
GRANT ALL PRIVILEGES ON pedidos.* TO 'rol_admin';

CREATE USER 'usuario_auditoria';
GRANT 'rol_auditor' TO 'usuario_auditoria';
SET DEFAULT ROLE 'rol_auditor' TO 'usuario_auditoria'@'%';

CREATE USER 'usuario_ventas1';
GRANT 'rol_vendedor' TO 'usuario_ventas1';
SET DEFAULT ROLE 'rol_vendedor' TO 'usuario_ventas1'@'%';

CREATE USER 'usuario_admin1';
GRANT 'rol_admin' TO 'usuario_admin1';
SET DEFAULT ROLE 'rol_admin' TO 'usuario_admin1'@'%';

-- =========================================================
-- Queries and index optimization
-- =========================================================

-- Imported products sold within a period, ranked by volume
SELECT p.descripcion, SUM(dp.cantidad) AS total_vendido
FROM Productos p
JOIN Detalle_Pedidos dp ON p.idproducto = dp.idproducto
JOIN Pedidos pe ON dp.numero_pedido = pe.numero_pedido
WHERE pe.fecha BETWEEN '2024-01-01' AND '2024-06-30'
AND p.origen = 'Importado'
GROUP BY p.descripcion
ORDER BY total_vendido DESC;

-- Indexes to optimize the query above (filtering by date and by origin)
CREATE INDEX idx_fecha_pedidos
ON pedidos (fecha);

CREATE INDEX idx_productos_importados
ON productos (origen);

-- EXPLAIN ANALYZE confirmed that, after adding these indexes, the query plan
-- goes from a full table scan to an index range scan on idx_fecha_pedidos,
-- reducing both the estimated cost and the actual execution time.

-- =========================================================
-- Transactions
-- =========================================================

-- Case A: register an order with two line items and deduct stock
START TRANSACTION;
    INSERT INTO Pedidos(idcliente, idvendedor, fecha, estado)
    VALUES (1, 1, "2026-08-14", "pendiente");

    SET @numero_pedido = LAST_INSERT_ID();
    SELECT @numero_pedido AS Numero_Pedido_generado;

    INSERT INTO Detalle_pedidos(renglon, numero_pedido, idproducto, cantidad, precio_unitario_dp, total)
    VALUE (1, @numero_pedido, 100, 5, 1246942.87, 6234714.35);

    INSERT INTO Detalle_pedidos(renglon, numero_pedido, idproducto, cantidad, precio_unitario_dp, total)
    VALUE (2, @numero_pedido, 220, 5, 1246942.87, 6234714.35);

    UPDATE productos
    SET stock = stock - 5
    WHERE idproducto = 100;

    UPDATE productos
    SET stock = stock - 5
    WHERE idproducto = 220;

    COMMIT;

-- Case B: attempt to place an order for a non-existent customer -> fails on FK and rolls back
INSERT INTO Pedidos(numero_pedido, idcliente, idvendedor, fecha, estado)
VALUES (300, 99999, 67, "2026-08-29", "Pendiente");
-- Expected error (fk_cliente constraint): the operation is rolled back
ROLLBACK;

-- Case C: using a savepoint to roll back only part of a transaction
START TRANSACTION;
    UPDATE productos
    SET precio_unitario = precio_unitario * 0.80
    WHERE idproducto = 7;

    SAVEPOINT punto1;

    UPDATE productos
    SET stock = stock - 3
    WHERE idproducto = 260;

    ROLLBACK TO SAVEPOINT punto1;
    COMMIT;

-- =========================================================
-- Stored functions
-- =========================================================

-- Calculates an order's total by summing its line items
DELIMITER //
    CREATE FUNCTION fn_calcular_total_pedido (p_numero_pedido INT)
    RETURNS DECIMAL (12,2)
    READS SQL DATA
    BEGIN
        DECLARE v_total DECIMAL (12,2);
        SELECT COALESCE (SUM(dp.total), 0.00) INTO v_total
        FROM detalle_pedidos dp
        WHERE dp.numero_pedido = p_numero_pedido;

        RETURN v_total;
    END//
DELIMITER ;

-- Checks whether there is enough stock of a product for a requested quantity
DELIMITER //
    CREATE FUNCTION fn_validar_Stock_disponible (p_idproducto INT, p_cantidad INT)
    RETURNS TINYINT
    READS SQL DATA
    BEGIN
        DECLARE v_stock INT;
        SELECT p.stock INTO v_stock
        FROM productos p
        WHERE p.idproducto = p_idproducto;

        IF v_stock >= p_cantidad THEN
            RETURN 1;
        ELSE
            RETURN 0;
        END IF;
    END //
DELIMITER ;

-- =========================================================
-- Stored procedures
-- =========================================================

-- Registers a full order: validates customer, sales rep and stock,
-- inserts the order header and line item, and deducts stock.
-- Rolls back everything if an error occurs.
DELIMITER //
    CREATE PROCEDURE sp_registrar_pedido_completo (
        IN p_idcliente INT,
        IN p_idvendedor INT,
        IN p_idproducto INT,
        IN p_cantidad INT
    )
    BEGIN
        DECLARE v_idpedido INT;
        DECLARE v_preciounitario DECIMAL (12,2);

        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            ROLLBACK;
            RESIGNAL SET MESSAGE_TEXT = 'Unexpected error: the operation was rolled back.';
        END;

        START TRANSACTION;
            IF (SELECT COUNT(*) FROM clientes c WHERE c.idcliente = p_idcliente) = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: The customer does not exist';
            END IF;

            IF( SELECT COUNT(*) FROM vendedor v WHERE v.idvendedor = p_idvendedor) = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: The sales rep does not exist';
            END IF;

            IF fn_validar_Stock_disponible(p_idproducto, p_cantidad) = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Insufficient stock to process the transaction';
            END IF;

            INSERT INTO pedidos (idcliente, idvendedor, fecha, estado)
            VALUES (p_idcliente, p_idvendedor, NOW(), 'CONFIRMADO');

            SET v_idpedido = last_insert_id();

            SELECT p.precio_unitario INTO v_preciounitario
            FROM productos p
            WHERE p.idproducto = p_idproducto;

            INSERT INTO detalle_pedidos ( renglon, numero_pedido, idproducto, cantidad, precio_unitario_dp)
            VALUES (1, v_idpedido, p_idproducto, p_cantidad, v_preciounitario);

            UPDATE productos
            SET stock = stock - p_cantidad
            WHERE idproducto = p_idproducto;

            COMMIT;
        END//
DELIMITER ;

-- Increases the price of all products of a given origin by a percentage
DELIMITER //
    CREATE PROCEDURE sp_actualizar_precios_por_origen(
        IN p_origen VARCHAR (20),
        IN p_porcentaje_incremento DECIMAL (5,2)
    )
    BEGIN
        IF p_porcentaje_incremento<= 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: the increase must be a positive value';
        END IF;

        UPDATE productos
        SET precio_unitario = precio_unitario* (1 + p_porcentaje_incremento/100)
        WHERE origen=p_origen;

        COMMIT;
    END//
DELIMITER ;

-- =========================================================
-- Auditing: log table, trigger, and cancellation procedure
-- =========================================================

-- Logs every cancelled order: order number, date, user, and reason
CREATE TABLE Log_Anulaciones (
    idlog INT AUTO_INCREMENT PRIMARY KEY,
    numero_pedido INT NOT NULL,
    fecha_anulacion DATETIME NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    motivo VARCHAR(255) DEFAULT 'Anulación requerida por el cliente'
);

-- Automatically inserts an audit record when an order's status changes to ANULADO
DELIMITER //
    CREATE TRIGGER trg_audit_anulacion_pedido
    AFTER UPDATE
    ON pedidos
    FOR EACH ROW
    BEGIN
        IF OLD.estado <> 'ANULADO' AND NEW.estado = 'ANULADO' THEN
            INSERT INTO Log_Anulaciones (numero_pedido, fecha_Anulacion, usuario)
            VALUES (NEW.numero_pedido, NOW(), CURRENT_USER());
        END IF;
    END//
DELIMITER ;

-- Cancels an order (validating it exists and isn't already cancelled) and restores stock
DELIMITER //
    CREATE PROCEDURE sp_anular_pedido(
        IN p_numero_pedido INT
    )
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unexpected error: the operation was rolled back';
        END;

        START TRANSACTION;
            IF (SELECT COUNT(*) FROM pedidos p WHERE p.numero_pedido=p_numero_pedido) = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: The order does not exist';
            END IF;

            IF (SELECT COUNT(*) FROM pedidos p WHERE p.numero_pedido=p_numero_pedido AND p.estado='ANULADO') > 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: The order is already cancelled';
            END IF;

            UPDATE pedidos
            SET estado = 'ANULADO'
            WHERE numero_pedido = p_numero_pedido;

            UPDATE productos p
            INNER JOIN detalle_pedidos dp USING (numero_pedido)
            SET p.stock = p.stock + dp.cantidad
            WHERE numero_pedido = p_numero_pedido;

            COMMIT;
        END//
DELIMITER ;

-- Loops through products with stock below the minimum and builds a temporary
-- table with the suggested replenishment quantities up to the maximum stock
DELIMITER //
    CREATE PROCEDURE sp_procesar_reajuste_stock_critico()
    BEGIN
        DECLARE fin_cursor INT DEFAULT 0;
        DECLARE v_idproducto INT;
        DECLARE v_descripcion VARCHAR (50);
        DECLARE v_stock INT;
        DECLARE v_stock_min INT;
        DECLARE v_stock_max INT;
        DECLARE v_cantidad_reponer INT;

        DECLARE cur_stock_critico CURSOR FOR
            SELECT p.idproducto, p.descripcion, p.stock, p.stock_min, p.stock_max
            FROM productos p
            WHERE stock<stock_min;

        DECLARE CONTINUE HANDLER FOR NOT FOUND SET fin_cursor = 1;

        DROP TEMPORARY TABLE IF EXISTS Ordenes_Compra_Sugeridas;
        CREATE TEMPORARY TABLE Ordenes_Compra_Sugeridas (
            idproducto INT,
            descripcion VARCHAR(100),
            stock_actual INT,
            stock_min INT,
            stock_max INT,
            cantidad_reponer INT
        );

        OPEN cur_stock_critico;

        bucle_productos: LOOP
            FETCH cur_stock_critico INTO v_idproducto, v_descripcion, v_stock, v_stock_min, v_stock_max;

            IF fin_cursor = 1 THEN
                LEAVE bucle_productos;
            END IF;

            SET v_cantidad_reponer = v_stock_max - v_stock;

            INSERT INTO Ordenes_Compra_Sugeridas (idproducto, descripcion, stock_actual, stock_min, stock_max, cantidad_reponer)
            VALUES (v_idproducto, v_descripcion, v_stock, v_stock_min, v_stock_max, v_cantidad_reponer);
        END LOOP bucle_productos;

        CLOSE cur_stock_critico;

        SELECT *
        FROM Ordenes_Compra_Sugeridas;
    END//
DELIMITER ;