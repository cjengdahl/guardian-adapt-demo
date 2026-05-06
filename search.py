import sqlite3
from flask import Blueprint, request, render_template_string

search_bp = Blueprint("search", __name__)

TEMPLATE = """
<!DOCTYPE html>
<html>
<head><title>Search Results</title></head>
<body>
  <h1>Results for "{{ query }}"</h1>
  <ul>
    {% for row in results %}
      <li><a href="/post/{{ row[0] }}">{{ row[1] }}</a></li>
    {% endfor %}
    {% if not results %}
      <li>No posts found.</li>
    {% endif %}
  </ul>
  <a href="/">Back</a>
</body>
</html>
"""


def get_db():
    conn = sqlite3.connect("blog.db")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY, title TEXT, body TEXT)"
    )
    return conn


@search_bp.route("/search")
def search():
    query = request.args.get("q", "")
    conn = get_db()
    # SQL injection: user input concatenated directly into query string
    results = conn.execute(
        f"SELECT id, title FROM posts WHERE title LIKE '%{query}%' OR body LIKE '%{query}%'"
    ).fetchall()
    conn.close()
    return render_template_string(TEMPLATE, query=query, results=results)
