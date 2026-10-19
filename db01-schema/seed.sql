-- Sample data: two tenants (Acme, Globex) and one user (Sam) who belongs to both.
-- Run after schema.sql:  psql -U <user> -d <database> -v ON_ERROR_STOP=1 -f seed.sql

BEGIN;

INSERT INTO teams (name, slug) VALUES ('Acme', 'acme'), ('Globex', 'globex');

INSERT INTO users (email, display_name) VALUES
  ('sam@example.com',  'Sam'),
  ('alex@example.com', 'Alex'),
  ('jo@example.com',   'Jo');

INSERT INTO memberships (team_id, user_id, role)
SELECT t.id, u.id, m.role
FROM (VALUES
  ('acme',   'sam@example.com',  'owner'),
  ('acme',   'alex@example.com', 'member'),
  ('globex', 'sam@example.com',  'member'),
  ('globex', 'jo@example.com',   'owner')
) AS m(team_slug, email, role)
JOIN teams t ON t.slug = m.team_slug
JOIN users u ON u.email = m.email;

INSERT INTO tags (team_id, name)
SELECT t.id, g.name
FROM (VALUES ('acme','bug'), ('acme','urgent'), ('globex','bug'), ('globex','design')) AS g(team_slug, name)
JOIN teams t ON t.slug = g.team_slug;

INSERT INTO tasks (team_id, created_by, assignee_id, title, description, status, priority, due_date)
SELECT t.id, c.id, a.id, x.title, x.descr, x.status, x.priority, now() + x.due
FROM (VALUES
  ('acme',   'sam@example.com', 'alex@example.com', 'Fix login bug',      'Users cannot log in with SSO', 'in_progress', 1, interval '2 days'),
  ('acme',   'sam@example.com', NULL,               'Write release notes', 'Summarise the sprint',         'todo',        3, interval '7 days'),
  ('globex', 'jo@example.com',  'sam@example.com',  'Fix login bug',      'Same title, different tenant', 'todo',        2, interval '3 days')
) AS x(team_slug, creator, assignee, title, descr, status, priority, due)
JOIN teams t ON t.slug = x.team_slug
JOIN users c ON c.email = x.creator
LEFT JOIN users a ON a.email = x.assignee;

INSERT INTO task_tags (task_id, tag_id, team_id)
SELECT k.id, g.id, k.team_id
FROM tasks k
JOIN teams t ON t.id = k.team_id
JOIN tags g  ON g.team_id = k.team_id
WHERE (t.slug = 'acme'   AND k.title = 'Fix login bug' AND g.name IN ('bug', 'urgent'))
   OR (t.slug = 'globex' AND k.title = 'Fix login bug' AND g.name = 'bug');

INSERT INTO comments (task_id, author_id, body)
SELECT k.id, u.id, 'Reproduced on staging.'
FROM tasks k
JOIN teams t ON t.id = k.team_id AND t.slug = 'acme'
JOIN users u ON u.email = 'alex@example.com'
WHERE k.title = 'Fix login bug';

COMMIT;
