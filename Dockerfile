FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# wizexercise.txt will be copied in root path by COPY . .
# Since we set WORKDIR to /app, the file ends up at /app/wizexercise.txt
# To have it in root path, we copy it explicitly:
COPY wizexercise.txt /

EXPOSE 5000

CMD ["python", "app.py"]