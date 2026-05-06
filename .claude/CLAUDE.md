# AI Code Assistant Instructions — Flask Blog (Security-Hardened)

Revision checklist
- Remove any use of app.run(debug=True) and never generate debug-mode server code in source files.
- Prevent generation of raw SQL string concatenation; require parameterized queries or ORM usage.
- Require explicit validation and safe casting of all route parameters and HTTP inputs.
- Prohibit exec/eval/os.system calls with user data; avoid any code patterns that run or format shell/SQL commands from inputs.
- Add CI/pre-commit checks to detect debug flags and raw SQL concatenation patterns automatically.

## Purpose
These instructions guide the AI Code Assistant tool when generating or updating code for this Flask blog project. They emphasize secure defaults to eliminate the prior findings: (1) debug mode enabled in code (CWE-489) and (2) potential SQL injection via unsafe SQL string construction (CWE-89). Follow these rules strictly when producing code, tests, or configuration.

## High-level policies (must follow)
- Never emit code that sets Flask's debug mode in source files (no app.run(debug=True) or app.debug = True). Development debugging is allowed only via external developer tooling (Flask CLI or environment variables on local dev machines). Generated code must default to debug disabled.
- Do not introduce raw SQL built by concatenating or interpolating user-provided strings. Use parameterized queries or a well-maintained ORM (e.g., SQLAlchemy) with bind parameters.
- Validate and sanitize every HTTP route parameter and form input before use. Explicitly cast types (e.g., int(post_id)) with safe error handling.
- For file-system or shell operations, never use untrusted input directly. Use safe APIs (e.g., secure_filename, werkzeug.utils.safe_join) and prohibit exec/eval/os.system with untrusted data.
- Keep Jinja2 autoescape enabled; do not use the `|safe` filter on untrusted user content.
- Do not store secrets or credentials in source; read them from environment variables and never print them into logs.

## Project constraints to preserve
- No persistent database is required for this repository. If code generation must add a DB, follow the "Database rules" below and obtain explicit approval in the PR message before adding persistence.
- Posts should remain in-memory by default unless a clear migration plan and secure DB usage is provided.

## Code-generation rules and examples

### Disallow debug in generated server entrypoints
- Never generate source that enables Flask debugging. Use this pattern for local entrypoints:

```python
# DO NOT set debug=True in source code
import os
from app import app  # Flask app defined elsewhere

if __name__ == "__main__":
    # For local development prefer: `flask run` or set FLASK_ENV/FLASK_DEBUG in developer environment.
    # In source, always start with debug disabled.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=False)
```

- For production, generate deployment guidance that uses a WSGI server (gunicorn/uwsgi) rather than app.run:

```text
# Recommended production start (document only; not in application source)
# gunicorn -w 4 "app:app"
```

### Database rules (if introducing DB code)
- Prefer SQLAlchemy ORM or use DB-API parameterized queries. Never construct SQL with string concatenation or f-strings using user input.
- Parameterized sqlite3 example (safe):

```python
import sqlite3

def get_post_by_id(conn, post_id):
    try:
        pid = int(post_id)
    except (TypeError, ValueError):
        raise ValueError("invalid post id")
    cur = conn.cursor()
    cur.execute("SELECT id, title, body FROM posts WHERE id = ?", (pid,))
    return cur.fetchone()
```

- SQLAlchemy example (preferred):

```python
from sqlalchemy import Column, Integer, String, Text
from sqlalchemy.orm import declarative_base, Session

Base = declarative_base()

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True)
    title = Column(String(255))
    body = Column(Text)

# Query example (safe; ORM binds parameters automatically)
def get_post(session: Session, post_id: int):
    return session.query(Post).filter(Post.id == post_id).one_or_none()
```

### Input validation and type casting
- Validate and cast all route parameters and form inputs explicitly. Return appropriate HTTP error codes on invalid input.

```python
from flask import request, abort

@app.route("/post/<post_id>")
def view_post(post_id):
    try:
        pid = int(post_id)
    except (TypeError, ValueError):
        abort(400, "Invalid post id")
    # use pid safely from here
```

- For string inputs used in templates, rely on Jinja2 autoescape. If sanitization is required beyond escaping, use a well-tested library (e.g., bleach) and document why.

### Prohibit unsafe dynamic execution
- Never generate or accept code using eval(), exec(), os.system(), subprocess.run([...], shell=True) with user input. If subprocesses are required, always use a list without shell=True and validate arguments strictly.
- If any code generation attempt includes dynamic execution, reject and replace with a safe alternative.

### Template safety
- Keep Jinja2 autoescape enabled (default for Flask templates).
- Avoid `|safe` on any user-provided content. If markup must be allowed, sanitize explicitly and document.

## CI / Pre-commit checks (mandatory)
Include an automated check in CI to fail on introduced insecure patterns. Example GitHub Actions job snippet (adapt to your CI):

```yaml
name: Security checks

on: [push, pull_request]

jobs:
  check-insecure:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fail on debug flag or raw SQL concatenation
        run: |
          set -e
          # Check for debug=True in repo
          if grep -R --line-number --exclude-dir=.git --exclude="*venv*" "debug=True" .; then
            echo "ERROR: debug=True found in source. Remove before merging." >&2
            exit 1
          fi
          # Check for suspicious SQL concatenation patterns: + or f-strings used in execute(...) or in raw query creation
          if grep -R --line-number --exclude-dir=.git --exclude="*venv*" -E "execute\(.+[+{]" . || grep -R --line-number --exclude-dir=.git -E "cursor\.execute\(\s*f?\"" .; then
            echo "ERROR: Potential raw SQL concatenation detected. Use parameterized queries or ORM." >&2
            exit 1
          fi
      - name: Run Bandit security scan (optional)
        run: |
          pip install bandit
          bandit -r .
```

- Add a pre-commit hook or pre-merge check (in local dev or CI) to detect "debug=True" and obvious SQL concatenation.

## Guidance for AI Code Assistant behavior
When producing code or edits, the AI must:
- Default to secure configurations (debug disabled, no secrets in code).
- Explain any introduction of persistence or external services in the PR description and include secure usage patterns.
- Include relevant unit tests or checks that demonstrate validation behavior for inputs that previously triggered scanner findings (e.g., tests for invalid post_id returning 400).
- Insert comments in generated code where an environment-specific decision is required (e.g., deployment choice), reminding the reviewer to verify the production configuration.

## Example secure patterns summary
- Secure server start:
```python
app.run(host="127.0.0.1", port=5000, debug=False)
# production: use gunicorn/uwsgi; do not enable Flask debugger in source
```
- Safe DB usage:
```python
# sqlite3 parameterized example
cur.execute("SELECT * FROM posts WHERE id = ?", (post_id,))
```
- Safe input handling:
```python
try:
    pid = int(post_id)
except ValueError:
    abort(400)
```

## Review checklist for PRs generated by the AI tool
- No source file contains debug=True or app.debug = True.
- No SQL strings are formed via string concatenation or f-strings with user input.
- All route parameters are validated and cast with error handling.
- No exec/eval/os.system/subprocess(shell=True) invoked with untrusted input.
- Templates do not mark user content as safe without explicit, documented sanitization.

## Minimal developer notes
- Local dev can still use Flask CLI or set FLASK_ENV/FLASK_DEBUG locally; do not commit source-level debug settings.
- If adding a DB, include migration and secret-management guidance, and follow the Database rules section above.

Follow these instructions for every generated change to ensure the debug-mode and SQL injection issues are not reintroduced.