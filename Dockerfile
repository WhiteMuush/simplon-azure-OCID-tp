FROM python:3.12.3

# Create app directory
WORKDIR /app

# Install app dependencies
COPY requirements.txt ./

RUN pip install -r requirements.txt

COPY data/ ./app/data
COPY app.py ./

EXPOSE 8080

VOLUME ["/app/data"]

CMD [ "python", "app.py", "host=0.0.0.0", "port=8080" ]