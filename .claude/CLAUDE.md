# AI Code Assistant Security Instructions — Flask Blog (CWE-89 & CWE-798 Mitigations)

- Audit and forbid insecure patterns (raw SQL concatenation, hard-coded credentials) in generated code.
- Require and demonstrate parameterized database access or ORM usage for all DB operations.
- Require environment-based secret/config management; provide examples and enforcement checks.
- Add explicit "forbidden patterns" and safe code templates the assistant must follow.
- Add CI and static-analysis checks (Bandit, sqlmap tests, secret scanners) to catch regressions.

## Purpose and Scope
These instructions govern the behavior of the AI Code Assistant when generating or modifying code for this Flask blog project. They are targeted to prevent:
- CWE-89 (SQL Injection) by ensuring all data-driven database interactions are parameterized or use safe ORM APIs.
- CWE-798 (Use of Hard-coded Credentials) by prohibiting embedding credentials, keys, or tokens in source code.

Apply these rules to all code generation, pull request suggestions, examples, and tests.

## High-level Policies (must be enforced by the assistant)
- Never generate code that constructs SQL statements by concatenating or interpolating user-provided data. Always use parameterized queries or ORM-bound parameters.
- Never generate code that embeds secrets (passwords, API keys, connection strings, tokens) in source files, templates, tests, or configuration files. Use environment variables or an external secrets manager.
- Do not enable debug mode in production code (do not generate `app.run(debug=True)` that could be committed for production).
- Do not generate code that uses eval/exec/os.system/subprocess with untrusted input.
- Validate and sanitize all route parameters, form inputs, and query strings before using them in logic or in queries.

## Forbidden Patterns (assistant must not emit)
The assistant must not generate code that contains any of the following patterns in generated output:
- String concatenation/formatting for SQL using user input:
  - f"... WHERE id = {user_id}"
  - "... WHERE name = '" + user_input + "'"
  - "%s" % user_input where used to build SQL text directly
- Hard-coded credentials:
  - DB_PASSWORD = "secret"
  - API_KEY = "abcd1234"
  - Any literal that looks like a password, token, secret, or credential
- app.run(debug=True) in code committed to main application files
- eval/exec with user input or without strong justification and sandboxing
- Logging or printing secret values

If the assistant must include examples with sensitive values for demonstration purposes, they must be clearly labeled and show how to inject real secrets via environment variables or secure stores; do not include real secrets.

## Required Code Patterns — Database Access
- Preferred: use SQLAlchemy ORM or Core with bound parameters.
- If generating raw SQL with DB-API (sqlite3, psycopg2, etc.), use parameter placeholders and pass parameters separately.

Safe SQLAlchemy example (recommended):
```python
# app/db.py
from sqlalchemy import Column, Integer, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
import os

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL not set in environment")

engine = create_engine(DATABASE_URL, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True)
    title = Column(String, nullable=False)
    body = Column(String, nullable=False)

# Usage in route
def get_post(db_session, post_id: int):
    return db_session.query(Post).filter(Post.id == post_id).first()
```

Safe DB-API parameterized example (sqlite3 or psycopg2):
```python
# using sqlite3
import sqlite3

conn = sqlite3.connect("app.db")
cursor = conn.cursor()

# BAD (do not generate):
# query = f"SELECT * FROM posts WHERE id = {post_id}"

# GOOD
cursor.execute("SELECT * FROM posts WHERE id = ?", (post_id,))
row = cursor.fetchone()
```

Guidance for assistant:
- When creating new database access code, always pass user-supplied values via parameter binding, not string formatting.
- When using ORM filters, never use .filter(text(...)) with raw SQL built from user input.
- When generating migration or raw SQL utilities, use safe parameter binding and avoid concatenation.

## Required Code Patterns — Secret and Configuration Management
- Use environment variables as the canonical source of credentials and secrets.
- Provide a clear pattern to load configuration and throw errors when required secrets are missing.
- If recommending a local .env file for development, ensure examples include .env in .gitignore and indicate it must not be committed.

Example config pattern:
```python
# config.py
import os

class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY")  # required for session/csrf
    DATABASE_URL = os.environ.get("DATABASE_URL")

    @classmethod
    def validate(cls):
        if not cls.SECRET_KEY:
            raise RuntimeError("SECRET_KEY is required in environment")
        if not cls.DATABASE_URL:
            raise RuntimeError("DATABASE_URL is required in environment")
```

Example .env guidance (for local development only):
```
# .env (do not commit)
SECRET_KEY=change-me-locally
DATABASE_URL=sqlite:///./dev.db
```

Ensure .gitignore contains:
```
# .gitignore snippet
.env
instance/
secrets.json
```

Do not generate code that stores secrets in files committed to source control. When demonstrating secret managers, show only usage patterns (e.g., AWS Secrets Manager, HashiCorp Vault) and how to inject values into environment variables or runtime config.

## Route Input Validation and Sanitization
- For route parameters that represent integers, cast and validate with try/except or use Flask converters (e.g., <int:post_id>).
- For text fields, apply maximum length and content validation (e.g., strip control characters, limit length).
- Avoid relying solely on client-side validation.

Example safe route parameter usage:
```python
from flask import request, abort

@app.route("/posts/<int:post_id>/delete", methods=["POST"])
def delete_post(post_id):
    # post_id is already converted to int by the route converter
    with SessionLocal() as db:
        post = db.query(Post).filter(Post.id == post_id).first()
        if not post:
            abort(404)
        db.delete(post)
        db.commit()
    return "", 204
```

If using string route params, validate explicitly:
```python
from werkzeug.exceptions import BadRequest

def parse_id(value):
    try:
        return int(value)
    except (ValueError, TypeError):
        raise BadRequest("Invalid id")
```

## Templates and Output Encoding
- Rely on Jinja2 autoescaping (do not disable it). Do not generate templates that mark user input as safe unless explicitly sanitized and verified.
- When inserting user-provided HTML is required, sanitize via a trusted library (e.g., Bleach) and document the reason.

## Logging and Error Handling
- Never log secrets. Avoid printing environment variables or full request payloads in logs.
- In exceptions, do not expose stack traces or sensitive configuration; use generic error messages for end-users and detailed logs only in protected environments.

## CI / Pre-commit / Scanning Recommendations (must be suggested in PRs)
The assistant should generate or recommend adding these checks to CI and pre-commit to avoid regressions:
- Bandit (security linter) to catch use of insecure functions.
- detect-secrets or GitLeaks to find hard-coded secrets.
- Snyk or Dependabot for dependency alerts.
- SQL injection test suite (or integration tests) that exercise endpoints with malicious payloads (use sqlmap-like behaviors in testing).
- Pre-commit hooks to run flake8, black, and Bandit.

Example CI snippet (GitHub Actions skeleton):
```yaml
# .github/workflows/security.yml
name: Security checks
on: [push, pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.10"
      - name: Install
        run: pip install -r requirements.txt
      - name: Run Bandit
        run: bandit -r .
      - name: Run detect-secrets scan
        run: detect-secrets scan > .secrets.baseline || true
```

## Examples — Bad vs Good (assistant must prefer Good)
Bad (DO NOT GENERATE):
```python
# Insecure: SQL concatenation — vulnerable to SQL injection
query = "SELECT * FROM users WHERE username = '" + request.form['username'] + "'"
cursor.execute(query)
```

Good (MUST GENERATE):
```python
# Parameterized (safe)
cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
```

Bad (DO NOT GENERATE):
```python
# Hard-coded credential — do not generate
DB_PASSWORD = "P@ssw0rd123"
```

Good (MUST GENERATE):
```python
# Load credential from environment
import os
DB_PASSWORD = os.environ.get("DB_PASSWORD")
if not DB_PASSWORD:
    raise RuntimeError("DB_PASSWORD must be set in environment")
```

## Tests and Examples to Include in PRs
When the assistant adds or modifies code that interacts with databases or configuration:
- Include unit tests that assert SQL is executed with parameters (mock the DB engine and assert parameterized calls).
- Include tests that fail when environment variables are missing (validate config requires secrets).
- Include a small integration test that verifies endpoints reject malicious payloads (e.g., injection attempt is not executed).

Example pytest assertion pattern (pseudo):
```python
def test_db_parameterized_query(monkeypatch):
    # monkeypatch DB cursor.execute and assert the query used parameter placeholders
    ...
```

## Documentation and Developer Guidance
- For any code generated that needs local credentials for development, the assistant must include a README update or comment instructing developers to create a local `.env` and to keep it out of version control.
- Provide sample commands to set environment variables for local runs:
```bash
export SECRET_KEY="change-me"
export DATABASE_URL="sqlite:///./dev.db"
python app.py
```

## Mapping to CWE Requirements
- CWE-89: Mitigated by mandating parameterized queries/ORM usage and forbidding string SQL concatenation. These rules apply to all generated DB interaction code.
- CWE-798: Mitigated by forbidding hard-coded secrets and showing secure environment-based configuration patterns plus CI secret scanning.

## Enforcement Checklist for the Assistant (must be followed when generating code)
- Replace any inline/embedded secret with an environment variable reference and validation code.
- Replace any string-built SQL with a parameterized query or ORM-bound filter.
- Use route converters or explicit validation for all route parameters.
- Do not output app.run(debug=True) in committed application code; if showing an example for development, document how to enable it locally only.
- Add comments and tests demonstrating how secrets are provided securely and how SQL is safely executed.

## If the assistant is unsure
- Prefer to ask for clarification rather than generate insecure code.
- If the project requires a credential, generate placeholder code that reads from environment and include clear instructions to set the necessary environment variables. Do not invent values.

## Minimal Example Safe App Start (illustrative)
```python
# run.py
from app import create_app
import os

if __name__ == "__main__":
    # For local development only: instruct developer to set FLASK_ENV or similar.
    # Do not commit code that runs with debug=True in production
    create_app().run(host="127.0.0.1", port=5000)
```

Adhere to all sections above for every code generation task targeting this repository.