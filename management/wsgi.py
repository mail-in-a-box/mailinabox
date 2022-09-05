from daemon import app
import utils

app.logger.addHandler(utils.create_syslog_handler())

if __name__ == "__main__":
    app.run(port=10222)