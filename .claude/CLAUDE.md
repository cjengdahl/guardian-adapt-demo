# Secure AI Code Assistant Instructions — Flask Blog Project

## Purpose
These instructions direct the AI Code Assistant to generate and modify code for this Flask blog project securely. They explicitly prevent introduction of Path Traversal, Debug Mode exposures, SQL Injection, and Cross-Site Scripting (XSS) vulnerabilities and provide safe, idiomatic patterns for file handling, DB access, templating, and deployment.

## High-level policies (must always be followed)
- Never enable Flask debug mode in committed or production code. Debug may be enabled only locally by developers and only via a local developer configuration (never hard-coded).
- Never use eval(), exec(), os.system(), subprocess.* with untrusted input, or create code that builds Python code from user input.
- Never construct filesystem paths or template names directly from user input. Use whitelists, secure filename utilities, path normalization, and explicit mapping.
- Always treat user-supplied content as untrusted. Escape or sanitize before rendering. Never use template filters that bypass escaping (e.g., Jinja2 |safe) on user input unless content is explicitly validated and trusted.
- For any DB access, always use parameterized queries / ORM with bound parameters. Never format SQL strings with user input.
- Store secrets and credentials only in environment variables or secret stores. Never hard-code secrets in source.
- Validate and whitelist all route parameters and inputs, and apply defensive checks server-side.

## Code generation rules (mandatory)
When generating code, the assistant must produce patterns that conform to the following:

1. Debug / Deployment
   - Do not output code that sets app.run(debug=True) in the repository.
   - Provide a safe run block using environment variables and default debug False:
     ```python
     import os

     if __name__ == "__main__":
         # Never default to debug=True. Use env var only for local dev.
         debug_mode = os.getenv("FLASK_DEBUG", "0") == "1"
         app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=debug_mode)
     ```
   - Recommend production deployment using a WSGI server (e.g., Gunicorn). Example:
     ```
     # Example production run (do not use debug)
     gunicorn -w 4 -b 0.0.0.0:8000 app:app
     ```

2. Path Traversal / File Handling
   - Never join user input directly into filesystem paths. Use secure_filename for uploads, hard-coded base directories, and resolve+check that the resolved path is inside the base directory.
   - Prefer send_from_directory for serving static or uploaded files and validate filenames via a whitelist or secure_filename.
     ```python
     from werkzeug.utils import secure_filename
     from flask import send_from_directory, abort
     from pathlib import Path
     import os

     UPLOAD_DIR = Path("/var/www/flask_blog/uploads").resolve()

     def is_safe_path(basedir: Path, path: Path) -> bool:
         try:
             return basedir == path.resolve().parents[len(basedir.resolve().parts)-1] or basedir in path.resolve().parents
         except Exception:
             return False

     def save_upload(file_storage):
         filename = secure_filename(file_storage.filename)
         if filename == "":
             abort(400)
         dest = (UPLOAD_DIR / filename).resolve()
         if not is_safe_path(UPLOAD_DIR, dest):
             abort(400)
         file_storage.save(dest)
         return filename

     @app.route("/uploads/<filename>")
     def uploaded_file(filename):
         # Validate filename against whitelist or secure_filename and serve from directory only
         safe_name = secure_filename(filename)
         return send_from_directory(str(UPLOAD_DIR), safe_name)
     ```
   - If mapping IDs to files, keep the mapping in memory or DB and never accept arbitrary file paths from the client.

3. SQL / Data Access (prevent SQL Injection)
   - Use an ORM (SQLAlchemy) or parameterized queries. Do not interpolate user input into SQL strings.
     - SQLAlchemy example:
       ```python
       # Using SQLAlchemy (recommended)
       from sqlalchemy import create_engine, text

       engine = create_engine(os.getenv("DATABASE_URL", "sqlite:///blog.db"), future=True)

       # Parametrized query using text() and bound parameters
       def get_post_by_id(post_id):
           with engine.connect() as conn:
               result = conn.execute(text("SELECT id, title, body FROM posts WHERE id = :id"), {"id": post_id})
               return result.fetchone()
       ```
     - sqlite3 parameterized example:
       ```python
       import sqlite3

       def get_post_by_id(db_path, post_id):
           conn = sqlite3.connect(db_path)
           try:
               cur = conn.cursor()
               cur.execute("SELECT id, title, body FROM posts WHERE id = ?", (post_id,))
               return cur.fetchone()
           finally:
               conn.close()
       ```
   - Validate and coerce route parameters (e.g., ensure `post_id` is an integer) before passing to DB.

4. XSS / Templating
   - Rely on Jinja2 autoescaping for HTML templates. Do not mark user content as safe unless explicitly sanitized.
   - If user HTML is allowed (rare), sanitize with a robust library such as bleach with a strict whitelist:
     ```python
     import bleach

     ALLOWED_TAGS = ["b", "i", "u", "em", "strong", "a", "p", "ul", "li", "br"]
     ALLOWED_ATTRS = {"a": ["href", "title", "rel"]}

     def sanitize_html(user_html):
         return bleach.clean(user_html, tags=ALLOWED_TAGS, attributes=ALLOWED_ATTRS, strip=True)
     ```
   - Escape user input with flask.escape() if inserting into non-template contexts.
   - Do not use Jinja2's |safe filter for content that originates from users.

5. Input Validation and Whitelisting
   - Validate types and lengths for all form fields and route parameters.
   - Use explicit whitelists for allowed filenames, allowed MIME types, and allowed form values.
   - Reject inputs that do not conform; return 4xx responses, not 5xx.

6. Secrets and Configuration
   - All secrets (API keys, DB credentials, salts) must be read from environment variables or external secret stores. Never output code that hard-codes secrets.
     ```python
     SECRET_KEY = os.getenv("FLASK_SECRET_KEY")
     if not SECRET_KEY:
         raise RuntimeError("FLASK_SECRET_KEY must be set in the environment")
     app.config["SECRET_KEY"] = SECRET_KEY
     ```

7. Logging, Error Handling, and Security Headers
   - Do not leak stack traces or internal errors to clients. Use generic error pages in production.
   - Add secure HTTP headers (Content-Security-Policy, X-Content-Type-Options, X-Frame-Options, Referrer-Policy). Example:
     ```python
     @app.after_request
     def set_security_headers(response):
         response.headers["X-Content-Type-Options"] = "nosniff"
         response.headers["X-Frame-Options"] = "DENY"
         response.headers["Referrer-Policy"] = "no-referrer"
         # Example CSP: adjust as needed for your static/inline resources
         response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
         return response
     ```

8. Static Templates and Template Selection
   - Never render templates based on user-provided template names. Template names must be static or derived from safe internal logic.
   - Avoid template injection by never accepting raw template source from users.

## Recommended secure code examples (copy-paste safe)
- Safe run block (no debug default)
```python
import os
from flask import Flask

app = Flask(__name__)
app.config["SECRET_KEY"] = os.getenv("FLASK_SECRET_KEY", "dev-placeholder")  # enforce override in prod

if __name__ == "__main__":
    # Use FLASK_DEBUG=1 locally only. Default is production-safe.
    debug_mode = os.getenv("FLASK_DEBUG", "0") == "1"
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=debug_mode)
```

- Parameterized DB access (SQLAlchemy)
```python
from sqlalchemy import create_engine, text
import os

engine = create_engine(os.getenv("DATABASE_URL", "sqlite:///blog.db"), future=True)

def create_post(title, body):
    with engine.begin() as conn:
        conn.execute(text("INSERT INTO posts (title, body) VALUES (:title, :body)"),
                     {"title": title, "body": body})
```

- Sanitizing user input for display
```python
from markupsafe import escape
# For plain text:
safe_title = escape(user_input_title)
# If HTML allowed, use bleach.clean() as shown in the policies section
```

## Static analysis, tests, and CI checks
- All changes produced by the assistant must pass static security checks:
  - Run Bandit, Safety, or a comparable scanner on Python code in CI.
  - Run a templating/lint scan to detect unescaped template usage.
- Add unit tests that assert:
  - Route parameters are validated (e.g., numeric IDs reject non-numeric values).
  - File-serving endpoints never return files outside the allowed upload directory.
  - DB functions use parameterized queries (integration tests can verify behavior).

## Pre-commit and repository hygiene
- Enforce pre-commit hooks that include linters and security scanners to prevent insecure code from being committed.
- Ensure code reviews specifically check for:
  - No debug=True in code
  - No use of eval/exec or unsafe subprocess calls
  - All DB queries parameterized
  - File paths normalized and constrained
  - No hard-coded secrets

## When the AI Code Assistant should refuse or ask for clarification
- If a requested change requires enabling debug mode, external secrets, or dynamic template paths, refuse and propose a secure alternative.
- If user requests serving arbitrary files provided by clients or executing arbitrary commands, refuse and provide a secure design pattern instead (e.g., whitelist, stored mappings, job queue).

## Reference checks for generated snippets
Before finalizing any generated code, the assistant must ensure:
- No usage of eval/exec, os.system, subprocess.* with user input.
- All filesystem writes/reads use secure_filename, base directories, and path resolution checks.
- All SQL operations use parameterization/ORM; no f-strings or %-formatting with user data in SQL.
- Templates render user content only through escaping or sanitized HTML.

## Minimal examples of unsafe patterns to avoid (for assistant internal detection)
- Do NOT generate:
  ```python
  app.run(debug=True)
  conn.execute(f"SELECT * FROM posts WHERE id = {user_id}")
  os.system("convert " + user_supplied_filename)
  render_template(user_supplied_template_name + ".html")
  ```
- Instead replace with the safe alternatives shown in this document.

--- 

Follow these instructions exactly when producing or modifying repository code to prevent reintroduction of Path Traversal, Debug Mode exposure, SQL Injection, and XSS vulnerabilities.