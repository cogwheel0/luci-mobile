"""Загружает APK на MEGA, проверяет SHA-256 скачанной обратно копии и печатает ссылку.

MEGA отвечает на логин HTTP 402 с вызовом X-Hashcash, который mega.py 1.0.8 решать не умеет,
поэтому requests.post в модуле mega подменён обёрткой, которая решает вызов и повторяет запрос.

После загрузки на MEGA остаются только KEEP (по умолчанию 2) последних версий LuCI-Mobile-*.apk —
текущая и предыдущая для отката.

Зависимости: pip install mega.py==1.0.8 && pip install -U "tenacity>=8".
Учётные данные — переменные MEGA_LOGIN / MEGA_PASSWORD.
Использование: python3 ci/mega_upload.py dist/LuCI-Mobile-X.Y.Z.apk
"""
import base64
import hashlib
import os
import re
import struct
import sys
import tempfile

import mega.mega as mega_mod
import requests
from mega import Mega


def solve_hashcash(challenge):
    _, easiness, _, token = challenge.split(":")
    easiness = int(easiness)
    threshold = (((easiness & 63) << 1) + 1) << ((easiness >> 6) * 7 + 3)
    body = base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)) * 262144
    n = 0
    while True:
        prefix = struct.pack(">I", n)
        if struct.unpack(">I", hashlib.sha256(prefix + body).digest()[:4])[0] <= threshold:
            return "1:%s:%s" % (token, base64.urlsafe_b64encode(prefix).decode().rstrip("="))
        n += 1


_post = requests.post


def post_with_hashcash(url, **kwargs):
    for _ in range(3):
        response = _post(url, **kwargs)
        challenge = response.headers.get("X-Hashcash")
        if response.status_code != 402 or not challenge:
            return response
        kwargs["headers"] = {**(kwargs.get("headers") or {}), "X-Hashcash": solve_hashcash(challenge)}
    return response


class _Requests:
    """Модуль requests для mega.py: всё как есть, кроме post."""
    post = staticmethod(post_with_hashcash)

    def __getattr__(self, name):
        return getattr(requests, name)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    apk = sys.argv[1]
    mega_mod.requests = _Requests()
    m = Mega().login(os.environ["MEGA_LOGIN"], os.environ["MEGA_PASSWORD"])
    link = m.get_upload_link(m.upload(apk))
    # mega.py отдаёт старый формат mega.co.nz/#!ID!KEY
    if "#!" in link:
        file_id, key = link.split("#!", 1)[1].split("!", 1)
        link = "https://mega.nz/file/%s#%s" % (file_id, key)

    expected = sha256(apk)
    with tempfile.TemporaryDirectory() as tmp:
        got = sha256(str(m.download_url(link, dest_path=tmp)))
    if got != expected:
        sys.exit("SHA-256 копии с MEGA не совпадает: %s != %s" % (got, expected))
    prune(m, int(os.environ.get("KEEP", "2")))
    print(link)


def version_key(name):
    return tuple(int(x) for x in re.findall(r"\d+", name))


def prune(m, keep):
    """Удаляет старые LuCI-Mobile-X.Y.Z.apk, оставляя keep последних версий (текущая + откат)."""
    groups = {}
    for file_id, f in m.get_files().items():
        name = (f.get("a") or {}).get("n", "") if isinstance(f.get("a"), dict) else ""
        match = re.fullmatch(r"(LuCI-Mobile)-\d+\.\d+\.\d+\.apk", name)
        if f.get("t") == 0 and match:
            groups.setdefault(match.group(1), {}).setdefault(name, []).append(file_id)
    for apks in groups.values():
        for name in sorted(apks, key=version_key, reverse=True)[keep:]:
            for file_id in apks[name]:
                m.destroy(file_id)
            print("MEGA: удалена старая версия " + name, file=sys.stderr)


if __name__ == "__main__":
    main()
