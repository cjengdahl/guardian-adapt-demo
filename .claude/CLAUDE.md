# AI Code Assistant — Project Instructions & Security Policies

- Review and enforce safe command execution patterns; disallow shell execution with untrusted input.
- Ensure debug mode is never hard-coded to True; require environment-controlled debug settings and runtime checks.
- Enforce safe template rendering and input sanitization to prevent XSS; avoid use of |safe/Markup on user data.
- Require secrets in environment variables only; forbid credentials in source and logs.
- Add CI/pre-commit checks and unit tests to detect Command Injection, Debug True, and XSS patterns before merge.

## Overview

This file provides concise, actionable rules and examples for the AI Code Assistant tool to generate secure Flask application code for this repository (simple in-memory blog). It replaces/augments prior guidance so the scanner-detected vulnerabilities (Command Injection, Debug Mode Enabled, XSS) are prevented in future generated code.

## High-level Constraints for Generated Code

- Never generate code that uses eval(), exec(), or similar dynamic code execution on untrusted input.
- Never call os.system() or subprocess.run(..., shell=True) with user-supplied data.
- Do not set app.run(debug=True) anywhere in source. Debug mode must be controlled via environment variables and default to disabled.
- Always rely on Jinja2 auto-escaping for HTML; never mark user content as safe unless explicitly sanitized and justified.
- Use environment variables for runtime configuration and secrets; never embed credentials in source or example code.
- Validate and sanitize all user-supplied input (query params, form data, path components) before use.

## Command Execution & Injection (CWE-78)

Policy:
- Generated code must not execute shell commands with untrusted input. If a feature legitimately requires running an OS command, require:
  - A whitelisted set of allowed commands or actions (mapping to internal functions).
  - Strong validation/normalization of inputs (whitelist or strict regex).
  - Use of subprocess without shell=True and with argument lists.
  - Prefer native Python libraries to perform actions rather than launching external commands.

Safe patterns (examples):

- Avoid this (vulnerable):
```python
# DO NOT generate
import os
cmd = request.args.get('cmd')
os.system(cmd)  # command injection
```

- Preferred safe alternative (whitelist mapping):
```python
# Safe: map requested action to an internal function
ALLOWED_ACTIONS = {
    'reindex': lambda: rebuild_index(),
    'status': lambda: check_status(),
}

action = request.args.get('action')
if action not in ALLOWED_ACTIONS:
    abort(400)
result = ALLOWED_ACTIONS[action]()  # no shell execution, controlled mapping
```

- If subprocess is required:
```python
# Safe: no shell, validated args
import subprocess

def run_safe_ls(path):
    # Validate path: only allow within data directory
    from pathlib import Path
    base = Path('/var/www/data').resolve()
    target = (base / path).resolve()
    if not str(target).startswith(str(base)):
        raise ValueError('invalid path')
    subprocess.run(['ls', '-la', str(target)], check=True)  # no shell=True
```

- If quoting is necessary and building command strings must be used (discouraged), use shlex.quote and still prefer whitelists:
```python
import shlex
safe_arg = shlex.quote(user_input)  # still prefer avoiding shell usage
```

## Debug Mode and Runtime Configuration (CWE-489)

Policy:
- Never hard-code debug=True. Generated code must:
  - Default to debug disabled.
  - Read debug mode from environment variables only (e.g., FLASK_DEBUG or FLASK_ENV), and treat any production environment as non-debug.
  - Include a runtime assertion to prevent starting with debug enabled in production.

Recommended pattern:
```python
import os
from flask import Flask

app = Flask(__name__)
# Other app config...

def is_debug_enabled():
    # Only enable debug if explicit env var set to "1" and FLASK_ENV is not "production"
    return os.environ.get('FLASK_DEBUG') == '1' and os.environ.get('FLASK_ENV') != 'production'

if __name__ == '__main__':
    debug = is_debug_enabled()
    if os.environ.get('FLASK_ENV') == 'production' and debug:
        raise RuntimeError('Refusing to run in debug mode in production')
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=debug)
```

Additional guidance:
- For production deployments, instruct maintainers to use a WSGI server (gunicorn/uwsgi) and not rely on Flask's development server.
- Include CI checks (see CI section) to fail if any source file contains app.run(debug=True) or if FLASK_DEBUG is hard-coded.

## Template Rendering and XSS (CWE-79)

Policy:
- Use Jinja2 autoescape for all HTML templates (Flask does this by default). Do not call Markup, |safe, or otherwise disable escaping for user content unless explicitly sanitized.
- When building HTML programmatically, use flask.escape() for any user content.
- Provide a sanitization step for user-submitted rich text using a whitelist-based sanitizer (e.g., bleach) if the application must allow HTML input.
- Add HTTP response headers to mitigate XSS.

Safe usage examples:

- Rely on template autoescape (preferred):
```html
<!-- templates/post.html -->
<h1>{{ post.title }}</h1>
<p>{{ post.body }}</p>  <!-- autoescaped by Jinja2 -->
```

- Programmatic escaping:
```python
from flask import escape, render_template

@app.route('/post/<int:post_id>')
def show_post(post_id):
    post = get_post(post_id)
    # If rendering outside templates:
    safe_title = escape(post['title'])
    return render_template('post.html', post=post)
```

- Allowing sanitized HTML (use bleach):
```python
import bleach

ALLOWED_TAGS = ['b', 'i', 'em', 'strong', 'a', 'p', 'ul', 'li']
ALLOWED_ATTRS = {'a': ['href', 'rel', 'target']}

def sanitize_html(user_html):
    return bleach.clean(user_html, tags=ALLOWED_TAGS, attributes=ALLOWED_ATTRS, strip=True)
```

- Security headers (example middleware):
```python
@app.after_request
def set_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    # CSP should be tuned for the application; keep it strict by default
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; object-src 'none';"
    response.headers['X-XSS-Protection'] = '1; mode=block'
    return response
```

Guidelines for AI Code Assistant:
- If a user requests generation of rich-text features, generate sanitization code and unit tests demonstrating that unsafe tags/attributes are stripped.
- Warn (in comments) when generation includes any use of |safe or Markup, and require an explicit justification and a sanitization step.

## Input Validation & Parameter Handling

Policy:
- Always validate route parameters and form fields:
  - For numeric IDs use type converters in routes (e.g., <int:post_id>).
  - For filenames or paths restrict characters and ensure path traversal is prevented via pathlib.Path.resolve and base-directory checks.
  - For free text enforce length limits and character restrictions as appropriate.
- Prefer whitelisting over blacklisting.

Example validations:
```python
from flask import abort, request
import re

def validate_username(name):
    if not name or len(name) > 50:
        abort(400)
    if not re.match(r'^[A-Za-z0-9_ -]+$', name):
        abort(400)
    return name
```

## Secrets and Environment Variables

Policy:
- Do not hard-code secrets, API keys, or credentials. Use environment variables and a library like python-dotenv for development only.
- Never log secrets or sensitive tokens.

Example:
```python
import os
SECRET_KEY = os.environ.get('SECRET_KEY')
if not SECRET_KEY:
    raise RuntimeError('SECRET_KEY must be set in environment')
app.config['SECRET_KEY'] = SECRET_KEY
```

## CI, Pre-commit Hooks, and Static Checks

Policy:
- AI-generated changes must include or be accompanied by CI checks that scan for:
  - Instances of os.system, subprocess.* with shell=True, eval, exec.
  - app.run(debug=True) or debug hard-coded.
  - Template usage of |safe or Markup on variables coming from request/form.
- Recommended tools: flake8, bandit (security scanner), or a custom grep-based check in CI.

Example GitHub Actions snippet (minimal):
```yaml
name: Security Scan
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install
        run: pip install bandit
      - name: Bandit scan
        run: bandit -r .
      - name: Grep checks
        run: |
          grep -nR "app.run(debug=True)" || true
          grep -nR -E "os\.system|exec\(|eval\(" || true
```
(Adjust to fail on matches in your CI configuration.)

Pre-commit example (pre-commit config snippet):
```yaml
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.0.1
  hooks:
    - id: trailing-whitespace
- repo: local
  hooks:
    - id: security-checks
      name: security-checks
      entry: bash -c "grep -R --line-number -E 'app.run\\(debug=True\\)|os\\.system|exec\\(|eval\\(' || true"
      language: system
      always_run: true
```

## Testing & Verification

Policy:
- Generated code must be accompanied by unit tests that validate:
  - Input validation logic (boundary cases, invalid inputs).
  - That sanitization strips dangerous HTML and scripts.
  - That command-execution paths do not accept arbitrary input (use mocks for subprocess).
- Include a test that asserts debug mode is disabled by default and cannot be started in production.

Example tests (pytest style):
```python
def test_sanitize_html():
    unsafe = '<script>alert(1)</script><b>ok</b>'
    clean = sanitize_html(unsafe)
    assert '<script>' not in clean
    assert '<b>ok</b>' in clean
```

## Guidance for the AI Code Assistant (Generation Rules)

When generating code or completing PRs, follow these mandatory steps:
1. If the requested change touches any code that could invoke shell/OS commands, prompt the user for justification and require a whitelist-based design; generate safe alternatives by default.
2. For any Flask run configuration, generate environment-variable driven debug settings and runtime asserts preventing debug in production.
3. For templates and any user-rendered content, default to autoescaped templates; if asked to render raw HTML, require use of a sanitizer (e.g., bleach) and include tests.
4. Avoid using |safe, Markup, eval, exec, os.system, subprocess(..., shell=True) in generated code. If absolutely required, include explicit safety checks, whitelists, and inline comments explaining why and how the code is safe.
5. Add or update CI configuration to detect the three classes of issues (Command Injection, Debug True, XSS) and fail PRs containing them.
6. Add unit tests for critical sanitization/validation logic and for asserting debug mode is off by default.

## Minimal Example: Safe app.run + sanitizer + headers

```python
# app.py (excerpt)
import os
from flask import Flask, request, render_template, escape, abort
import bleach

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY') or 'dev-placeholder'
# Sanitization config
ALLOWED_TAGS = ['b', 'i', 'em', 'strong', 'a', 'p', 'ul', 'li']
ALLOWED_ATTRS = {'a': ['href', 'rel', 'target']}

def sanitize_html(user_html):
    return bleach.clean(user_html or '', tags=ALLOWED_TAGS, attributes=ALLOWED_ATTRS, strip=True)

@app.after_request
def set_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self';"
    response.headers['X-XSS-Protection'] = '1; mode=block'
    return response

@app.route('/create', methods=['POST'])
def create_post():
    title = request.form.get('title', '')[:200]
    body = request.form.get('body', '')
    # sanitize user-submitted HTML body
    safe_body = sanitize_html(body)
    # store safe_body, never raw body
    posts.append({'title': title, 'body': safe_body})
    return render_template('index.html', posts=posts)

def is_debug_enabled():
    return os.environ.get('FLASK_DEBUG') == '1' and os.environ.get('FLASK_ENV') != 'production'

if __name__ == '__main__':
    debug = is_debug_enabled()
    if os.environ.get('FLASK_ENV') == 'production' and debug:
        raise RuntimeError('Refusing to run in debug mode in production')
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=debug)
```

## Summary of Must-Follow Rules for AI Code Assistant Outputs

- Disallow unsafe command execution patterns; prefer internal mappings and subprocess without shell.
- Never hard-code debug=True; use env-driven debug with production safeguards.
- Preserve Jinja2 autoescape; sanitize any allowed HTML with a whitelist sanitizer (bleach).
- Use environment variables for secrets and configuration; avoid logging secrets.
- Include CI/pre-commit and tests to detect regressions for Command Injection, Debug True, and XSS.

Adhere to these rules on every generation and provide brief inline comments in generated code explaining the security rationale where appropriate.