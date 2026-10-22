"""Materialize survey DXFs for auditors; never share their numerical oracle."""
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def survey_fixture_directory(directory=None):
    if directory is None:
        with TemporaryDirectory(prefix='fieldforge-surveys-') as temporary:
            subprocess.run([sys.executable, str(ROOT / 'scripts/generate_underground_surveys.py'),
                            '--dxf-dir', temporary], check=True, stdout=subprocess.DEVNULL)
            with survey_fixture_directory(temporary) as fixtures:
                yield fixtures
        return
    fixtures = Path(directory)
    manifest = json.loads((ROOT / 'Tests/Fixtures/underground_surveys_manifest.json').read_text())
    for level, entry in manifest.items():
        path = fixtures / f'underground_survey_{level}.dxf'
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'DXF differs from pinned manifest: {path}')
    yield fixtures
