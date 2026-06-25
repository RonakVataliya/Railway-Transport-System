# 🚆 Railway Transport Database System (RTDS)

A relational database design project modelling the core operations of an Indian railway network — from zones and divisions down to individual seat reservations, live train status, and maintenance tracking.

Built with **PostgreSQL**, documented with ERDs and relational schema diagrams, and complemented by a C++ console application for basic querying.

---

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Entity-Relationship Diagram](#-entity-relationship-diagram)
- [Relational Schema](#-relational-schema)
- [Database Schema Summary](#-database-schema-summary)
- [Analytical Queries](#-analytical-queries)
- [How to Run](#-how-to-run)
- [C++ Application](#-c-application)
- [Repository Structure](#-repository-structure)
- [Tech Stack](#-tech-stack)
- [License](#-license)

---

## 🗂 Project Overview

RTDS models a hierarchical railway system spanning:

- **Organizational hierarchy** — zones → divisions → departments → staff
- **Infrastructure** — stations, routes, route-station sequences, maintenance sheds
- **Rolling stock** — locomotives, trains, coaches, seats
- **Operations** — schedules, live train status, delay tracking
- **Passengers & ticketing** — user registration, booking, PNR lookup, seat assignment, refunds
- **Maintenance** — maintenance records linked to trains and staff

The schema was designed in two iterative stages (ERD Stage 1 → ERD Stage 2 → Final), with full normalization, referential integrity constraints, and meaningful CHECK constraints throughout.

---

## 🗺 Entity-Relationship Diagram

![Final ERD](diagrams/RTDS_FINAL_ERD.png)

> The ERD was drawn using [Dia Diagram Editor](http://dia-installer.de/). Source `.dia` files are in `diagrams/source/`.

---

## 🔗 Relational Schema

![Relational Schema](diagrams/RTDS_Relational_Schema.png)

---

## 🏗 Database Schema Summary

The schema lives in the `DB_Project` PostgreSQL schema and contains **22 tables**:

| Table | Description |
|---|---|
| `zone` | Top-level railway zones with headquarters |
| `division` | Divisions under each zone |
| `department` | Functional departments (operations, engineering, etc.) |
| `station` | Stations with city, category, junction flag, and division link |
| `route` | Named routes with total distance |
| `route_station` | Ordered sequence of stations per route with timing and platform info |
| `train_class` | Ticket classes (e.g. Sleeper, 3A, 2A) with fare multipliers |
| `train` | Trains linked to routes, locomotives, and classes |
| `locomotive` | Locomotives with status and assigned maintenance shed |
| `maintenance_shed` | Sheds under divisions with type and capacity |
| `maintenance_record` | Per-train maintenance events with type and status |
| `maintenance_staff` | Junction table linking staff to maintenance records |
| `schedule` | Train schedules with source/destination stations and timestamps |
| `live_train_status` | Real-time delay reports per station per schedule |
| `coach` | Coaches attached to trains with AC flag, type, seats, fare multiplier |
| `seat` | Individual seats per coach with berth type |
| `registered_user` | Passenger accounts with contact and authentication fields |
| `payment` | Payment transactions with method and timestamp |
| `tickets` | PNR-keyed bookings linking users, payments, and schedules |
| `passenger` | Individual passengers on a PNR with seat assignment |
| `ticket_refund` | Refund records with reason code and amount |
| `staff` | Employees spanning zones, divisions, departments, and stations |
| `ticket_checker` | Subtype of staff with fine log |
| `driver` | Subtype of staff with driving license and train assignment |
| `guard` | Subtype of staff with security clearance and train assignment |

**Key design decisions:**
- Composite primary keys for `schedule (train_id, starting_ts)`, `passenger (passenger_id, pnr)`, `seat (train_id, coach_code, seat_number)`, and `route_station (route_id, station_id)`
- `ON UPDATE CASCADE` and `ON DELETE RESTRICT/SET NULL/CASCADE` used appropriately throughout
- `CHECK` constraints on fares, distances, capacities, and salary fields
- Staff subtypes (`driver`, `guard`, `ticket_checker`) use shared-primary-key inheritance pattern

---

## 🔍 Analytical Queries

`schema/Query_Solutions.sql` contains **50 queries** covering:

| Category | Queries |
|---|---|
| Train search & scheduling | Trains between two stations in a time window, upcoming schedules per train |
| Booking & PNR | Full booking details by PNR, user booking history, upcoming trips by passenger name/DOB |
| Seat availability | Available seats and per-seat price per coach for a scheduled train |
| Transactions | Atomic booking (BEGIN/COMMIT), refund insertion |
| Revenue analytics | Per-day revenue, payment method breakdown, zone-wise revenue, top spenders |
| Passenger analytics | Daily/weekly passenger counts, 7-day moving average, group size per booking |
| Delay & live status | Average delay per route, top 5 most-delayed stations |
| Staff & HR | Staff count per department/division, salary statistics, transfer update, checker fine logs |
| Maintenance | Locomotives overdue for service, inactive locos by zone, shed inventory |
| Fraud detection | Passengers under multiple accounts, high-cancellation users, burst booking detection |
| Infrastructure | Junction stations by route count, stations in a city with zone/division, coach composition |

---

## ▶ How to Run

**Prerequisites:** PostgreSQL 13+

```sql
-- 1. Create the schema
\i schema/RTDS_DDL.sql

-- 2. Load sample data
\i schema/Insertion_Script.sql

-- 3. Run queries
\i schema/Query_Solutions.sql
```

Or connect via `psql`:

```bash
psql -U your_user -d your_database -f schema/RTDS_DDL.sql
psql -U your_user -d your_database -f schema/Insertion_Script.sql
```

> All objects are created under the `DB_Project` schema. Make sure your `search_path` is set accordingly, or prefix tables with `DB_Project.table_name`.

---

## 💻 C++ Application

`app/railway_app.cpp` is a console application that connects to the RTDS PostgreSQL database (via `libpq`) and provides basic interactive querying — train search, PNR lookup, and booking listing.

**Build:**

```bash
g++ -o railway_app app/railway_app.cpp -lpq
./railway_app
```

> Requires `libpq-dev` installed (`sudo apt install libpq-dev` on Debian/Ubuntu).

---

## 📁 Repository Structure

```
RTDS/
├── README.md
├── schema/
│   ├── RTDS_DDL.sql              ← Table definitions (22 tables)
│   ├── Insertion_Script.sql      ← Sample data
│   └── Query_Solutions.sql       ← 50 analytical queries
├── diagrams/
│   ├── RTDS_FINAL_ERD.png        ← Final ERD export
│   ├── RTDS_Relational_Schema.png
│   └── source/                   ← Dia source files
│       ├── ERD_Stage1.dia
│       ├── ERD_Stage2.dia
│       └── Relational_Schema_Final.dia
├── docs/
│   ├── ERD_Report.pdf
│   └── Relational_Schema_Report.pdf
├── app/
│   └── railway_app.cpp
└── LICENSE
```

---

## 🛠 Tech Stack

| Tool | Purpose |
|---|---|
| PostgreSQL 15 | Primary RDBMS |
| SQL (DDL + DML) | Schema definition, data insertion, analytical queries |
| Dia Diagram Editor | ERD and relational schema diagrams |
| C++ (`libpq`) | Console application |

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
