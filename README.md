# Order Management System — SQL

Relational database project for an order management system, covering schema design, business-logic views, access control, stored procedures/functions, triggers, transactions, and query optimization.

## Data Model

| Table             | Description                                                       |
| ----------------- | ----------------------------------------------------------------- |
| `clientes`        | Customers who place orders                                        |
| `vendedor`        | Sales reps, each with a commission rate                           |
| `proveedor`       | Suppliers of products                                             |
| `productos`       | Product catalog, with stock levels and origin (national/imported) |
| `pedidos`         | Orders, linked to a customer and a sales rep                      |
| `detalle_pedidos` | Line items for each order (product, quantity, price)              |
| `Log_Anulaciones` | Audit log of cancelled orders                                     |

## Features

**Views**

- Active customers within a date range
- Sales rep performance ranking
- High-value orders (above a threshold)
- Units sold per product in a period
- Customers with no orders
- Occasional customers (fewer than 2 orders)

**Access control**

- Three roles (`auditor`, `vendedor`, `admin`) with scoped privileges, each assigned to a dedicated user

**Business logic**

- `fn_calcular_total_pedido` — computes an order's total from its line items
- `fn_validar_stock_disponible` — checks if there's enough stock for a requested quantity
- `sp_registrar_pedido_completo` — validates customer/seller/stock and registers a full order transactionally, with rollback on error
- `sp_actualizar_precios_por_origen` — bulk price adjustment by product origin
- `sp_anular_pedido` — cancels an order, restores stock, and is audited automatically
- `sp_procesar_reajuste_stock_critico` — cursor-based procedure that flags products below minimum stock and suggests replenishment quantities

**Auditing**

- `trg_audit_anulacion_pedido` — trigger that logs every order cancellation automatically

**Transactions**

- Examples covering a multi-step order insert, a rollback on a foreign key violation, and a savepoint-based partial rollback

**Query optimization**

- Indexes on `pedidos.fecha` and `productos.origen`, verified with `EXPLAIN ANALYZE`: the query plan went from a full table scan to an index range scan

## Files

- `schema.sql` — full database structure: tables, views, roles, functions, procedures, triggers, and example transactions
- `seed.sql` — sample data to populate the database

## Running Locally

```bash
mysql -u root -p < schema.sql
mysql -u root -p < seed.sql
```

## Author

**Agostina Solla**

- GitHub: [@agossolla](https://github.com/agossolla)
