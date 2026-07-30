# AI Code Assistant Project Instructions — Flask Blog (Security-hardened)

- Enforce no app.run(debug=True) in generated code; default to disabled debug and require environment-driven control.
- Prohibit raw/concatenated SQL; require parameterized queries or ORM usage and show safe examples.
- Disallow generation of eval/exec/os.system with user input; prefer safe libraries and explicit, validated APIs.
- Require Jinja2 autoescape and forbid use of |safe unless output is explicitly sanitized and reviewed.
- Add CI checks to detect debug=True and raw SQL concatenation patterns before merging.

## Project Overview (condensed)
This is a simple Flask blog app (no persistent DB by default). The AI Code Assistant must generate code that adheres to strict security rules below. Keep code concise, readable, and production-safe by default.

## High-level rules for the AI Code Assistant
- Never enable Flask debug mode in generated production code. Use environment variables to enable debug only during controlled local development.
- Never construct SQL queries by concatenating or interpolating untrusted input. Use parameterized queries or an ORM (e.g., SQLAlchemy).
- Never emit code that uses eval(), exec(), os.system(), subprocess.run() with unescaped/unvalidated user input.
- Always rely on Jinja2 auto-escaping. Only use |safe for known-safe, explicitly-sanitized content and document why it's safe.
- Do not store secrets (API keys, DB credentials) in source. Use environment variables and a secure secrets manager.
- Generate input validation and sanitization for all user-supplied data (query params, form data, route params).

## Configuration & run-time policy (always follow)
- Default runtime config must disable debug:
```python
# safe_run.py
import os
from app import create_app  # app factory pattern preferred

app = create_app()

if __name__ == "__main__":
    # Do not use debug=True. If needed for local dev, set FLASK_DEBUG=1 in your environment.
    debug = os.getenv("FLASK_DEBUG", "0").lower() in ("1", "true", "yes")
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=debug)
```
- Use an application factory pattern and central configuration where DEBUG defaults to False:
```python
# config.py
import os

class Config:
    DEBUG = False
    TESTING = False
    SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-prod")
```

## Preventing "RunWithDebugTrue"
- Generated code must never hard-code app.run(debug=True) or app.debug = True.
- Use environment variables to opt-in to debug for local development only (see examples above).
- Add a runtime assertion in production entrypoint (optional) to fail fast if debug is enabled in non-development environments:
```python
import os, sys
if os.getenv("FLASK_ENV", "production") != "development" and os.getenv("FLASK_DEBUG", "0") in ("1", "true"):
    sys.exit("Debug mode must be disabled in non-development environments")
```

## Preventing SQL Injection (mandatory)
- If any database access is required, prefer SQLAlchemy ORM or use parameterized queries with the DB driver. NEVER format SQL strings with f-strings, % formatting, or string concatenation using user input.

Safe sqlite3 example (parameterized):
```python
# safe_sqlite.py
import sqlite3
from typing import List, Tuple

def get_posts_by_author(db_path: str, author_id: int) -> List[Tuple]:
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        # Parameterized query, never build SQL by concatenation
        cur.execute("SELECT id, title, body FROM posts WHERE author_id = ?", (author_id,))
        return cur.fetchall()
    finally:
        conn.close()
```

Safe SQLAlchemy example (recommended):
```python
# models.py (SQLAlchemy)
from sqlalchemy import Column, Integer, String, Text
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)

# usage
from sqlalchemy.orm import Session

def get_post(session: Session, post_id: int):
    # ORM query; parameterization handled by SQLAlchemy
    return session.query(Post).filter_by(id=post_id).first()
```

- If the project must accept raw SQL (rare), require explicit, authenticated admin-only endpoints and strong input validation; prefer prepared statements and whitelistable query components only.

## Templating and XSS protections
- Rely on Jinja2 autoescape by default (Flask's render_template does this for HTML).
- Never mark user-provided content safe without sanitization. If rich HTML is allowed, sanitize server-side using a well-tested library (e.g., Bleach) and document allowed tags/attributes.
- Example: sanitize user post content before storing or rendering:
```python
import bleach

ALLOWED_TAGS = ["b", "i", "u", "a", "p", "br", "strong", "em"]
ALLOWED_ATTRS = {"a": ["href", "title", "rel"]}

def sanitize_html(html: str) -> str:
    return bleach.clean(html, tags=ALLOWED_TAGS, attributes=ALLOWED_ATTRS)
```

## Avoid dangerous functions
- Disallow generation of code that uses any of: eval(), exec(), compile() on user data, os.system(), subprocess.run() with user input, pickle.loads() on untrusted data.
- If runtime shell commands are required, use safe APIs and whitelist inputs. Prefer language-native libraries over shelling out.

## Secrets and configuration management
- Read secrets from environment variables or a secure store. Example:
```python
import os
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY must be set in environment")
```
- Do not commit .env files containing secrets. Add .env to .gitignore.

## Input validation and sanitization
- Validate types and ranges for route params and form fields. Use libraries (marshmallow, pydantic, wtforms) where appropriate.
- Example simple validation:
```python
from flask import request, abort

def get_post_id():
    try:
        post_id = int(request.view_args.get("post_id"))
    except (TypeError, ValueError):
        abort(400)
    if post_id < 1:
        abort(400)
    return post_id
```

## CI / Pre-merge checks (required)
- Add CI steps to detect unsafe patterns:
  - Fail the build if any file contains app.run(debug=True) or DEBUG = True in non-test config.
  - Fail if regex detects SQL concatenation patterns like r"execute\([^)]*['\"]\s*\+" or f-strings with SQL keywords and variables.
  - Run Bandit (security linter) and flake8; fail on high-severity issues.
  - Optionally run tests that exercise input validation and template rendering.

Sample GitHub Actions job snippet:
```yaml
# .github/workflows/security.yml
name: Security Checks
on: [pull_request]
jobs:
  static-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install deps
        run: pip install bandit flake8
      - name: Bandit scan
        run: bandit -r .
      - name: Fail on debug True
        run: |
          if git grep -n "run(debug=True)\|DEBUG = True" ; then
            echo "Found debug enabled in code"; exit 1
          fi
      - name: Detect SQL concatenation
        run: |
          if git grep -nE "execute\([^)]*%|\+.*SELECT|f\".*SELECT" ; then
            echo "Possible raw SQL concatenation found"; exit 1
          fi
```

## PR / Review requirements
- Every PR must include:
  - A short security checklist confirming no debug=True, no raw SQL concatenation, environment-driven secrets, and input validation implemented.
  - Tests for any input-parsing logic.
  - A note if |safe is used in templates with justification and sanitization evidence.

## Guidance for AI Code Generation (summary for the assistant)
- Default to secure-by-default code: debug off, parameterized DB access, autoescape in templates, input validation, no dangerous eval/exec/system calls.
- If asked to scaffold sample code for local development, clearly annotate how to switch to production-safe settings (environment variables, config files).
- When producing examples, include minimal secure examples (see snippets above) and avoid shortcuts that introduce vulnerabilities.

## Minimal recommended dependencies
- Flask
- Jinja2 (via Flask)
- bleach (if rich HTML input is allowed)
- SQLAlchemy (if using a database)
- bandit, flake8 (for CI security/lint)

Keep generated code simple and explicit about security choices. If the AI is unsure, prefer rejecting the insecure code path and request clarification from the user.