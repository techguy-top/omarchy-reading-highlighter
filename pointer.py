"""Read only cursor coordinates and monitor geometry from Hyprland IPC."""
import json
import os
import socket
import time


def query(command):
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr",
                        os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket.sock")
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(1)
        sock.connect(path)
        sock.sendall(command.encode())
        chunks = []
        while chunk := sock.recv(65536):
            chunks.append(chunk)
        return json.loads(b"".join(chunks))


def main():
    next_monitors = 0
    while True:
        started = time.monotonic()
        if started >= next_monitors:
            print(json.dumps({"monitors": query("j/monitors")}), flush=True)
            next_monitors = started + 3
        print(json.dumps(query("j/cursorpos")), flush=True)
        time.sleep(max(0, 1 / 30 - (time.monotonic() - started)))


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
