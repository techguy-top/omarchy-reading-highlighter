"""Local, opt-in traced-word OCR. JSON-lines protocol; never executes shell text."""
import csv
import datetime
import fcntl
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

from PIL import Image, ImageOps
from gi.repository import Gio, GLib
from pointer import query

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'reading-highlighter/settings.json'
DEFAULT = str(Path.home() / 'Documents/Reading Highlights.md')


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def apps():
    result = []
    for app in Gio.AppInfo.get_all_for_type('text/plain'):
        if app.get_id() and app.supports_files() and app.should_show():
            result.append({'value': app.get_id(), 'label': app.get_display_name()[:120]})
    return sorted(result, key=lambda a: a['label'].casefold())[:100]


def file_path(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 4096 or any(ord(c) < 32 for c in value):
        raise ValueError('Choose a folder, or enter a notes filename such as ~/Documents/Reading Highlights.md.')
    value = value.strip()
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path.home() / 'Documents' / path
    if path.is_dir() or value.endswith('/'):
        path = path / 'Reading Highlights.md'
    elif not path.suffix:
        path = path.with_suffix('.md')
    if path.suffix.lower() not in ('.md', '.txt'):
        raise ValueError('Use a .md or .txt notes file, or choose a folder. A filename without an extension gets .md automatically.')
    if path.exists() and not path.is_file():
        raise ValueError('Choose a regular notes file or a folder.')
    return path


def open_folder(settings):
    path = file_path(settings['file']).parent
    if not path.is_dir():
        raise ValueError('This folder does not exist yet. Save a capture first, or choose an existing folder.')
    notes = file_path(settings['file'])
    if notes.is_file():
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            bus.call_sync('org.freedesktop.FileManager1', '/org/freedesktop/FileManager1',
                          'org.freedesktop.FileManager1', 'ShowItems',
                          GLib.Variant('(ass)', ([notes.as_uri()], '')), None,
                          Gio.DBusCallFlags.NONE, 3000, None)
            return
        except GLib.Error:
            pass
    Gio.AppInfo.launch_default_for_uri(path.as_uri(), None)


def load_settings():
    defaults = {'file': DEFAULT, 'app': '', 'autoOpen': False}
    try:
        if CONFIG.stat().st_size <= 16384:
            data = json.loads(CONFIG.read_text())
            defaults['file'] = str(file_path(data.get('file', DEFAULT)))
            defaults['app'] = str(data.get('app', ''))[:256]
            defaults['autoOpen'] = data.get('autoOpen') is True
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return defaults


def save_settings(data, available):
    settings = {'file': str(file_path(data.get('file'))), 'app': data.get('app', ''),
                'autoOpen': data.get('autoOpen') is True}
    if settings['app'] not in [''] + [a['value'] for a in available]:
        raise ValueError('Choose an app from the installed text-file apps.')
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    temp = CONFIG.with_suffix('.tmp')
    temp.write_text(json.dumps(settings, indent=2) + '\n')
    temp.replace(CONFIG)
    return settings


def open_file(settings):
    path = file_path(settings['file'])
    if not path.is_file():
        raise ValueError('Capture some text before opening the notes file.')
    if settings['app']:
        app = Gio.DesktopAppInfo.new(settings['app'])
        if app is None:
            raise ValueError('The selected app is no longer installed.')
        app.launch([Gio.File.new_for_path(str(path))], None)
    else:
        Gio.AppInfo.launch_default_for_uri(path.as_uri(), None)


def logical_size(m):
    w, h = m['width'], m['height']
    if m.get('transform', 0) % 2:
        w, h = h, w
    return round(w / m['scale']), round(h / m['scale'])


def snapshot():
    cursor = query('j/cursorpos')
    for m in query('j/monitors'):
        w, h = logical_size(m)
        if m['x'] <= cursor['x'] < m['x'] + w and m['y'] <= cursor['y'] < m['y'] + h:
            raw = subprocess.run(['grim', '-o', m['name'], '-s', '1', '-'],
                                 check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5).stdout
            image = Image.open(io.BytesIO(raw)).convert('RGB')
            if image.size != (w, h):
                image = image.resize((w, h), Image.Resampling.LANCZOS)
            return {'monitor': m, 'image': image, 'started': time.monotonic()}
    raise ValueError('No monitor found under the pointer.')


def segment_hits_box(a, b, box):
    """Liang-Barsky segment intersection with an expanded word rectangle."""
    left, top, right, bottom = box
    dx, dy = b[0] - a[0], b[1] - a[1]
    low, high = 0.0, 1.0
    for p, q in ((-dx, a[0]-left), (dx, right-a[0]), (-dy, a[1]-top), (dy, bottom-a[1])):
        if p == 0:
            if q < 0:
                return False
        else:
            r = q / p
            if p < 0:
                low = max(low, r)
            else:
                high = min(high, r)
            if low > high:
                return False
    return True


def selected_text(tsv, points, origin, factor=2):
    lines = {}
    segments = list(zip(points, points[1:])) or [(points[0], points[0])]
    for row in csv.DictReader(io.StringIO(tsv), delimiter='\t', quoting=csv.QUOTE_NONE):
        if row.get('level') != '5' or not row.get('text', '').strip():
            continue
        x = int(row['left']) / factor + origin[0]
        y = int(row['top']) / factor + origin[1]
        w, h = int(row['width']) / factor, int(row['height']) / factor
        # Nine logical pixels either side matches the visible 18px marker.
        box = (x-9, y-9, x+w+9, y+h+9)
        if any(segment_hits_box(a, b, box) for a, b in segments):
            key = tuple(row[k] for k in ('page_num', 'block_num', 'par_num', 'line_num'))
            lines.setdefault(key, []).append(row['text'].strip())
    return '\n'.join(' '.join(words) for words in lines.values())[:100000]


def recognize(capture, raw_points):
    if time.monotonic() - capture['started'] > 125:
        raise ValueError('Capture expired. Keep each trace under two minutes.')
    if not isinstance(raw_points, list) or not 2 <= len(raw_points) <= 4000:
        raise ValueError('Trace across some words before releasing the shortcut.')
    m, image = capture['monitor'], capture['image']
    points = []
    for p in raw_points:
        x, y = float(p['x']) - m['x'], float(p['y']) - m['y']
        if not math.isfinite(x) or not math.isfinite(y) or not (0 <= x < image.width and 0 <= y < image.height):
            raise ValueError('Keep each capture on the monitor where you started.')
        points.append((x, y))
    left = max(0, int(min(p[0] for p in points)) - 36)
    top = max(0, int(min(p[1] for p in points)) - 36)
    right = min(image.width, math.ceil(max(p[0] for p in points)) + 36)
    bottom = min(image.height, math.ceil(max(p[1] for p in points)) + 36)
    crop = ImageOps.grayscale(image.crop((left, top, right, bottom)))
    crop = ImageOps.autocontrast(crop)
    if crop.resize((1, 1)).getpixel((0, 0)) < 128:
        crop = ImageOps.invert(crop)
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    crop.save(buf, format='PNG')
    languages = os.environ.get('OMARCHY_OCR_LANGS', 'eng')
    if len(languages) > 100 or not all(c.isalnum() or c in '_+-' for c in languages):
        languages = 'eng'
    env = dict(os.environ, OMP_THREAD_LIMIT='2')
    result = subprocess.run(['tesseract', 'stdin', 'stdout', '-l', languages, '--psm', '11', 'tsv'],
                            input=buf.getvalue(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=30, check=True, env=env)
    if len(result.stdout) > 4_000_000:
        raise ValueError('Too much text in this capture. Try a smaller trace.')
    text = selected_text(result.stdout.decode('utf-8', errors='replace'), points, (left, top))
    if not text.strip():
        raise ValueError('No text found along the trace. Move through the middle of the words and try again.')
    return text


def append_text(path, text):
    path = file_path(str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')
    heading = f'\n\n## {timestamp}\n\n' if path.suffix.lower() == '.md' else f'\n\n[{timestamp}]\n\n'
    with path.open('a', encoding='utf-8') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.write(heading + text.strip() + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def main():
    available = apps()
    settings = load_settings()
    capture = None
    emit(event='settings', settings=settings, apps=available)
    while line := sys.stdin.readline(1_000_001):
        try:
            if len(line) > 1_000_000:
                raise ValueError('Capture message is too large.')
            data = json.loads(line)
            action = data.get('action')
            if action == 'start':
                capture = snapshot()
                emit(event='ready', monitor=capture['monitor']['name'])
            elif action == 'cancel':
                capture = None
                emit(event='cancelled')
            elif action == 'finish':
                current, capture = capture, None
                if current is None:
                    raise ValueError('No capture is in progress.')
                try:
                    text = recognize(current, data.get('points'))
                finally:
                    current = None
                append_text(settings['file'], text)
                emit(event='saved', preview=text[:1000], file=settings['file'])
                if settings['autoOpen']:
                    try:
                        open_file(settings)
                    except Exception as exc:
                        emit(event='openError', message=str(exc)[:500])
            elif action == 'settings':
                settings = save_settings(data, available)
                emit(event='settings', settings=settings, apps=available)
            elif action == 'folder':
                open_folder(settings)
                emit(event='opened')
            elif action == 'open':
                open_file(settings)
                emit(event='opened')
        except Exception as exc:
            capture = None
            message = str(exc)[:500]
            if isinstance(exc, subprocess.CalledProcessError):
                message = (exc.stderr or b'Capture command failed').decode(errors='replace')[:500]
            emit(event='error', message=message)


if __name__ == '__main__':
    main()
