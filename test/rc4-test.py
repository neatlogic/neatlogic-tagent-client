#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright  2017 TechSure<http://www.techsure.com.cn/>
"""
import binascii
import sys

py_version = sys.version_info.major


def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = []
    for char in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        out.append(chr(ord(char) ^ box[(box[x] + box[y]) % 256]))
    return ''.join(out)


def _rc4_encrypt_hex(key, data):
    if py_version == 2:
        return binascii.hexlify(_rc4(key, data))
    elif py_version == 3:
        return binascii.hexlify(_rc4(key, data).encode('latin-1')).decode()


def _rc4_decrypt_hex(key, data):
    if py_version == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif py_version == 3:
        return _rc4(key, binascii.unhexlify(data).decode('latin-1'))


def main():
    passphrase = 'ts9012501'
    plaintext = '9336,5577'
    encrypted = _rc4_encrypt_hex(passphrase, plaintext)
    decrypted = _rc4_decrypt_hex(passphrase, encrypted)
    print("plain test: {0}\nafter encrypt: {1}\nafter decrypt: {2}".format(plaintext, encrypted, decrypted))


if __name__ == '__main__':
    main()
