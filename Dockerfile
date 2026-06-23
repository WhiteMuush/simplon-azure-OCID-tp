FROM python:3.14-slim

# Create app directory
WORKDIR /app

# Install app dependencies
COPY requirements.txt ./
COPY pylock.toml ./

RUN pip install -r requirements.txt

COPY data/ ./app/data
COPY app.py ./

EXPOSE 8080

VOLUME ["/app/data"]

CMD [ "python", "app.py", "--host 0.0.0.0 --port 8080" ]