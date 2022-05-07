#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import sys
sys.path.append('../lib')
from TagentClient import *

AUTH_KEY = 'techsure901'


def main():
    ip = '127.0.0.1'
    port = '3939'
    authKey = 'ts9012501'

    pyagent = TagentClient(ip, port, authKey)
    pyagent.updateCred(authKey)

    pyagent.reload()

    print("INFO: test execute remote commad.")
    pyagent.execCmd('root', "ls -l /tmp", 1)
    res = pyagent.getCmdOut("root", "ls -l /tmp/test", 0)
    for i in res:
        print(i)
    pyagent.execCmdAsync("root", "ls -l /tmp")

    print("\nINFO: test download.")
    pyagent.download(
        'root',
        "tmp/VMwareTools-10.0.6-3595377.tar.gz",
        "/root",
        1)
    # pyagent.download('root', "tmp/debug_pai_asset.log.20171113", "/root", 1)

    print("\nINFO: test download dir.")
    pyagent.download('root', "/tmp/test", "/root/", 1)

    print("\nINFO: test upload file.")
    pyagent.download(
        "root",
        "/root/test/debug_pai_asset.log.20171113",
        "/tmp/test2/",
        1)

    print("\nINFO: test upload dir.")
    pyagent.upload("root", "/root/test", "/app/", 1)

    print("\nINFO: test upload url file.")
    pyagent.upload(
        'root',
        "https://www.cpan.org/authors/id/S/SA/SALVA/Net-OpenSSH-0.75_02.tar.gz",
        "/root/test/",
        1)


if __name__ == '__main__':
    main()
