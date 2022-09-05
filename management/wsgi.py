from daemon import app
import auth, utils

from werkzeug.middleware.proxy_fix import ProxyFix

app.wsgi_app = ProxyFix(
    app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1
)

env = utils.load_environment()
auth_service = auth.AuthService()

app.logger.addHandler(utils.create_syslog_handler())

if __name__ == "__main__":
    app.run(port=10222)