-- One-time setup in a new Snowflake account (run as ACCOUNTADMIN in a Snowsight worksheet).
-- Creates a small auto-suspending warehouse, the database and a least-privilege role for dbt.
use role accountadmin;

create warehouse if not exists TRANSFORMING
  warehouse_size = 'XSMALL' auto_suspend = 60 auto_resume = true initially_suspended = true;

create database if not exists MARKETING;

create role if not exists TRANSFORMER;
grant usage on warehouse TRANSFORMING to role TRANSFORMER;
grant usage, create schema on database MARKETING to role TRANSFORMER;
-- User names are case-sensitive: copy yours from SHOW USERS (column "name").
show users;
grant role TRANSFORMER to user "<your_user_name>";

-- Then register the public key (contents of rsa_key.pub without the BEGIN/END lines):
-- alter user <your_user> set rsa_public_key = 'MIIBIjANBgkqh...';
