#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
#
# Shows how long the build still needs. Soong writes its progress to
# out/build_progress.pb (BuildProgress: total_actions = 1,
# finished_actions = 2, current_actions = 3, failed_actions = 4). The speed
# is taken from the last 20 minutes, so slow phases (Java, linking) and fast
# ones (small C files) even out instead of the estimate jumping around.
#
#   noxis_eta.py <out-dir> [--every SECONDS] [--pid PID] [--once]
import os
import sys
import time


def varint(b, i):
    n = s = 0
    while True:
        x = b[i]
        i += 1
        n |= (x & 0x7F) << s
        s += 7
        if not x & 0x80:
            return n, i


def read(path):
    try:
        with open(path, "rb") as f:
            b = f.read()
    except OSError:
        return None
    fields, i = {}, 0
    try:
        while i < len(b):
            key, i = varint(b, i)
            if key & 7 != 0:          # only varints expected
                return None
            v, i = varint(b, i)
            fields[key >> 3] = v
    except IndexError:                # file is being rewritten right now
        return None
    return fields.get(1, 0), fields.get(2, 0), fields.get(4, 0)


def dur(sec):
    sec = int(sec)
    h, m = sec // 3600, sec % 3600 // 60
    return f"{h}h{m:02d}m" if h else f"{max(m, 1)}m"


def alive(pid):
    if not pid:
        return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit("usage: noxis_eta.py <out-dir> [--every S] [--pid PID] [--once]")
    path = os.path.join(a[0], "build_progress.pb")
    every = int(a[a.index("--every") + 1]) if "--every" in a else 60
    pid = int(a[a.index("--pid") + 1]) if "--pid" in a else 0
    once = "--once" in a
    hist, said_wait = [], False
    while alive(pid):
        p = read(path)
        now = time.time()
        # Soong's own bootstrap shows up as 1/2 or 2/3 steps - that is still analysis
        if p and p[0] > 50:
            total, done, failed = p
            hist.append((now, done))
            hist = [h for h in hist if now - h[0] <= 1200] or hist[-1:]
            t0, d0 = hist[0]
            pct = done * 100 // total
            line = f"[noxis] ETA: {pct}% · {done}/{total} steps"
            if now - t0 >= 120 and done > d0:
                left = (total - done) / ((done - d0) / (now - t0))
                line += f" · ~{dur(left)} left (done ~{time.strftime('%H:%M', time.localtime(now + left))})"
            else:
                line += " · measuring speed…"
            if failed:
                line += f" · {failed} failed"
            print("\r\033[K" + line, flush=True)
        elif not said_wait or once:
            print("\r\033[K[noxis] ETA: still analysing (Soong/Kati) – estimate follows once compiling starts",
                  flush=True)
            said_wait = True
        if once:
            return
        # sample often for a good speed value, print only every `every` s
        for _ in range(max(every // 10, 1)):
            time.sleep(10 if every >= 10 else every)
            if not alive(pid):
                return
            p = read(path)
            if p and p[0] > 50:
                hist.append((time.time(), p[1]))


if __name__ == "__main__":
    main()
