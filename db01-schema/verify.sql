-- Integrity checks for schema.sql + seed.sql.
-- Run (do NOT use ON_ERROR_STOP: the first block is SUPPOSED to produce errors):
--   psql -U <user> -d <database> -f verify.sql
-- Every statement marked "EXPECT: ERROR" must fail. Destructive tests are rolled back.

\echo '=== 1. Assignee from another tenant (EXPECT: ERROR tasks_assignee_member_fk) ==='
UPDATE tasks SET assignee_id = (SELECT id FROM users WHERE email = 'jo@example.com')
WHERE team_id = (SELECT id FROM teams WHERE slug = 'acme') AND title = 'Write release notes';

\echo '=== 2. Tag from another tenant (EXPECT: ERROR task_tags_tag_fk) ==='
INSERT INTO task_tags (task_id, tag_id, team_id)
SELECT k.id, g.id, k.team_id
FROM tasks k, tags g
WHERE k.team_id = (SELECT id FROM teams WHERE slug = 'acme') AND k.title = 'Write release notes'
  AND g.team_id = (SELECT id FROM teams WHERE slug = 'globex') AND g.name = 'design';

\echo '=== 3. Duplicate tag name, different case (EXPECT: ERROR tags_team_name_uniq) ==='
INSERT INTO tags (team_id, name) SELECT id, 'BUG' FROM teams WHERE slug = 'acme';

\echo '=== 4. Priority out of range (EXPECT: ERROR tasks_priority_check) ==='
INSERT INTO tasks (team_id, title, priority)
SELECT id, 'Bad priority', 9 FROM teams WHERE slug = 'acme';

\echo '=== 5. Same user twice in one team (EXPECT: ERROR memberships_pkey) ==='
INSERT INTO memberships (team_id, user_id)
SELECT t.id, u.id FROM teams t, users u WHERE t.slug = 'acme' AND u.email = 'sam@example.com';

\echo '=== 6. ON DELETE SET NULL: delete Alex; task and comment must survive (rolled back) ==='
BEGIN;
DELETE FROM users WHERE email = 'alex@example.com';
SELECT title, assignee_id IS NULL AS assignee_cleared FROM tasks WHERE title = 'Fix login bug' AND team_id = (SELECT id FROM teams WHERE slug = 'acme');
SELECT body, author_id IS NULL AS author_cleared FROM comments;
ROLLBACK;

\echo '=== 7. ON DELETE CASCADE: delete Acme; its rows vanish, users remain (rolled back) ==='
BEGIN;
DELETE FROM teams WHERE slug = 'acme';
SELECT (SELECT count(*) FROM tasks)       AS tasks_left,
       (SELECT count(*) FROM comments)    AS comments_left,
       (SELECT count(*) FROM tags)        AS tags_left,
       (SELECT count(*) FROM task_tags)   AS task_tags_left,
       (SELECT count(*) FROM memberships) AS memberships_left,
       (SELECT count(*) FROM users)       AS users_left;
ROLLBACK;

\echo '=== 8. Indexes are used on realistic volume (rolled back) ==='
BEGIN;
INSERT INTO tasks (team_id, title, status, priority)
SELECT (SELECT id FROM teams WHERE slug = 'globex'),
       'Generated task ' || g,
       (ARRAY['todo','in_progress','done'])[1 + g % 3],
       1 + g % 5
FROM generate_series(1, 50000) AS g;
ANALYZE tasks;
EXPLAIN (COSTS OFF)
SELECT id FROM tasks
WHERE team_id = (SELECT id FROM teams WHERE slug = 'acme') AND status = 'in_progress';
EXPLAIN (COSTS OFF)
SELECT id FROM tasks
WHERE to_tsvector('english', title || ' ' || coalesce(description, '')) @@ to_tsquery('english', 'login');
ROLLBACK;
