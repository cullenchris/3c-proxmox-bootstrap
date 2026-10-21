#!/usr/bin/env python3
"""Offline security tests for the development bootstrap archive extractor.

The test extracts the embedded Python validation block from the bootstrap
script. It never downloads files, accesses GitHub credentials or runs Proxmox.
"""
from io import BytesIO
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

BOOTSTRAP = Path(__file__).resolve().parents[1] / "bootstrap-reporting-dev.sh"
BEGIN = "python3 - \"$ARCHIVE\" \"$STAGE\" <<'PY'\n"
END = "\nPY\n"


def extraction_program():
    content = BOOTSTRAP.read_text(encoding="utf-8")
    if BEGIN not in content:
        raise ValueError("Bootstrap extractor entrypoint missing")
    block = content.split(BEGIN, 1)[1]
    if END not in block:
        raise ValueError("Bootstrap extractor terminator missing")
    return block.split(END, 1)[0]


def make_archive(path, special=None):
    with tarfile.open(path, "w:gz") as tar:
        root = tarfile.TarInfo("test-repo-abcdef/")
        root.type = tarfile.DIRTYPE
        tar.addfile(root)
        for index in range(21):
            data = f"example {index}\n".encode("utf-8")
            info = tarfile.TarInfo(f"test-repo-abcdef/test-{index:02d}.txt")
            info.size = len(data)
            tar.addfile(info, BytesIO(data))
        if special == "traversal":
            data = b"escape\n"
            info = tarfile.TarInfo("test-repo-abcdef/../escape.txt")
            info.size = len(data)
            tar.addfile(info, BytesIO(data))
        elif special == "symlink":
            info = tarfile.TarInfo("test-repo-abcdef/bad-link")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/passwd"
            tar.addfile(info)


class ArchiveSafetyTests(unittest.TestCase):
    def run_extractor(self, special=None):
        with tempfile.TemporaryDirectory() as folder:
            parent = Path(folder)
            archive = parent / "archive.tar.gz"
            output = parent / "out"
            output.mkdir()
            make_archive(archive, special)
            result = subprocess.run(
                [sys.executable, "-c", extraction_program(), str(archive), str(output)],
                capture_output=True, text=True, check=False, timeout=15,
            )
            return result.returncode, result.stdout + result.stderr, (output / "test-00.txt").exists()

    def test_valid_archive_extracts(self):
        status, message, created = self.run_extractor()
        self.assertEqual(status, 0, message)
        self.assertTrue(created)

    def test_traversal_path_rejected(self):
        status, message, _ = self.run_extractor("traversal")
        self.assertNotEqual(status, 0)
        self.assertIn("Unsafe archive", message)

    def test_symlink_rejected(self):
        status, message, _ = self.run_extractor("symlink")
        self.assertNotEqual(status, 0)
        self.assertIn("Unsafe archive member type", message)


if __name__ == "__main__":
    unittest.main(verbosity=2)
