# Project Overview

This is a Flask web application — a simple blog that supports creating, viewing, and deleting posts.

## Stack

- **Backend**: Python 3, Flask
- **Templating**: Jinja2 (via Flask's `render_template`)
- **Frontend**: Static HTML/CSS served from `static/` and `templates/`
- **No database**: Posts are stored in memory at runtime

## Key Files

- `app.py` — all route definitions and app logic
- `templates/` — Jinja2 HTML templates
- `static/` — CSS and other static assets
- `requirements.txt` — Python dependencies

## Security Expectations

- User input from forms must never be rendered unescaped; rely on Jinja2 autoescape
- Avoid `eval`, `exec`, or `os.system` with any user-supplied data
- Do not expose debug mode (`app.run(debug=True)`) in production
- Validate and sanitize all route parameters before use
- Avoid storing secrets or credentials in source code; use environment variables

## Development Notes

- Install dependencies: `pip install -r requirements.txt`
- Run locally: `python app.py`
- The app runs on `http://localhost:5000` by default
