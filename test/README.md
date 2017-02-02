This is the mailinabox test suite. It uses the excellent pytest module to check the functionality of the different services.

# Usage

start-up a vagrant box

    vagrant up

install test requirements (using a virtualenv is highly recommended)

    pip install -r requirements.txt

run the tests

    pytest

to just run a subset of the tests (e.g. the ssh related ones):

    pytest test_ssh.py


# Contributing

pytest auto-discovers all tests in this directory. The test functions need to be named "test_..." and there needs to be at least one assert statement.
