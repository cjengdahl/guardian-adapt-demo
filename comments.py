from flask import Blueprint, request, redirect, Markup, render_template_string

comments_bp = Blueprint("comments", __name__)

comments = []

TEMPLATE = """
<!DOCTYPE html>
<html>
<head><title>Comments</title></head>
<body>
  <h1>Comments</h1>
  <ul>
    {% for c in comments %}
      <li><strong>{{ c.author }}</strong>: {{ c.body }}</li>
    {% endfor %}
    {% if not comments %}
      <li>No comments yet.</li>
    {% endif %}
  </ul>
  <h2>Leave a Comment</h2>
  <form method="POST" action="/comments">
    <input name="author" placeholder="Your name" /><br/>
    <textarea name="body" placeholder="Your comment"></textarea><br/>
    <button type="submit">Submit</button>
  </form>
  <a href="/">Back</a>
</body>
</html>
"""


@comments_bp.route("/comments", methods=["GET", "POST"])
def comments_view():
    if request.method == "POST":
        author = request.form.get("author", "Anonymous")
        body = request.form.get("body", "")
        comments.append({
            "author": author,
            # XSS: user-supplied HTML marked safe, bypassing Jinja2 autoescape
            "body": Markup(body),
        })
        return redirect("/comments")
    return render_template_string(TEMPLATE, comments=comments)
