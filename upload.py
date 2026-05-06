import os
from flask import Blueprint, request, render_template_string

upload_bp = Blueprint("upload", __name__)

UPLOAD_DIR = "/tmp/uploads"

TEMPLATE = """
<!DOCTYPE html>
<html>
<head><title>Upload Image</title></head>
<body>
  <h1>Upload Post Image</h1>
  <form method="POST" action="/upload" enctype="multipart/form-data">
    <input type="file" name="file" /><br/><br/>
    <button type="submit">Upload</button>
  </form>
  {% if message %}<p>{{ message }}</p>{% endif %}
</body>
</html>
"""


@upload_bp.route("/upload", methods=["GET", "POST"])
def upload():
    message = None
    if request.method == "POST":
        f = request.files.get("file")
        if f:
            os.makedirs(UPLOAD_DIR, exist_ok=True)
            # No file type validation and unsanitized filename allows path traversal
            save_path = os.path.join(UPLOAD_DIR, f.filename)
            f.save(save_path)
            message = f"Uploaded to {save_path}"
    return render_template_string(TEMPLATE, message=message)
