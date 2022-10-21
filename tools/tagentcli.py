#!/usr/bin/python3
import os
import argparse
import getpass
import re
import TagentClient


def usage():
    pname = os.path.basename(__file__)
    print("Usage: {} [-v|--verbose] [-h|--host] <host> -u <user> -p <port> -P <password> [-b|--binary] [-a|--action] [exec|upload|download|writefile|reload] <args ...>\n".format(pname))
    exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--verbose',  '-v', action='store_true', default=False, help='Verbose output')
    parser.add_argument('--binary',   '-b', action='store_true', default=False, help='Data is binary')
    parser.add_argument('--host',      default='127.0.0.1',  help='Host')
    parser.add_argument('--port',     '-p', default='3939',  help='Port')
    parser.add_argument('--password', '-P', default='',  help='Password')
    parser.add_argument('--user',     '-u', default='root',  help='User name')
    parser.add_argument('--action',   '-a', default='exec',  help='Actions:exec|upload|download|writefile|reload')
    parser.add_argument('rest',       nargs=argparse.REMAINDER)
    args = parser.parse_args()
    restArgs = args.rest

    host = args.host
    port = int(args.port)
    password = args.password
    action = args.action
    user = args.user

    if not host or not port or action not in ('exec', 'upload', 'download', 'writefile', 'reload', 'transfer'):
        usage()

    convertCharset = 1
    if args.binary:
        convertCharset = 0

    if not password:
        password = getpass.getpass("Enter tagent password:")

    isVerbose = 0
    if args.verbose:
        isVerbose = 1

    tagent = TagentClient.TagentClient(host, port, password, readTimeout=360, writeTimeout=10)
    if not tagent:
        exit(1)

    status = 0
    if action == 'exec':
        cmd = ' '.join(restArgs)
        status = tagent.execCmd(user, cmd, isVerbose)
    elif action == 'upload':
        argsLen = len(restArgs)
        if argsLen == 2:
            status = tagent.upload(user, restArgs[0], restArgs[1], isVerbose, convertCharset)
        elif argsLen == 3:
            status = tagent.upload(user, restArgs[0], restArgs[1], isVerbose, convertCharset, restArgs[2])
        else:
            print("ERROR: upload must has only two or three argument.\n")
            print("Example: upload /tmp/test /home/app/\n")
            print("Example(follow links): upload /tmp/test /home/app/ 1\n")
            exit(-1)
    elif action == 'download':
        argsLen = len(restArgs)
        if argsLen == 2:
            status = tagent.download(user, restArgs[0], restArgs[1], isVerbose, 0, convertCharset=convertCharset)
        elif argsLen == 3:
            status = tagent.download(user, restArgs[0], restArgs[1], isVerbose, restArgs[2], convertCharset=convertCharset)
        else:
            print("ERROR: download must has only two or three argument.\n")
            print("Example: download /tmp/test /home/app/\n")
            print("Example(follow links): download /tmp/test /home/app/ 1\n")
            exit(-1)
    elif action == 'writefile':
        argsLen = len(restArgs)
        if argsLen != 2:
            print("ERROR: writefile must has only two argument.\n")
            print("Example: /home/app/test 'the file content'\n")
            exit(-1)
        status = tagent.writeFile(user, restArgs[1], restArgs[0], isVerbose, convertCharset)
    elif action == 'transfer':
        argsLen = len(restArgs)
        if argsLen != 2:
            print("ERROR: tranfer must has two argument.\n")
            print("Example: myuser/mypassword@192.168.0.100:3939:/tmp/test  /tmp\n")
            exit(-1)

        followLinks = 0
        if argsLen > 2:
            followLinks = restArgs[1]

        dest = restArgs[1]
        srcHost = None
        srcPort = 3939
        srcUser = 'root'
        srcPasswd = ''
        src = ''
        (userAndPass, srcDirDef) = restArgs[0].split('@', 1)

        if srcDirDef is None:
            print("ERROR: Invalid parameter $args[0]\n")
            print("Example: myuser/mypassword@192.168.0.100:3939:/tmp/test\n")
            exit(-1)

        (srcUser, srcPassword) = userAndPass.split('/', 1)

        match = re.match('^([^:]+):(\\d+):(.*)$', srcDirDef)

        if match:
            srcHost = match.group(1)
            srcPort = match.group(2)
            src = match.group(3)
        else:
            match = re.match('^([^:]+):(.*)$', srcDirDef)
            if match:
                srcHost = match.group(1)
                src = match.group(2)
            else:
                print("ERROR: Invalid parameter $args[0]\n")
                print("Example: myuser/mypassword@192.168.0.100:3939:/tmp/test\n")
                exit(-1)

        status = tagent.transFile(srcHost, srcPort, srcUser, srcPassword, src, user, dest, isVerbose, followLinks)

    elif action == 'reload':
        status = tagent.reload()

    if status != 0:
        print("ERROR: execute tagent failed, exit code:{}.\n".format(status))
        exit(status)
