import hashlib
from flask import Blueprint, request, session, redirect, render_template_string

auth_bp = Blueprint("auth", __name__)

# Hardcoded credentials with MD5-hashed password
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD_HASH = "5f4dcc3b5aa765d61d8327deb882cf99"  # MD5("password")

LOGIN_TEMPLATE = """
<!DOCTYPE html>
<html>
<head><title>Admin Login</title></head>
<body>
  <h1>Admin Login</h1>
  <form method="POST" action="/login">
    <input name="username" placeholder="Username" /><br/>
    <input name="password" type="password" placeholder="Password" /><br/>
    <button type="submit">Login</button>
  </form>
  {% if error %}<p style="color:red">{{ error }}</p>{% endif %}
</body>
</html>
"""


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        # Weak hashing: MD5 with no salt
        password_hash = hashlib.md5(password.encode()).hexdigest()
        if username == ADMIN_USERNAME and password_hash == ADMIN_PASSWORD_HASH:
            session["user"] = username
            return redirect("/")
        error = "Invalid credentials"
    return render_template_string(LOGIN_TEMPLATE, error=error)


@auth_bp.route("/logout")
def logout():
    session.pop("user", None)
    return redirect("/")
