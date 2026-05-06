# Secure AI Code Assistant Instructions — Flask Blog Project

- Audit and remove any code that enables Flask debug mode in generated files.
- Prohibit generation of raw, concatenated SQL using unsanitized user input; prefer ORM or parameterized queries.
- Treat all HTTP inputs as tainted: require validation/sanitization and explicit safe-binding before use.
- Enforce Jinja2 autoescaping; forbid generating code that disables it or marks user data as safe.
- Add CI/pre-commit rules and reviewer checks to detect debug flags, raw SQL concatenation, use of eval/exec/os.system with user data, and hardcoded secrets.

## Purpose and Scope
These instructions guide the AI Code Assistant when producing or modifying code for this Flask blog repository. They are narrowly focused on preventing two categories of security issues detected in prior scans:
- Debug Mode Enabled (RunWithDebugTrue)
- SQL Injection (Sqli)

All generated code MUST follow these rules. The assistant should output code snippets, configuration, and tests consistent with these constraints.

## General Security Policies for Generated Code
- NEVER insert `app.run(debug=True)` or otherwise enable Flask debug mode in source files. Generated examples may show how to run locally with CLI environment variables but must not programmatically switch debug on.
- NEVER generate raw SQL by concatenating strings, formatting, or f-strings with user-supplied values.
- Prefer high-level database APIs (ORMs) and parameterized queries when interacting with SQL.
- All request-derived data (request.args, request.form, request.values, request.cookies, request.headers, path params) is considered untrusted (tainted). Code must validate and sanitize before use.
- Prohibit use of eval/exec/compile/execfile/os.system/subprocess.run or similar with untrusted input. If these must appear (very rarely), they require a security review and strong justification; prefer safe alternatives.
- Do not place secrets or credentials (API keys, DB passwords) in source code. Use environment variables and configuration management.

## Flask Run / Debug Configuration (What to generate)
- Do not hardcode debug mode. Generated repository code should either:
  - Omit `debug` parameter entirely when calling app.run(), or
  - Explicitly set `debug=False` in any example main entrypoint.
- Recommend using the Flask CLI for development and a WSGI server for production.

Allowed examples to emit:

```python
# app.py (example main guard)
import os
from myapp import create_app

app = create_app()

if __name__ == "__main__":
    # For local, development testing use the flask CLI:
    #   $ export FLASK_APP=app.py
    #   $ export FLASK_DEBUG=1     # optional for local dev only
    #   $ flask run
    #
    # Do not enable debug programmatically in source.
    app.run(host="127.0.0.1", port=5000, debug=False)
```

Recommended production run (do not generate as default for user apps):

- Use a WSGI server such as Gunicorn:
  - `gunicorn -w 4 app:app`

Generator guidance:
- If producing setup or README instructions, show how to use the Flask CLI for dev and Gunicorn for prod.
- If producing container examples, ensure environment variables control debug (and document that FLASK_DEBUG must not be used in production).

## Data Access and SQL Handling (Preventing SQL Injection)
- Default recommendation: use an ORM such as SQLAlchemy for persistence. If the assistant generates DB code, prefer ORM patterns.
- If any raw SQL is required, ALWAYS use parameterized queries prepared by the DB-API driver (placeholders), never string interpolation.

Example: SQLAlchemy (preferred)

```python
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class Post(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    content = db.Column(db.Text, nullable=False)

# Safe insert/create
new_post = Post(title=safe_title, content=safe_content)
db.session.add(new_post)
db.session.commit()
```

Example: sqlite3 with parameterized queries (if avoiding ORM)

```python
import sqlite3
from werkzeug.exceptions import BadRequest

def get_post_by_id(post_id):
    try:
        post_id = int(post_id)
    except (TypeError, ValueError):
        raise BadRequest("Invalid post id")

    conn = sqlite3.connect("data.db")
    cur = conn.cursor()
    # Safe: parameter binding via placeholders
    cur.execute("SELECT id, title, content FROM posts WHERE id = ?", (post_id,))
    row = cur.fetchone()
    conn.close()
    return row
```

Forbidden patterns (must not be generated):

```python
# DO NOT generate code like this:
post_id = request.args.get("id")
query = f"SELECT * FROM posts WHERE id = {post_id}"   # unsafe
cursor.execute(query)                                 # unsafe
```

Generator guidance:
- If producing a snippet that reads an identifier from the URL or query, explicitly coerce/validate types (e.g., int) and check ranges or allowed values.
- For any SQL query that includes user-controlled values, use bound parameters (`?`, `%s`, or named placeholders depending on driver) and pass values as parameters/tuples.

## Input Validation and Taint Handling
- Treat the following as untrusted: request.args, request.form, request.values, request.get_json(), request.cookies, headers, and any path parameters.
- For each route that uses input, produced code MUST:
  - Validate type and format. Example: parse ints with try/except; validate strings against a whitelist or regex when appropriate.
  - Enforce length limits (e.g., title <= 200 characters).
  - Normalize and canonicalize inputs where applicable.
  - Reject or sanitize unexpected characters (avoid HTML in non-HTML fields, etc.).

Example safe pattern for ID:

```python
from flask import request, abort

def get_post_route():
    post_id = request.view_args.get("post_id") or request.args.get("id")
    try:
        post_id = int(post_id)
    except (TypeError, ValueError):
        abort(400, "Invalid post id")
    # use post_id only after validation
```

File uploads:
- Use werkzeug.utils.secure_filename and validate MIME types and size limits.

## Templating and XSS Protections
- Rely on Jinja2 autoescaping. Do not generate templates that disable autoescape or use Markup/|safe with user-controlled data.
- When generating template code, display user content with default escaping:

```jinja
<!-- templates/post.html -->
<h1>{{ post.title }}</h1>
<p>{{ post.content }}</p>   {# Jinja2 autoescapes by default #}
```

- If generating cases that must render HTML provided by trusted sources, require explicit review and clear comments explaining why it is trusted.

## Prohibited or Restricted Code Patterns
- Do not generate:
  - app.run(debug=True) or any pattern that programmatically enables debug in production code.
  - SQL via f-strings, %-formatting, string concatenation with untrusted input.
  - eval(), exec(), compile(), os.system(), subprocess.* invoked with user input.
  - Hard-coded secrets, e.g., "SECRET_KEY = 'abc123'".
  - Disabling Jinja2 autoescape or marking user content as safe without validation.

## Configuration and Secrets Management
- Guidance for generated configuration:
  - Use environment variables for secrets and configuration options.
  - Example: `SECRET_KEY = os.environ.get("SECRET_KEY")` and fail fast if required secrets are missing.
- Provide examples for .env usage in documentation only; never commit .env with secrets.

## CI / Pre-commit / Linting Rules to Generate or Recommend
- When producing repository config or CI templates, include checks that flag the following:
  - Any occurrence of "debug=True" or "FLASK_DEBUG=1" in committed source files.
  - Use of `eval`, `exec`, `os.system`, `subprocess`, or `popen` with non-literal arguments.
  - Raw SQL concatenation patterns: f-strings or % formatting used in a string that includes SQL keywords (`SELECT`, `INSERT`, `UPDATE`, `DELETE`).
- Example .pre-commit hook suggestions (to be emitted as part of a repo template):

```yaml
repos:
  - repo: local
    hooks:
      - id: detect-debug-true
        name: Detect debug=True
        entry: bash -c "grep -R --line-number \"debug=True\" || true"
        language: system
      - id: detect-raw-sql
        name: Detect likely raw SQL concatenation
        entry: bash -c "grep -R --line-number -E \"SELECT .*\\{|\\$\\{|f\\\".*SELECT|%\\(.*\\)s.*SELECT\" || true"
        language: system
```

- Recommend running Bandit (security linter) in CI and failing builds on high-confidence issues.

## PR Reviewer Checklist (for AI-generated changes)
When an AI-generated PR is submitted, reviewers should verify:
- No files enable debug mode in source (search "debug=True" and "FLASK_DEBUG").
- No raw SQL concatenation with user inputs exists; any SQL is parameterized or uses ORM.
- All request-derived inputs are validated or sanitized before use.
- No eval/exec/os.system/subprocess calls operate on user input.
- No secrets committed in code or configuration files.
- Unit tests cover input validation and common failure modes.

## Examples of Acceptable Generated Patterns
- Using SQLAlchemy ORM for posts (preferred).
- Using sqlite3 or psycopg2 with parameterized queries and typed validation.
- Using Flask CLI for local dev and Gunicorn for production.

## Minimal Example: Secure CRUD (Illustrative)
This short example is an allowed pattern the assistant may generate; it demonstrates validation, no debug mode, and parameterized DB usage (ORM preferred).

```python
# create_app.py
import os
from flask import Flask, request, abort, render_template
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def create_app():
    app = Flask(__name__)
    app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///data.db')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', '')
    db.init_app(app)

    class Post(db.Model):
        id = db.Column(db.Integer, primary_key=True)
        title = db.Column(db.String(200), nullable=False)
        content = db.Column(db.Text, nullable=False)

    @app.route("/posts/<int:post_id>")
    def show_post(post_id):
        post = Post.query.get_or_404(post_id)
        return render_template("post.html", post=post)

    return app
```

## Documentation and Comments in Generated Code
- When the assistant generates code that could be sensitive, include concise comments explaining why a pattern is safe (e.g., "parameterized query avoids SQL injection").
- Where safety depends on environment configuration, document the exact environment variables that must be set and recommended values (do not include secrets).

## Enforcement and Escalation
- Any generated code that violates these rules must be rejected for security remediation before merging.
- For unclear cases (e.g., an uncommon need for dynamic SQL), require a human security review and justification.

---

These instructions are authoritative for the AI Code Assistant when authoring or modifying code in this repository. They are intentionally concise and prescriptive to prevent the recurrence of the debug-mode and SQL injection vulnerabilities reported by automated scanning.