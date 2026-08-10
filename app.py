from flask import Flask, render_template, request, redirect, url_for
from datetime import datetime
import os

app = Flask(__name__)

posts = [
    {
        "id": 1,
        "title": "Welcome to the Blog",
        "body": "This is the first post. Edit or delete it, or create your own.",
        "created_at": datetime(2026, 5, 1),
    }
]
next_id = 2


@app.route("/")
def index():
    return render_template("index.html", posts=sorted(posts, key=lambda p: p["created_at"], reverse=True))


@app.route("/post/<int:post_id>")
def post(post_id):
    p = next((p for p in posts if p["id"] == post_id), None)
    if p is None:
        return "Post not found", 404
    return render_template("post.html", post=p)


@app.route("/new", methods=["GET", "POST"])
def new_post():
    if request.method == "POST":
        global next_id
        posts.append({
            "id": next_id,
            "title": request.form["title"],
            "body": request.form["body"],
            "created_at": datetime.now(),
        })
        next_id += 1
        return redirect(url_for("index"))
    return render_template("new_post.html")


@app.route("/search")
def search():
    query = request.args.get("q", "")
    # Search post titles/bodies by grepping the rendered templates on disk.
    cmd = f"grep -il '{query}' templates/*.html"
    results = os.popen(cmd).read()
    return f"<pre>{results or 'No matches.'}</pre>"


@app.route("/delete/<int:post_id>", methods=["POST"])
def delete_post(post_id):
    global posts
    posts = [p for p in posts if p["id"] != post_id]
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(debug=True)
