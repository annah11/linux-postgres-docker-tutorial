-- DB-01: Multi-tenant task management schema (PostgreSQL 16)
-- Tenant = team. Every team-owned row carries team_id, and composite foreign
-- keys guarantee related rows belong to the SAME team.
--
-- Run:  psql -U <user> -d <database> -v ON_ERROR_STOP=1 -f schema.sql

BEGIN;

-- ---------------------------------------------------------------- users
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT NOT NULL UNIQUE
                CHECK (email = lower(email) AND position('@' IN email) > 1),
  display_name  TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- teams (tenants)
CREATE TABLE teams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- memberships (users <-> teams, many-to-many)
CREATE TABLE memberships (
  team_id    UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'member'
             CHECK (role IN ('owner', 'admin', 'member')),
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, user_id)
);
-- PK covers lookups by team; this covers "which teams is this user in?"
CREATE INDEX memberships_user_id_idx ON memberships (user_id);

-- ---------------------------------------------------------------- tasks (one-to-many from teams)
CREATE TABLE tasks (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id      UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  created_by   UUID REFERENCES users(id) ON DELETE SET NULL,
  assignee_id  UUID,
  title        TEXT NOT NULL CHECK (length(trim(title)) > 0),
  description  TEXT,
  status       TEXT NOT NULL DEFAULT 'todo'
               CHECK (status IN ('todo', 'in_progress', 'done')),
  priority     INT NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  due_date     TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Target for composite foreign keys from comments/task_tags (same-team guarantee)
  CONSTRAINT tasks_id_team_uniq UNIQUE (id, team_id),

  -- The assignee must be a MEMBER OF THIS TEAM. If the membership disappears,
  -- only assignee_id is cleared (team_id is NOT NULL and must stay). PG 15+.
  CONSTRAINT tasks_assignee_member_fk
    FOREIGN KEY (team_id, assignee_id)
    REFERENCES memberships (team_id, user_id)
    ON DELETE SET NULL (assignee_id)
);
-- Query filters: "team's tasks by status", "my open tasks", "due soon", full-text search
CREATE INDEX tasks_team_status_idx   ON tasks (team_id, status);
CREATE INDEX tasks_team_due_idx      ON tasks (team_id, due_date) WHERE due_date IS NOT NULL;
CREATE INDEX tasks_assignee_idx      ON tasks (assignee_id, status) WHERE assignee_id IS NOT NULL;
CREATE INDEX tasks_created_by_idx    ON tasks (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX tasks_search_gin_idx    ON tasks
  USING GIN (to_tsvector('english', title || ' ' || coalesce(description, '')));

-- ---------------------------------------------------------------- comments (one-to-many from tasks)
CREATE TABLE comments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id     UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  author_id   UUID REFERENCES users(id) ON DELETE SET NULL,
  body        TEXT NOT NULL CHECK (length(trim(body)) > 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX comments_task_created_idx ON comments (task_id, created_at);
CREATE INDEX comments_author_idx       ON comments (author_id) WHERE author_id IS NOT NULL;

-- ---------------------------------------------------------------- tags (per team) + task_tags (tasks <-> tags, many-to-many)
CREATE TABLE tags (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tags_id_team_uniq UNIQUE (id, team_id)
);
-- Tag names are unique per team, case-insensitively
CREATE UNIQUE INDEX tags_team_name_uniq ON tags (team_id, lower(name));

CREATE TABLE task_tags (
  task_id   UUID NOT NULL,
  tag_id    UUID NOT NULL,
  team_id   UUID NOT NULL,
  PRIMARY KEY (task_id, tag_id),
  -- Both sides must belong to the same team as this row
  CONSTRAINT task_tags_task_fk FOREIGN KEY (task_id, team_id)
    REFERENCES tasks (id, team_id) ON DELETE CASCADE,
  CONSTRAINT task_tags_tag_fk FOREIGN KEY (tag_id, team_id)
    REFERENCES tags (id, team_id) ON DELETE CASCADE
);
CREATE INDEX task_tags_tag_idx ON task_tags (tag_id);

COMMIT;
