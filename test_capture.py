import csv
import io
import json
import os
import sys
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

from PIL import Image, ImageDraw, ImageFont
import capture


class CaptureTests(unittest.TestCase):
    def test_trace_filters_words_and_line_order(self):
        header = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
        tsv = header + '\n'.join([
            '5\t1\t1\t1\t1\t1\t20\t20\t60\t20\t99\tKeep',
            '5\t1\t1\t1\t1\t2\t220\t20\t60\t20\t99\tIgnore',
            '5\t1\t1\t1\t2\t1\t20\t120\t60\t20\t99\tSecond',
        ])
        self.assertEqual(capture.selected_text(tsv, [(5,15),(35,15)], (0,0)), 'Keep')
        self.assertEqual(capture.selected_text(tsv, [(5,15),(35,15),(35,65),(5,65)], (0,0)), 'Keep\nSecond')

    def test_segment_does_not_select_untraced_bounding_box(self):
        self.assertFalse(capture.segment_hits_box((0,0),(100,100),(0,80,10,100)))
        self.assertTrue(capture.segment_hits_box((0,0),(100,100),(40,40,60,60)))
        self.assertTrue(capture.segment_hits_box((10,10),(10,10),(0,0,20,20)))

    def test_synthetic_ocr_and_append(self):
        image = Image.new('RGB', (800,220), 'white')
        font_path = subprocess.check_output(['fc-match', '-f', '%{file}', 'Liberation Sans'], text=True).strip()
        font = ImageFont.truetype(font_path, 32)
        draw = ImageDraw.Draw(image)
        draw.text((30,35), 'Reading capture works', font=font, fill='black')
        draw.text((30,135), 'Do not save this line', font=font, fill='black')
        current = {'monitor': {'x':-800,'y':50}, 'image':image, 'started':time.monotonic()}
        points = [{'x':x-800,'y':105} for x in range(30,400,3)]
        text = capture.recognize(current, points)
        self.assertEqual(text, 'Reading capture works')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'notes.md'
            capture.append_text(path, text)
            capture.append_text(path, 'Another capture')
            self.assertIn('Reading capture works', path.read_text())
            self.assertIn('Another capture', path.read_text())
            self.assertEqual(path.read_text().count('## '), 2)

    def test_markup_stays_literal_in_saved_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'notes.txt'
            text = '<img src="https://example.invalid/tracker"> & words'
            capture.append_text(path, text)
            self.assertIn(text, path.read_text())
        panel = Path(__file__).with_name('Panel.qml').read_text()
        plain = Path(__file__).with_name('PlainText.qml').read_text()
        self.assertIn('textFormat: Text.PlainText', plain)
        self.assertIn('text: TrailState.lastPreview', panel)
        self.assertNotIn('tooltipText: TrailState.', panel)

    def test_dynamic_app_labels_are_neutralized(self):
        panel = Path(__file__).with_name('Panel.qml').read_text()
        helper = panel.split('function safeLabel(value) {',1)[1].split('}',1)[0]
        result = subprocess.run(['node','-e', 'function safeLabel(value) {'+helper+'}; process.stdout.write(safeLabel(process.argv[1]))', '<img src="https://example.invalid/tracker"> & test'], check=True, capture_output=True, text=True)
        self.assertNotIn('<', result.stdout)
        self.assertNotIn('>', result.stdout)
        self.assertNotIn('&', result.stdout)

    def test_settings_persist_across_helper_restarts(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = {'action':'settings', 'file':str(Path(directory)/'notes.md'), 'app':'', 'autoOpen':True}
            env = dict(os.environ, XDG_CONFIG_HOME=directory)
            command = [sys.executable, '-B', str(Path(__file__).with_name('capture.py'))]
            result = subprocess.run(command, input=json.dumps(settings)+'\n', text=True, capture_output=True, env=env, check=True)
            messages = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(messages[-1]['settings']['file'], settings['file'])
            self.assertTrue(messages[-1]['settings']['autoOpen'])
            result = subprocess.run(command, input='', text=True, capture_output=True, env=env, check=True)
            restored = json.loads(result.stdout)['settings']
            self.assertEqual(restored['file'], settings['file'])
            self.assertTrue(restored['autoOpen'])

    def test_folder_and_simple_filename_destinations(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.assertEqual(capture.file_path(directory), folder/'Reading Highlights.md')
            self.assertEqual(capture.file_path(directory+'/new folder/'), folder/'new folder/Reading Highlights.md')
            self.assertEqual(capture.file_path(directory+'/My notes'), folder/'My notes.md')
            self.assertEqual(capture.file_path(directory+'/My notes.txt'), folder/'My notes.txt')
        self.assertEqual(capture.file_path('My reading notes'), Path.home()/'Documents/My reading notes.md')

    def test_file_validation_and_monitor_rotation(self):
        for value in ['/tmp/no.pdf', '/tmp/line\nbreak.md', '']:
            with self.assertRaises(ValueError):
                capture.file_path(value)
        self.assertEqual(capture.logical_size({'width':1920,'height':1080,'scale':1.5,'transform':1}), (720,1280))


if __name__ == '__main__':
    unittest.main()
