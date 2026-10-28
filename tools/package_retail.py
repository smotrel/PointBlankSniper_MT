"""Build a local, reviewable Retail test ZIP without touching the game install."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
output = root / "PointBlankSniper-retail-test.zip"
files = [root / "PointBlankSniper.toc", root / "LICENSE", root / "README-fork.md"]
for directory in ("Locales", "Source", "Tones"):
    files.extend(p for p in (root / directory).rglob("*") if p.is_file())

included = {p.relative_to(root).as_posix().lower() for p in files}
for xml in list((root / "Source").rglob("*.xml")) + list((root / "Locales").rglob("*.xml")):
    for node in ET.parse(xml).iter():
        if node.tag.rsplit("}", 1)[-1] not in ("Script", "Include"):
            continue
        referenced = node.attrib.get("file")
        if not referenced:
            continue
        relative = (xml.parent / Path(referenced.replace("\\", "/"))).relative_to(root).as_posix()
        if relative.lower() not in included:
            raise SystemExit(f"Missing XML dependency: {xml.relative_to(root)} -> {relative}")

with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for path in sorted(files):
        name = "PointBlankSniper/" + path.relative_to(root).as_posix()
        if path.name == "PointBlankSniper.toc":
            toc = path.read_text(encoding="utf-8").replace("@project-version@", "fork-retail-test-1")
            archive.writestr(name, toc)
        else:
            archive.write(path, name)

with ZipFile(output) as archive:
    assert archive.testzip() is None
    print(f"{output} ({len(archive.namelist())} files; archive verified)")
