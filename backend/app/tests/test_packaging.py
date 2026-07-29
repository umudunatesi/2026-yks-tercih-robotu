from pathlib import Path


def test_windows_backend_package_includes_runtime_data():
    spec = Path(__file__).parents[2] / "yks_backend.spec"
    content = spec.read_text(encoding="utf-8")
    assert "('app\\\\data', 'app\\\\data')" in content
