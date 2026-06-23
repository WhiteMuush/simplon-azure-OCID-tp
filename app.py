from flask import Flask, request
import os
import datetime

app = Flask(__name__)

LOG_FOLDER = './data'
LOG_FILE = f"{LOG_FOLDER}/access.log"

@app.route('/')
def home():
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    log_message = f"{request.remote_addr} - [{timestamp}] - GET / HTTP/1.1\n"
    
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(log_message)
    except Exception as e:
        return f"Internal Server Error : {str(e)}", 500
    return "Hello, world!"

@app.route('/logs')
def get_logs():
    try:
        with open(LOG_FILE, 'r') as f:
            content = f.read()
        if not content:
            return ""
        return f"<pre>{content}</pre>"
    except Exception as e:
        return f"Internal Server Error : {str(e)}", 500

if __name__ == '__main__':
    if not os.path.exists(LOG_FOLDER):
        os.makedirs(LOG_FOLDER)

    app.run(host='0.0.0.0', port=8080)
