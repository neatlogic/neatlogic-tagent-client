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

    # pyagent.updateCred(authKey)

    print("\nINFO: test download.")
    pyagent.download(
        'root',
        "tmp/VMwareTools-10.0.6-3595377.tar.gz",
        "/root",
        1)

    print("\nINFO: test download dir.");
    pyagent.download('root', "/tmp/test", "/root/", 1)

    print("\nINFO: test upload file.")
    pyagent.upload(
        "root",
        "/root/test/debug_pai_asset.log.20171113",
        "/tmp/test2/",
        1)

    print("\nINFO: test upload dir.")
    pyagent.upload("root", "/root/test", "/app/", 1)


if __name__ == '__main__':
    main()
