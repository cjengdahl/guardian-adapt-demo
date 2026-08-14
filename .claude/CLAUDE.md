# AI Code Assistant Instruction File — Secure Code Generation for Flask Blog

## Purpose
Provide concise, enforceable instructions for an AI Code Assistant generating code for this Flask blog repository. These instructions explicitly mitigate CWE-89 (SQL Injection) and CWE-798 (Hard-coded Credentials) and ensure the assistant will not produce code that introduces those vulnerabilities.

## High-level policies (must follow)
- Never generate SQL statements with direct string concatenation, interpolation, or formatting using untrusted input.
- Never include hard-coded credentials, API keys, secrets, tokens, or password literals in source code or examples. Use environment variables or a secrets manager.
- Prefer safe abstractions (ORMs like SQLAlchemy) or parameterized, prepared statements when database access is required.
- If the user requests example credentials for demonstration, always use clearly labeled placeholders (EXAMPLE_*) and include instructions to replace them with environment variables or vaults.
- Add or update tests and CI checks in PRs to detect both SQL injection patterns and hard-coded secrets before merging.
- On ambiguous requests (e.g., "connect to DB"), ask clarifying questions before generating code: which DB, connection method, and whether credentials come from env/secret manager.

## Project overview (condensed)
- Flask app with Jinja2 templates, no persistent DB by default.
- Posts stored in memory at runtime.
- Development: `python app.py` (do not enable debug mode in production).
- All generated code must preserve Jinja2 autoescape for rendering user inputs.

## Secure database access guidance (prevents CWE-89)
- Default behavior: do not introduce persistent storage or raw SQL unless explicitly requested.
- If DB code is required, follow one of these safe patterns:
  - Use an ORM (recommended): SQLAlchemy with parameter binding and query APIs.
  - Use parameterized queries / prepared statements. Do NOT use f-strings, string concatenation, or .format() to build SQL queries.

Examples:

- SQLAlchemy (recommended)
```python
# SQLAlchemy engine/session pattern (example)
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.orm import sessionmaker, declarative_base
import os

DATABASE_URL = os.environ["DATABASE_URL"]  # e.g., postgresql://user:pass@host/db
engine = create_engine(DATABASE_URL, echo=False, future=True)
Session = sessionmaker(bind=engine, autoflush=False)
Base = declarative_base()

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True)
    title = Column(String, nullable=False)
    content = Column(String, nullable=False)

# Usage
with Session() as session:
    post = Post(title="Hello", content="World")
    session.add(post)
    session.commit()
```

- sqlite3 with parameterized queries (avoid concatenation)
```python
import sqlite3
import os

DB_PATH = os.environ.get("DB_PATH", "app.db")
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Safe insertion using parameter placeholders (no string concatenation)
cursor.execute("INSERT INTO posts (title, content) VALUES (?, ?)", (title, content))
conn.commit()

# Safe selection
cursor.execute("SELECT id, title FROM posts WHERE id = ?", (post_id,))
row = cursor.fetchone()
```

- psycopg2 (PostgreSQL) with parameterized queries
```python
import psycopg2
import os

conn = psycopg2.connect(os.environ["DATABASE_URL"])
with conn:
    with conn.cursor() as cur:
        cur.execute("SELECT id, title FROM posts WHERE id = %s", (post_id,))
        row = cur.fetchone()
```

- Forbidden (examples of what NOT to generate)
```python
# DO NOT generate code like this:
query = f"SELECT * FROM posts WHERE id = {post_id}"          # vulnerable to SQL injection
query = "SELECT * FROM posts WHERE title = '" + title + "'"  # vulnerable
cursor.execute(query)
```

## Secret management guidance (prevents CWE-798)
- Never hard-code credentials, keys, or secrets in source files, config samples, or generated code.
- Always source credentials from environment variables, a secrets manager (HashiCorp Vault, AWS Secrets Manager), or platform config (Kubernetes Secrets).
- For local development, prefer .env (gitignored) and explicit guidance to use python-dotenv; still never check .env into VCS.

Examples:

- Environment variable (preferred)
```python
import os

DATABASE_URL = os.environ["DATABASE_URL"]  # require presence
SECRET_KEY = os.environ.get("FLASK_SECRET_KEY", None)
if not SECRET_KEY:
    raise RuntimeError("FLASK_SECRET_KEY must be set in the environment")
```

- python-dotenv for local dev (only in dev)
```python
# .env should be gitignored
from dotenv import load_dotenv
load_dotenv()  # loads .env into environment variables
```

- Using a secret manager (outline)
```
# Pseudocode:
secret = vault_client.get_secret("myapp/database-url")
DATABASE_URL = secret.value
```

- Forbidden patterns (do not generate)
```python
# DO NOT generate code with literals like:
DB_USER = "admin"
DB_PASS = "supersecret"              # CWE-798: hard-coded credentials
API_KEY = "AKIA...."                 # secrets in source
```

## Generation constraints and assistant behavior
- Before generating any code that interacts with external systems or requires credentials, the assistant must:
  - Ask whether to use an in-memory store, a provided DB URL, or a secret manager.
  - If credentials are required, insist they be provided via environment variables or placeholders only.
- When returning example code with placeholders, include explicit instructions and a snippet showing how to set env vars (1–2 lines).
- When asked to provide sample configuration, use sanitized placeholders and a clear admonition: "Replace these placeholders with secure values and do not commit to source control."

Prompt-safe examples for assistant responses:
- Good: "Below is an example using DATABASE_URL from an environment variable. Replace EXAMPLE_* placeholders in your environment; do not commit them."
- Bad: "Here is a sample with username 'admin' and password 'password'." — DO NOT produce.

## CI / Pre-merge checks and static analysis
Add or update CI and pre-commit hooks to detect SQL injection patterns and hard-coded secrets.

- Required tools (suggested)
  - Bandit (Python security linter)
  - detect-secrets or git-secrets
  - Semgrep with rules for SQL injection and hard-coded credentials
  - pre-commit for Git hooks

- Example pre-commit config snippet
```yaml
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.4.0
  hooks:
    - id: detect-aws-credentials
- repo: https://github.com/Yelp/detect-secrets
  rev: v1.1.0
  hooks:
    - id: detect-secrets
- repo: https://github.com/PyCQA/bandit
  rev: 1.7.5
  hooks:
    - id: bandit
- repo: https://github.com/returntocorp/semgrep
  rev: v1.33.0
  hooks:
    - id: semgrep
      args: [--config, path/to/semgrep-rules.yml]
```

- Example Semgrep rule snippets (illustrative)
```yaml
rules:
  - id: python-sql-concat
    patterns:
      - pattern: f"SELECT $X"
      - pattern-either:
          - pattern: "$Q + $X"
          - pattern: "$Q.format($X)"
    message: "Potential SQL injection via string concatenation/formatting"
    languages: [python]
    severity: ERROR

  - id: python-hardcoded-credential
    patterns:
      - pattern: "$VAR = 'password'"
      - pattern: "$VAR = 'SECRET'"
    message: "Hard-coded credential detected"
    languages: [python]
    severity: ERROR
```

- CI stage actions
  - Run bandit, semgrep, and detect-secrets on changed files.
  - Fail PR if any new instances of forbidden patterns or secret literals are introduced.

## PR review checklist (enforce policies)
For any PR that adds or changes code related to storage or configuration:
- Does the change avoid SQL string concatenation and use parameterized queries or ORM APIs?
- Are all credentials and secrets loaded from env vars or secure stores, not hard-coded?
- Did CI checks (bandit, semgrep, detect-secrets) pass with no new findings?
- Are example credentials placeholders and documented as non-production in README or code comments?
- Is debug mode disabled for production runs? (No app.run(debug=True) in production branches.)

## Developer prompt templates (use when requesting DB or credential code)
- Safe DB request:
  - "Generate Flask code to store posts in PostgreSQL using SQLAlchemy. Use DATABASE_URL from environment variables and show how to set DATABASE_URL locally. Do not include any real credentials."
- Safe credential request:
  - "Show how to configure and load FLASK_SECRET_KEY from environment variables; use a placeholder and explain how to generate a secure key."

## Examples of acceptable assistant behavior
- If asked to "connect to a database", assistant responds:
  - Asking clarifying question: "Which database engine should I use, and will you provide a DATABASE_URL in the environment?" Then generate safe code only after confirmation.
- If asked to include an example credential in docs, assistant uses EXAMPLE_* placeholders and emphasizes never to commit real secrets.

## Enforcement: what to reject
The assistant must refuse or rework outputs that:
- Include direct concatenation/interpolation of user input into SQL statements.
- Contain plaintext credentials, API keys, or secrets in code blocks, comments, or config files.
- Provide runnable production credentials in examples.

## Minimal secure examples to include in repository docs
- How to export env vars locally (Linux/macOS)
```bash
export DATABASE_URL="postgresql://user:password@host:5432/dbname"  # DO NOT commit
export FLASK_SECRET_KEY="REPLACE_WITH_SECURE_RANDOM_KEY"          # DO NOT commit
```
- How to use python-dotenv for local development
```bash
# .env (gitignored)
DATABASE_URL=postgresql://EXAMPLE_USER:EXAMPLE_PASS@localhost:5432/example_db
FLASK_SECRET_KEY=EXAMPLE_FLASK_SECRET
```

## Final notes to assistant
- Prioritize secure patterns over brevity when generating examples.
- When in doubt, ask clarifying questions rather than generating potentially insecure code.
- All generated code must include comments explaining where secrets should come from and how to rotate them.