# PostgreSQL + Hasura + pgAdmin with Docker Compose

A local development stack that starts with one command: a PostgreSQL 16 database, a Hasura GraphQL API on top of it, and pgAdmin for inspecting the data. Data lives in named volumes, so it survives restarts.

Built as the FND-02 task of the Minab I.T Solutions internship study plan.

## Architecture

```
Browser / app ──GraphQL──▶ Hasura (host 8081 → container 8080)
                                │ SQL over the internal network
                                ▼
pgAdmin (host 5050) ───────▶ db (PostgreSQL 16, internal port 5432 only)
                                │
                          volume: pgdata
```

| Service | Image | Host port | Notes |
|---|---|---|---|
| `db` | `postgres:16` | none (internal only) | Healthcheck: `pg_isready`. Data in volume `pgdata`. |
| `hasura` | `hasura/graphql-engine:v2.48.12` | 8081 | Waits for `db` to be healthy. Healthcheck: `/healthz`. |
| `pgadmin` | `dpage/pgadmin4:latest` | 5050 | Waits for `db`. Settings in volume `pgadmin-data`. |

Why `db` publishes no port: Hasura and pgAdmin reach it as `db:5432` on the Compose network, so nothing on the host needs direct access. This also avoids clashing with other databases on the machine.

## Prerequisites

- Docker with the Compose plugin (`docker compose version`)
- Free host ports 8081 and 5050 (check with `ss -ltn | grep -E ':8081 |:5050 '`)

## Quick start

```bash
git clone <this-repo-url>
cd <repo-folder>

cp .env.example .env
nano .env                      # replace every placeholder value

docker compose config          # validates the file and shows resolved values
docker compose up -d
docker compose ps              # wait until db and hasura show (healthy)
```

Generate strong secrets with `openssl rand -hex 16`. Use only letters, numbers and `_` in `POSTGRES_PASSWORD`, because it is embedded in a connection URL.

## First-time setup in the consoles

**Hasura** (`http://localhost:8081`, log in with `HASURA_ADMIN_SECRET`)

1. Data → Connect Existing Database.
2. Driver: Postgres. Connect via: Environment Variable. Name: `PG_DATABASE_URL`.
3. Open the new database, find your tables, and click Track.

**pgAdmin** (`http://localhost:5050`, log in with `PGADMIN_EMAIL` / `PGADMIN_PASSWORD`)

1. Register → Server.
2. Host `db` (not `localhost`), port `5432`, database `appdb`, user and password from `.env`.

## Everyday commands

| Task | Command |
|---|---|
| Start in background | `docker compose up -d` |
| Status and health | `docker compose ps` |
| Follow all logs | `docker compose logs -f` |
| Follow one service | `docker compose logs -f hasura` |
| Last 20 lines | `docker compose logs --tail 20 db` |
| Open a SQL shell | `docker compose exec db psql -U <POSTGRES_USER> -d <POSTGRES_DB>` |
| Stop, keep data | `docker compose down` |
| Stop and DELETE data | `docker compose down -v` |

## Verifying persistence

1. Create a table and insert rows (pgAdmin Query Tool or `psql`).
2. `docker compose down`, then `docker compose up -d`.
3. Query the table again. The rows are still there because they live in the `pgdata` volume, not in the container.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `Cannot connect to the Docker daemon` | The Docker engine is not running. Start Docker Desktop or the daemon, then rerun. |
| `port is already allocated` | Another process holds the host port. Find it with `ss -ltn` or `docker ps`, then change the left side of the port mapping in `docker-compose.yml`. |
| Hasura `connection refused` to the database | The URL must use the service name `db`, not `localhost`. |
| Hasura shows 0 databases | The data source has not been added yet. See "First-time setup". |
| Changed `POSTGRES_PASSWORD` but login still uses the old one | Postgres only applies it on first start. Recreate with `docker compose down -v` (this deletes data). |
| `unhealthy` right after start | Give it `start_period`. Check `docker compose logs <service>`. |

## Security notes

- `.env` holds secrets and is listed in `.gitignore`. Never commit it. Commit `.env.example` (placeholders only) instead.
- The Hasura admin secret grants full access to all data. Never put it in frontend code.
- Hasura dev mode and the console are enabled for local work. Disable them (`HASURA_GRAPHQL_ENABLE_CONSOLE`, `HASURA_GRAPHQL_DEV_MODE`) and define role-based permissions before any deployment.
- Pin image versions (including `pgadmin4`) once you have tested them.

## Key concepts practised

Images vs containers, port mapping (`host:container`), named volumes, environment variables and `.env`, Compose networking by service name, healthchecks with `depends_on: condition: service_healthy`, restart policies, and log rotation.
