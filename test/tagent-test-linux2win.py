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
    ip = '192.168.209.1'
    port = '3939'
    authKey = 'ts9012501'

    pyagent = TagentClient(ip, port, authKey)

    pyagent.updateCred(authKey)

    print("INFO: test execute remote commad.")
    pyagent.execCmd('root', "dir C:\\tmp", 1)
    res = pyagent.getCmdOut("root", "dir C:\\tmp", 0)
    for i in res:
        print(i)
    pyagent.execCmdAsync("root", "dir C:\\tmp")

    print("\nINFO: test download file.")
    pyagent.download(
        'root',
        "C:\\tmp\\test\\debug_pai_asset.log.20171113",
        "/root/test",
        1)

    print("\nINFO: test download dir.")
    pyagent.download('root', "C:\\tmp\\test", "/root/", 1)

    print("\nINFO: test upload file.")
    pyagent.upload(
        'root',
        "/root/test/debug_pai_asset.log.20171113",
        "C:\\tmp\\test\\",
        1)

    print("\nINFO: test upload dir.")
    pyagent.upload('root', "/root/test", "C:\\上传测试\\", 1)

    print("\nINFO: test upload url file.")
    pyagent.upload(
        'root',
        "https://www.cpan.org/authors/id/S/SA/SALVA/Net-OpenSSH-0.75_02.tar.gz",
        "C:\\tmp\\",
        1)


if __name__ == '__main__':
    main()
