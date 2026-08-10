# AI Code Assistant Tool — Flask Blog Project Instructions

## Project Overview
This repository is a simple Flask blog (in-memory posts) using Jinja2 templates. The AI Code Assistant tool must generate code and edits that are secure, follow best practices, and avoid introducing the vulnerabilities identified by previous scans (Command Injection, Debug Mode Enabled, Cross-site Scripting).

## High-level Security Requirements
- Never allow user-supplied input to be executed as code or shell commands.
- Never enable Flask debug mode in code checked into the repository or in production.
- Always treat all HTTP input as tainted and validate/sanitize before use or rendering.
- Do not store secrets or credentials in source; read them from environment variables or a secrets manager.

## Forbidden Patterns (must never be generated)
- eval(...), exec(...), compile(...), ast.literal_eval on user input.
- os.system(...), subprocess.call/ Popen/ run(..., shell=True) using unvalidated user input.
- Using Jinja2 Markup(...) or the `|safe` filter on untrusted user input without an explicit, documented sanitization step.
- app.run(debug=True) or any hard-coded DEBUG=True in the repository.

## AI Code Assistant Tool Rules (generation constraints)
When producing code or edits, the tool must:
1. Treat request.* sources (request.args, request.form, request.values, request.cookies, request.headers, request.get_json(), path params) as tainted.
2. Insert explicit validation and/or sanitization for any tainted value before it is:
   - used to construct shell/OS commands,
   - used as a template name or template context that might be rendered unescaped,
   - passed into eval/exec-like functionality,
   - stored if the storage or later rendering could expose other users.
3. Prefer whitelisting (allowed values or strict types) over blacklisting.
4. For commands or subprocesses, require both:
   - a code comment documenting why executing anything is necessary, and
   - a strict whitelist of allowed commands and arguments; use subprocess with list arguments and shell=False.
5. Use clearly named helper functions for validation/sanitization and reuse them across generated code.
6. Add unit tests or small examples that exercise validation logic when touching code that deals with tainted input.

## Input Validation & Sanitization Guidelines
- Prefer type coercion and range checks:
  - Example: validate integer id route params using int() with try/except and bounds checks.
- For string fields:
  - Enforce max length.
  - Use a whitelist regex for formats (e.g., titles, slugs).
  - Normalize or reject unexpected characters.
- For any user-provided filename, command, or template name:
  - Reject unless it matches a strict whitelist of allowed values.
  - Never build shell strings by concatenation.

Example: validating an integer route parameter
```python
from flask import abort, request

def parse_post_id(value):
    try:
        pid = int(value)
    except (TypeError, ValueError):
        abort(400, "Invalid post id")
    if pid < 0 or pid > 1_000_000:
        abort(400, "post id out of range")
    return pid

# Usage in route:
# post_id = parse_post_id(request.view_args.get('id') or request.args.get('id'))
```

Example: whitelist validation for simple commands (avoid if possible)
```python
import subprocess

ALLOWED_CMDS = {
    "status": ["/usr/bin/myapp-status"],
    "health": ["/usr/bin/myapp-health"]
}

def run_allowed_command(cmd_key):
    if cmd_key not in ALLOWED_CMDS:
        raise ValueError("command not allowed")
    # subprocess.run uses a list to avoid shell interpretation
    result = subprocess.run(ALLOWED_CMDS[cmd_key], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return result
```

## Preventing Command Injection (CWE-78)
- Never pass user input to shell=True or to any API that performs shell interpolation.
- Use subprocess.run([...], shell=False) and pass each argument as a separate list element.
- If arguments depend on user input, validate each argument against a whitelist or strict pattern.
- If an external program must be invoked, prefer to:
  - implement the logic in Python instead of spawning processes, or
  - use a predefined mapping of allowed operations to fixed command lists (see example above).

Explicit rule for the AI tool:
- If code proposes executing an OS command, the generated PR must include:
  - a justification comment,
  - a unit test or integration test covering the allowed command paths,
  - and a clear validation routine ensuring no untrusted input reaches the command.

## Preventing Cross-Site Scripting (XSS) (CWE-79)
- Rely on Jinja2 autoescaping for HTML templates. Do not disable autoescaping globally.
- Never use `|safe` or `Markup()` on untrusted input. If markup is necessary, sanitize using a well-maintained library (e.g., bleach) with a strict whitelist.
- Use flask.escape or markupsafe.escape for explicit escaping in code contexts outside templates.

Sanitization example using bleach (only when limited HTML is required):
```python
import bleach

ALLOWED_TAGS = ["b", "i", "u", "em", "strong", "a"]
ALLOWED_ATTRIBUTES = {"a": ["href", "title", "rel"]}

def sanitize_html(user_html):
    return bleach.clean(user_html, tags=ALLOWED_TAGS, attributes=ALLOWED_ATTRIBUTES, strip=True)
```

Rendering guidance:
- Template usage (safe):
  - In templates: {{ post.content }}  # Jinja2 autoescapes
- If allowing sanitized HTML:
  - In Flask code: safe_content = sanitize_html(user_input)
  - Template: {{ safe_content | safe }}  # only after explicit sanitization; include comment explaining sanitization function used

## Avoiding Debug Mode Exposure (CWE-489)
- Do not commit app.run(debug=True) or DEBUG=True in source.
- Prefer using environment variables or configuration files excluded from source control. Example pattern:
```python
import os
from flask import Flask

def create_app():
    app = Flask(__name__)
    app.config.from_mapping(
        SECRET_KEY=os.environ.get("SECRET_KEY", "dev-only-secret"),
        DEBUG=os.environ.get("FLASK_DEBUG", "0") == "1",
    )
    return app

if __name__ == "__main__":
    app = create_app()
    # For development run using: FLASK_DEBUG=1 python -m flask run
    app.run(host="127.0.0.1", port=5000, debug=app.config["DEBUG"])
```
- Recommend in CONTRIBUTING.md or developer notes: use `flask run` or a WSGI server (gunicorn/uwsgi) for production; never rely on the built-in dev server in production.

## Safe Template and Rendering Rules
- Keep Jinja2 autoescape enabled (default).
- When generating templates, do not include constructs that disable autoescape or mark user content as safe without explicit sanitization.
- If the AI tool must generate helper functions that prepare content for templates, they must be named clearly (e.g., sanitize_for_template) and documented.

## Secrets and Configuration
- Read secrets from environment variables or container secrets:
```python
import os
SECRET_KEY = os.environ.get("SECRET_KEY")
```
- Do not hard-code API keys, tokens, or passwords.

## Testing and CI Requirements (for generated changes)
- Any PR that modifies routes, template rendering, or adds OS command execution must include focused unit tests that:
  - verify validation rejects malformed or malicious input,
  - confirm templates escape content by default,
  - assert no debug-mode behavior is present.
- Run the repository vulnerability scanner in CI and block merges when new high/critical security findings are introduced.

## Examples (quick reference)
1) Safe handling for creating a post (no HTML allowed):
```python
from flask import request, abort, render_template
from markupsafe import escape

MAX_TITLE_LEN = 200
MAX_BODY_LEN = 20_000

def create_post():
    title = request.form.get("title", "")
    body = request.form.get("body", "")
    if not title or len(title) > MAX_TITLE_LEN:
        abort(400, "Invalid title")
    if len(body) > MAX_BODY_LEN:
        abort(400, "Body too long")
    # Store raw text; rely on Jinja2 autoescape when rendering
    post = {"title": title, "body": body}
    # ... save in-memory
    return render_template("post.html", post=post)
```

2) If limited HTML is allowed in the body (must use bleach):
```python
def create_post_with_html():
    raw_body = request.form.get("body", "")
    safe_body = sanitize_html(raw_body)  # see bleach example above
    post = {"title": escape(request.form.get("title", "")), "body": safe_body}
    return render_template("post.html", post=post)  # body may be marked safe in template only after sanitization
```

## Change/PR Checklist for AI-generated Edits
- No eval/exec usage on tainted data.
- No subprocess or OS command usage with unvalidated user input.
- No app.run(debug=True) or committed DEBUG flags.
- All user inputs validated and/or sanitized before use.
- All changes include tests covering validation and rendering behaviors.
- Any exception to these rules must include explicit justification and an approval step recorded in PR description.

## Developer Notes (concise)
- For local development, instruct contributors to use environment variables and the Flask CLI:
  - FLASK_APP=app.py FLASK_ENV=development flask run
- For production use WSGI servers and environment-managed secrets.
- Keep these instructions concise and enforce them via linters/CI checks where possible.

By following the rules and examples above, the AI Code Assistant tool should avoid generating the Command Injection, Debug Mode Enabled, and XSS vulnerabilities detected previously.