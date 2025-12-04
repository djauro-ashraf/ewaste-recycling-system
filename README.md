📘 E-Waste Recycling & Collection Center Management System

CSE 4508 — RDBMS Project Proposal

Database: PostgreSQL
Technologies: SQL, PL/pgSQL


---

🚀 Project Overview

Electronic waste is increasing globally and requires proper collection, categorization, pricing, and recycling.
Manual systems often suffer from poor tracking, errors, and lack of data centralization.

This project builds a PostgreSQL-based RDBMS to digitize the entire workflow, including:

Pickup request management

Item categorization & hazardous details

Weight records & automated pricing

Staff & vehicle assignment

Recycling batch processing

Payment tracking

Complete audit logging


The goal is to deliver a structured, consistent, and reliable database system that supports eco-friendly e-waste handling.


---

🎯 Key Features

Core Functionalities

User pickup request system

Assigning staff and vehicles

Item categorization & hazard metadata (JSON)

Weight collection with price calculation

Recycling batch grouping

Facility processing management

Payments & receipts

Audit logs for all important actions


RDBMS Features

Fully normalized database (up to 3NF)

Strong use of constraints (FK, CHECK, UNIQUE)

Views for summarized reporting

Indexes for performance

Window functions & GROUPING SETS for analytics

Stored procedures & functions

BEFORE/AFTER triggers for validation & auditing



---

🧱 Database Schema (High-Level)

Main Entities:

User

PickupRequest

Item

Category

WeightRecord

PricingRule

RecyclingBatch

Facility

Staff

Vehicle

Payment

AuditLog


Example Primary Keys:

User(user_id)
PickupRequest(request_id, user_id)
Item(item_id, request_id, category_id)
Category(category_id)
WeightRecord(weight_id, item_id)
PricingRule(rule_id)
RecyclingBatch(batch_id, facility_id)
Facility(facility_id)
Staff(staff_id)
Vehicle(vehicle_id)
Payment(payment_id, request_id)
AuditLog(audit_id)


---

🔄 System Workflow

1. User submits a pickup request


2. Staff and vehicle assigned


3. Items collected & categorized


4. Weight recorded → price calculated


5. Items added to recycling batch


6. Facility processes batch


7. Payment recorded


8. Audit log updated




---

🧮 Planned SQL Components

Complex Queries

Pickup history with multi-table JOINs

Monthly revenue & weight analytics

Window functions for ranking & summaries

GROUPING SETS & ROLLUP reports

Most-recycled categories


Views

user_pickup_summary

batch_overview


Indexes

request_date

category_id



---

🧩 PL/pgSQL Components

Stored Procedures

schedule_pickup()

assign_vehicle_and_staff()

create_payment_record()


Functions

calculate_weight_price(item_id)

total_request_cost(request_id)

hazard_score(json)


Triggers

BEFORE INSERT → validate hazardous metadata

AFTER INSERT → write to audit log

Multi-row trigger → auto-assign recycling batch based on accumulated weight



---

👥 Team Members

Wirba Ashraf Djauro— 220041159

Katim Gaye — 220041167

Elhadj Ibrahima Camara — 220041166



---

📌 Conclusion

This RDBMS project provides a comprehensive, scalable, and well-designed solution for managing e-waste collection and recycling. It leverages powerful PostgreSQL features including normalization, triggers, functions, and analytics, making it aligned with CSE 4508 coursework requirements.
