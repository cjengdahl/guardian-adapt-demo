# AI Code Assistant Security Instructions — Flask Blog Project

- Review and remove any use of `app.run(debug=True)` and never enable interactive debugger in generated code.
- Prohibit generation of raw SQL built with string interpolation from any HTTP or external input; require parameterized queries or an ORM.
- Require explicit input validation/sanitization and Jinja2 safe rendering rules for all user-supplied data.
- Provide secure starter templates (app factory, run guard, env-driven config) and safe SQL examples (parameterized sqlite3 and SQLAlchemy).
- Add CI/static-scan guidance to detect `debug=True`, use of `eval`/`exec`, and unsafe SQL patterns before merge.

## Purpose & Scope

These instructions guide the AI Code Assistant when generating or modifying code for this Flask blog repository. They are scoped to prevent the following vulnerabilities found by automated scans:
- RunWithDebugTrue (Debug Mode Enabled)
- SQL Injection (unsafe construction of SQL from user input)

Follow these rules strictly; failure to comply will produce insecure code.

## High-level Policies (must be enforced by the generator)

- Never generate code that runs Flask with `debug=True` or enables the interactive debugger in any environment other than a tightly controlled local developer session. Prefer `debug=False` by default and require an explicit environment variable to enable debug only for local development.
- Treat all incoming HTTP parameters and any external input as tainted. Do not use them directly in SQL, shell commands, `eval`/`exec`, or other code-executing contexts.
- Do not emit raw SQL concatenation or formatted strings that include user data. Use parameterized queries or an ORM (e.g., SQLAlchemy) with bound parameters.
- Avoid committing secrets; read credentials and debug flags from environment variables only.
- Do not add `os.system`, `subprocess.*`, `eval`, or `exec` calls using any user-supplied data.
- Ensure templates rely on Jinja2 autoescape; never mark user-provided content as safe without rigorous, documented sanitization.

## Configuration — app startup & debug handling

Use an app factory and a secure runtime pattern. Generated code must follow this example pattern.

```python
# app.py (entrypoint)
import os
from myapp import create_app

def bool_env(name, default=False):
    val = os.getenv(name)
    if val is None:
        return default
    return val.lower() in ("1", "true", "yes")

# Only enable debug when explicitly set in the environment for local dev.
# In CI/production the environment must not set FLASK_DEBUG=1 or FLASK_ENV=development.
if __name__ == "__main__":
    app = create_app()
    debug = bool_env("FLASK_DEBUG", False)
    # Prefer a production WSGI server in production. Only use app.run for local dev.
    app.run(host="127.0.0.1", port=5000, debug=debug)
```

Generator rule: never output `app.run(debug=True)` as a literal default. If examples include debug instructions, include clear comments and read debug from env as above.

## Application factory pattern (required)

Always generate an application factory that accepts a config object or reads safe environment values.

```python
# myapp/__init__.py
from flask import Flask
import os

def create_app(config=None):
    app = Flask(__name__, static_folder="static", template_folder="templates")
    # Load config from provided dict or environment variables only
    if config:
        app.config.update(config)
    else:
        app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "dev-placeholder")  # require override in prod
        app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv("DATABASE_URL", "sqlite:///:memory:")
        app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    # register blueprints, init db, etc.
    return app
```

Guideline: The assistant should include a note in generated code/documentation that SECRET_KEY must be set via env in production.

## Safe database usage — mandatory patterns

- If generating raw SQL code, always use parameterized placeholders (DB-API `?` or `%s` depending on driver) and pass parameters as a separate tuple/list.
- Prefer SQLAlchemy (or another mature ORM). Generated examples should default to SQLAlchemy when any persistence is required.
- Never construct SQL by concatenating user input.

Examples:

Parameterized sqlite3 example (acceptable):

```python
# safe_sqlite.py
import sqlite3

def insert_post(conn, title, body):
    # Validate inputs (see Input Validation section) then use parameterized query
    with conn:
        conn.execute(
            "INSERT INTO posts (title, body) VALUES (?, ?)",
            (title, body)
        )
```

Unsafe pattern (must not be generated):

```python
# DO NOT GENERATE:
query = f"INSERT INTO posts (title, body) VALUES ('{title}', '{body}')"  # vulnerable
conn.execute(query)
```

SQLAlchemy recommended example:

```python
# models.py
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class Post(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(255), nullable=False)
    body = db.Column(db.Text, nullable=False)
```

Usage (safe):

```python
# views.py
from flask import request, current_app
from .models import db, Post

def create_post():
    title = request.form.get("title", "")
    body = request.form.get("body", "")
    # Validate inputs (see Input Validation)
    post = Post(title=title, body=body)
    db.session.add(post)
    db.session.commit()
```

Generator rule: prefer SQLAlchemy examples and templates; if raw SQL is used, include an explicit parameterized-query example and a comment explaining why it’s safe.

## Input validation and sanitization (required)

- Always validate and constrain data types, lengths, and formats for incoming fields before using them in any logic, persistence, or rendering.
- Use server-side validation in addition to any client-side checks.
- Recommended minimum checks:
  - Trim and enforce max lengths (e.g., title <= 255 chars).
  - Reject inputs with unexpected control characters or binary data.
  - For identifiers (IDs) used in routing, coerce and validate types (e.g., convert to int and handle ValueError).
- Use libraries where appropriate (WTForms, Marshmallow, pydantic) and include example validations in generated code.

Example minimal validator:

```python
def validate_post_input(title, body):
    if not title or len(title) > 255:
        raise ValueError("Invalid title")
    if not body or len(body) > 5000:
        raise ValueError("Invalid body")
    return True
```

Generator rule: Add input validation in every generated endpoint that consumes user input and document the validation logic.

## Template rendering and XSS protection

- Rely on Jinja2 autoescaping for HTML templates. Do not use the |safe filter on user-provided content unless content has been sanitized and the sanitization step is explicitly shown and explained.
- When generating templates, do not disable autoescape or mark user data safe by default.

Generator rule: When producing templates, always use standard variable interpolation (e.g., {{ post.title }}) and include comments referencing that autoescape is enabled.

## Prohibitions and dangerous constructs

Do not generate any of the following in code that handles user input:
- eval(), exec(), compile() with user data
- os.system(), subprocess.run(), subprocess.Popen() with user data embedded in strings
- direct shell invocations that include user data
- building file paths with user data without strict validation and canonicalization

If a use-case truly requires these operations, the generated code must:
- Include an explicit security rationale and mitigation plan
- Fully validate and sanitize input
- Use secure APIs (e.g., subprocess with list arguments and no shell=True)

## Secrets and environment handling

- Never inline secrets, API keys, or credentials in generated source code. Use environment variables and document required variables:
  - SECRET_KEY
  - DATABASE_URL
  - FLASK_DEBUG (development only)
- Provide a sample `.env.example` and recommend python-dotenv for local development, but remind users to never commit a `.env` with secrets.

Example .env.example:

```
SECRET_KEY=replace-me-in-prod
DATABASE_URL=sqlite:///data.db
FLASK_DEBUG=0
```

Generator rule: When producing examples, use placeholders and a clear comment to set secure values in production.

## Static analysis and CI checks (recommended to include in generated repo)

Include or recommend CI hooks that catch these issues before merging:
- Bandit: detect use of debug, eval, subprocess with shell=True, hardcoded secrets
- Flake8/ruff: code style and simple errors
- Custom grep/lint rule: fail if `app.run(` includes `debug=True` literal
- SQL linting or a simple pattern matcher to detect string formatting/concatenation into SQL statements (e.g., regex searching for `f".*INSERT.*"` combined with HTTP param usage)

Example GitHub Actions snippet to run bandit and flake8:

```yaml
# .github/workflows/ci.yml (recommended)
name: CI
on: [push, pull_request]
jobs:
  lint-and-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.10"
      - name: Install deps
        run: |
          pip install bandit flake8
          pip install -r requirements.txt || true
      - name: Run bandit
        run: bandit -r .
      - name: Run flake8
        run: flake8
```

Generator rule: When producing CI configs, include a bandit step and at minimum a grep check that fails the build when `debug=True` appears in source.

## Examples to avoid (explicit)

Do not generate any code like:

```python
# Dangerous: DO NOT GENERATE
query = f"SELECT * FROM posts WHERE id = {request.args['id']}"
db.execute(query)
```

or

```python
# Dangerous: DO NOT GENERATE
app.run(host="0.0.0.0", port=5000, debug=True)
```

If the assistant must show an unsafe example for explanation, it must be clearly labeled as insecure and accompanied by a secure alternative.

## Documentation and developer guidance (must be generated with code)

Every generated change must include README notes that:
- Explain how to run locally with debug disabled by default and how to enable debug only via env for local dev.
- List required environment variables and warn against committing secrets.
- Document that code uses parameterized queries or SQLAlchemy and why (to prevent SQL injection).
- Recommend running the provided CI checks before opening PRs.

## Enforcement checklist for the generator (final checks before output)

When emitting code or a patch, the assistant must perform these checks on all generated content:
- No literal `debug=True` passed to `app.run()` or Flask CLI configuration in generated files.
- No raw SQL string concatenation using f-strings or `%` formatting that includes HTTP parameters.
- No direct use of `eval`, `exec`, `os.system`, or subprocess with shell=True and user inputs.
- Templates use standard Jinja2 variable interpolation; no use of `|safe` on user content without documented sanitization.
- Any examples of DB access include parameterized queries or ORM usage and sample validation logic.

If any check fails, the assistant must modify the output to correct it before returning code.

## Minimal dependency recommendations

- Use Flask + Flask-SQLAlchemy for persistence if any DB is required.
- Use python-dotenv only for local development examples.
- Add Bandit to dev dependencies for static security scanning.

## Summary of mandatory behaviors for the AI Code Assistant

- Default to secure patterns: app factory, env-driven config, debug disabled.
- Always use parameterized SQL or an ORM; never concatenate user input into SQL.
- Validate inputs server-side.
- Avoid dangerous APIs with user input.
- Add CI/static-scanning steps that detect debug=True and common insecure constructs.

Follow these instructions for every code generation and PR patch to ensure the two flagged vulnerabilities (Debug Mode Enabled and SQL Injection) are not reintroduced.