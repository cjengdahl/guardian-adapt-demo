# AI Code Assistant Project Instructions — Secure Flask Blog Code Generation

## High-level revision plan
- Enforce “no debug in production” rule and provide safe debug/config patterns.
- Prohibit unsafe SQL generation; require parameterized queries or an ORM.
- Treat all HTTP inputs as tainted: require validation, whitelisting, and type checks.
- Require Jinja2 autoescape and forbid use of `|safe` on untrusted content.
- Require secrets/config from environment variables and forbid hard-coded secrets.
- Provide example code snippets for safe patterns (debug config, validation, DB access).

## Project Overview (concise)
This is a simple Flask blog (Python 3). Templates use Jinja2; posts are in-memory by default. The AI Code Assistant must follow the security policies below when producing or modifying code.

## Mandatory Security Policies for Code Generation
All generated code MUST follow these rules. If a rule cannot be satisfied in a requested change, the assistant must refuse or propose a safe alternative.

1. No debug mode in production
   - Never generate code that runs the app with `debug=True` unconditionally.
   - Use an environment variable or Flask config flag to enable debug only in development.
   - Do not commit code that sets `app.run(debug=True)` or equivalent. If asked to include debug-mode startup examples, wrap them in an explicit development-only guard.

2. No raw SQL concatenation with user input (prevent SQL injection)
   - Treat all request-derived values (query params, form data, headers, cookies) as tainted.
   - Never concatenate or format SQL strings with tainted values.
   - Use one of the following safe approaches:
     - An ORM (recommended): SQLAlchemy models and query APIs.
     - Parameterized queries using the DB-API parameter style for the chosen driver (e.g., `?`, `%s`, or named parameters).
     - SQLAlchemy text queries with bind parameters (`text(...), {"id": id}`).
   - When dynamic identifiers (table/column names) are required, map user input to an explicit allowlist of internal identifiers — do not interpolate identifiers directly.

3. Input validation and sanitization
   - All parameters used for control flow, indexing, or queries must be validated:
     - Type checks (int, str, bool), length limits, regex or whitelist checks.
     - Return 400/422 for invalid input; do not proceed with potentially dangerous values.
   - Prefer schema-based validators or form libraries (WTForms, Marshmallow) for endpoints that accept structured input.
   - Example minimal helper: explicitly convert ints and abort on errors.

4. Template safety
   - Rely on Jinja2 autoescape. Do not disable autoescape globally.
   - Forbid using `|safe` or Markup on user-supplied content unless the content is explicitly sanitized and its safety documented.
   - If generating HTML fragments from user input, apply a robust sanitizer library (e.g., Bleach) and document why it is safe.

5. Secrets and configuration
   - Never generate code that hard-codes secrets (API keys, DB passwords, tokens) in the repository.
   - Read secrets from environment variables or secure configuration stores.
   - If suggesting `.env` usage, also instruct not to commit `.env` to source control and to add it to `.gitignore`.

6. Forbidden constructs
   - Do not generate `eval`, `exec`, `os.system`, `subprocess` with untrusted input.
   - Avoid `pickle.load` on untrusted data and similar unsafe deserialization.

7. Developer guidance
   - Suggest adding security-focused unit tests and dependency scans in CI.
   - Recommend running static analyzers and dependency vulnerability scanners during PR checks.

## Safe patterns and code examples

### Safe debug/config pattern
```python
# app.py (startup snippet)
import os
from flask import Flask

app = Flask(__name__)
# Load config from environment and defaults
app.config.from_mapping(
    SECRET_KEY=os.getenv("SECRET_KEY", "replace-me-for-dev"),
    DEBUG=os.getenv("FLASK_DEBUG", "0") == "1",
    ENV=os.getenv("FLASK_ENV", "production"),
)

if __name__ == "__main__":
    # Only enable the Werkzeug debugger in explicit development environments
    debug_mode = app.config["DEBUG"]
    if debug_mode and app.config["ENV"] != "development":
        raise RuntimeError("Debug mode allowed only when FLASK_ENV=development")
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=debug_mode)
```
- Do not leave `DEBUG=True` in committed code. Use env vars to control debugging.

### Safe DB access — ORM (recommended)
```python
# models.py (SQLAlchemy example)
from sqlalchemy import Column, Integer, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

Base = declarative_base()

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True)
    title = Column(String(200))
    body = Column(String)

# create engine with URL coming from env var
engine = create_engine(os.getenv("DATABASE_URL", "sqlite:///:memory:"), future=True)
SessionLocal = sessionmaker(bind=engine)
```
```python
# usage in route
def get_post(session, post_id):
    # post_id must have been validated as int before calling
    return session.query(Post).filter_by(id=post_id).first()
```

### Safe DB access — parameterized raw SQL
```python
# sqlite3 example (DB-API parameter style)
import sqlite3
conn = sqlite3.connect("app.db")
cur = conn.cursor()

# BAD (vulnerable):
# query = "SELECT * FROM posts WHERE id = %s" % post_id

# GOOD:
cur.execute("SELECT * FROM posts WHERE id = ?", (post_id,))
row = cur.fetchone()
```

```python
# psycopg2 example (Postgres param style)
cur.execute("SELECT * FROM posts WHERE id = %s", (post_id,))
```

```python
# SQLAlchemy text() with parameters
from sqlalchemy import text
result = session.execute(text("SELECT * FROM posts WHERE id = :id"), {"id": post_id})
```

### Rejecting dynamic SQL identifiers unless whitelisted
```python
ALLOWED_COLUMNS = {"title", "created_at"}

col = request.args.get("sort_by", "created_at")
if col not in ALLOWED_COLUMNS:
    abort(400)

# safe to use because col is from allowlist
query = f"SELECT id, title FROM posts ORDER BY {col}"
```

### Input validation examples
```python
from flask import request, abort

def get_int_param(name):
    val = request.args.get(name)
    if val is None:
        abort(400)
    try:
        return int(val)
    except ValueError:
        abort(400)

# usage
post_id = get_int_param("id")
```

For more complex payloads, prefer WTForms/Marshmallow:
```python
# WTForms (example)
from wtforms import Form, StringField
from wtforms.validators import DataRequired, Length

class PostForm(Form):
    title = StringField("title", [DataRequired(), Length(max=200)])
    body = StringField("body", [DataRequired(), Length(max=2000)])
```

### Template safety reminder
- Use `render_template("post.html", post=post)` with Jinja2 autoescaping enabled.
- Do not mark user content as safe:
  - BAD: {{ post.body|safe }}  (only allowed if content was sanitized and justification provided)
  - GOOD: {{ post.body }} (Jinja2 escapes by default)

## Guidance for the AI Code Assistant tool
When producing code or changes for this repository, the assistant must:
- Explicitly note when it requires a DB and recommend using SQLAlchemy; otherwise avoid adding DB access.
- Add input validation for every endpoint that accepts client input; return appropriate HTTP error codes for invalid input.
- Use environment variables for all secrets, keys, and for debug/ENV flags. Include guidance to add `.env` to `.gitignore`.
- Always prefer safe patterns (ORM, parameterized queries) over raw SQL. If a raw SQL snippet is requested, include a clear "bad vs good" example as in this file.
- Never generate `app.run(debug=True)` in the main branch; only produce development-only examples guarded by environment checks.
- Flag when a requested change would require relaxing a rule (e.g., dynamic SQL identifiers) and propose a safer alternative (allowlist mapping).
- Include brief in-code comments explaining security checks (e.g., "validate input here to prevent SQL injection").

## Minimal developer workflow (safe defaults)
- Install dependencies: pip install -r requirements.txt
- Set environment variables for development:
  - FLASK_ENV=development
  - FLASK_DEBUG=1
  - SECRET_KEY for local use only (do not commit)
- Run locally with environment-controlled debug:
  - python app.py
- Add CI checks:
  - Static analysis (flake8/pylint)
  - Dependency vulnerability scanning
  - Unit tests covering input validation and template rendering

## Files and patterns to avoid committing
- Do not commit .env or other files containing secrets.
- Do not commit code that sets DEBUG=True unconditionally.
- Do not commit raw SQL strings built from user input or unvalidated sources.

## Summary checklist for generated changes (enforced)
When the assistant produces a PR or patch, it must ensure:
- No unconditional debug mode in committed code.
- No raw SQL concatenation with user input exists.
- All user inputs are validated and treated as tainted.
- Jinja2 autoescape is kept and `|safe` is not used on untrusted content.
- Secrets come from env vars and `.env` is not committed.

Follow these rules strictly. If a requested code change would violate any rule, refuse or provide a secure alternative.