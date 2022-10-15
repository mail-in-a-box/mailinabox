from daemon import app
import auth, utils, logging

app.logger.addHandler(utils.create_syslog_handler())

logging_level = logging.DEBUG
logging.basicConfig(level=logging_level, format='MiaB %(levelname)s:%(module)s.%(funcName)s %(message)s')
logging.info('Logging level set to %s', logging.getLevelName(logging_level))
        
if __name__ == "__main__":
    app.run(port=10222)