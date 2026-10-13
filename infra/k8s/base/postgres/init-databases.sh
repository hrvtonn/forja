#!/bin/sh
# Executado pelo entrypoint oficial do Postgres apenas na primeira inicialização do volume.
# Cria um banco e um usuário dedicado para cada API (princípio do menor privilégio).
# Arquivo compartilhado entre o Docker Compose e o Kubernetes (fonte única).
set -e

: "${CONTRATOS_DB_PASSWORD:?variável CONTRATOS_DB_PASSWORD não definida}"
: "${FLASH_SALES_DB_PASSWORD:?variável FLASH_SALES_DB_PASSWORD não definida}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE USER contratos_app WITH PASSWORD '${CONTRATOS_DB_PASSWORD}';
CREATE DATABASE contracts_db OWNER contratos_app;
REVOKE ALL ON DATABASE contracts_db FROM PUBLIC;

CREATE USER flash_sales_app WITH PASSWORD '${FLASH_SALES_DB_PASSWORD}';
CREATE DATABASE flash_sales OWNER flash_sales_app;
REVOKE ALL ON DATABASE flash_sales FROM PUBLIC;
EOSQL
