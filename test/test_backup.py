import pytest
from time import sleep
from subprocess import check_call, check_output
import smtplib

from settings import *
from common import random_id
from test_mail import new_message, check_imap_received


def test_backup_mail():
    # send a mail, to ensure we have something to backup
    msg, subject = new_message(TEST_ADDRESS, TEST_ADDRESS)
    s = smtplib.SMTP(TEST_DOMAIN, 587)
    s.starttls()
    s.login(TEST_ADDRESS, TEST_PASSWORD)
    s.sendmail(TEST_ADDRESS, [TEST_ADDRESS], msg)
    s.quit()
    
    # trigger a backup
    sleep(2)
    cmd_ssh = "sshpass -p vagrant ssh vagrant@{} -p {} ".format(TEST_SERVER, TEST_PORT)
    cmd_count = cmd_ssh + "ls -l /home/user-data/backup/encrypted | wc -l"
    num_backup_files = int(check_output(cmd_count, shell=True))
    cmd = cmd_ssh + "sudo /vagrant/management/backup.py"
    check_call(cmd, shell=True)
    num_backup_files_new = int(check_output(cmd_count, shell=True))
    assert num_backup_files_new > num_backup_files
    
    # delete mail
    assert check_imap_received(subject)
    assert not check_imap_received(subject)
    
    # restore backup
    path = "/home/user-data"
    passphrase = "export PASSPHRASE=\$(sudo cat /home/user-data/backup/secret_key.txt) &&"
    # extract to temp directory
    restore = "sudo -E duplicity restore --force file://{0}/backup/encrypted {0}/restore &&".format(path)
    # move restored backup using rsync, because it allows to overwrite files
    move = "sudo rsync -av {0}/restore/* {0}/ &&".format(path)
    rm = "sudo rm -rf {0}/restore/".format(path)
    check_call(cmd_ssh + "\"" + passphrase + restore + move + rm + "\"", shell=True)
    
    # check the mail is there again
    assert check_imap_received(subject)
