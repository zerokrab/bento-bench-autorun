#!/usr/bin/env bash
# Initialize PostgreSQL
#
# Creates a new cluster if one doesn't exist, sets up the database user
# and taskdb database, then starts postgres in the background.

set -euo pipefail

DB_INIT_FLAG="${VARS_DIR}/.db_initialized"

if [[ ! -f "${DB_INIT_FLAG}" ]]; then
    echo "Initializing PostgreSQL cluster..."

    # Drop default cluster if it exists
    pg_lsclusters 2>/dev/null | grep -q "16" && pg_dropcluster 16 main --stop 2>/dev/null || true

    # Create data directory
    mkdir -p "${PGDATA}"
    chown postgres:postgres "${PGDATA}"

    # Initialize cluster
    su postgres -c "/usr/lib/postgresql/16/bin/initdb -D ${PGDATA}"

    # Start postgres temporarily for user creation
    su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D ${PGDATA} -l ${PGDATA}/logfile start"

    # Wait for postgres to be ready
    until su postgres -c "psql -c '\\q'" 2>/dev/null; do
        sleep 1
    done

    # Create user and database
    su postgres -c "psql -c \"CREATE USER bento WITH PASSWORD 'bento';\""
    su postgres -c "psql -c \"CREATE DATABASE taskdb OWNER bento;\""
    su postgres -c "psql -c \"GRANT pg_read_all_settings TO bento;\""

    # Stop postgres
    su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D ${PGDATA} stop -m fast"

    # Allow connections from any address (needed for container networking)
    echo "host  all  all  0.0.0.0/0  md5" >> "${PGDATA}/pg_hba.conf"
    echo "host  all  all  ::/0       md5" >> "${PGDATA}/pg_hba.conf"

    touch "${DB_INIT_FLAG}"
    echo "PostgreSQL initialized."
else
    echo "PostgreSQL already initialized, skipping setup."
fi

# Configure listen_addresses
if ! grep -q "^listen_addresses" "${PGDATA}/postgresql.conf"; then
    echo "listen_addresses = '*'" >> "${PGDATA}/postgresql.conf"
fi

# Start postgres in the background
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D ${PGDATA} -l ${PGDATA}/logfile start"

# Wait for postgres to be ready
until su postgres -c "psql -c '\\q'" 2>/dev/null; do
    sleep 1
done
echo "PostgreSQL is running."