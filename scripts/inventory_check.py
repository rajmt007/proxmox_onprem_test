#!/usr/bin/env python3
"""Read inventory sources without third-party spreadsheet libraries."""
from __future__ import annotations
import argparse, csv, json, os, sys, zipfile
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET
from lab_validation import inventory_ip_matches

NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pkg": "http://schemas.openxmlformats.org/package/2006/relationships",
}

def read_xlsx(path: Path, worksheet_name: str) -> list[dict]:
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        wb = ET.fromstring(archive.read("xl/workbook.xml"))
        rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        relationship_targets = {e.attrib["Id"]: e.attrib["Target"] for e in rels}
        sheet = next((s for s in wb.findall("main:sheets/main:sheet", NS)
                      if s.attrib.get("name") == worksheet_name), None)
        if sheet is None:
            raise KeyError(f"Worksheet {worksheet_name!r} not found in {path}")
        rel_id = sheet.attrib.get(f"{{{NS['rel']}}}id")
        target = relationship_targets.get(rel_id, "")
        sheet_path = (PurePosixPath("xl") / target).as_posix() if not target.startswith("/") else target.lstrip("/")
        # Targets such as /xl/worksheets/sheet1.xml and worksheets/sheet1.xml are both valid.
        if sheet_path not in names:
            sheet_path = target.lstrip("/")
            if not sheet_path.startswith("xl/"):
                sheet_path = "xl/" + sheet_path
        shared = []
        if "xl/sharedStrings.xml" in names:
            shared_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in shared_root.findall("main:si", NS):
                shared.append("".join(t.text or "" for t in item.findall(".//main:t", NS)))
        root = ET.fromstring(archive.read(sheet_path))
        all_rows: list[list[str]] = []
        for row in root.findall(".//main:sheetData/main:row", NS):
            parsed = []
            for cell in row.findall("main:c", NS):
                addr = cell.attrib.get("r", "")
                letters = "".join(c for c in addr if c.isalpha())
                col = 0
                for c in letters.upper(): col = col * 26 + ord(c) - 64
                while len(parsed) < col: parsed.append("")
                v = cell.find("main:v", NS)
                value = ""
                if cell.attrib.get("t") == "s" and v is not None:
                    value = shared[int(v.text)]
                elif cell.attrib.get("t") == "inlineStr":
                    value = "".join(t.text or "" for t in cell.findall(".//main:t", NS))
                elif v is not None:
                    value = v.text or ""
                parsed[col - 1] = value
            all_rows.append(parsed)
    if not all_rows:
        return []
    headers = [str(x).strip() for x in all_rows[0]]
    rows = []
    for raw in all_rows[1:]:
        if not any(str(x).strip() for x in raw): continue
        rows.append({headers[i]: (raw[i] if i < len(raw) else "") for i in range(len(headers)) if headers[i]})
    return rows

def load_rows(path: Path, worksheet_name: str) -> list[dict]:
    ext = path.suffix.lower()
    if ext in {".xlsx", ".xlsm"}: return read_xlsx(path, worksheet_name)
    if ext == ".csv":
        with path.open(newline="", encoding="utf-8-sig") as stream: return list(csv.DictReader(stream))
    if ext == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict): data = data.get(worksheet_name, data.get("inventory", data))
        if isinstance(data, dict): data = data.get("records", [data])
        if not isinstance(data, list) or any(not isinstance(row, dict) for row in data):
            raise ValueError("JSON inventory must be a list of objects or contain an inventory/records list.")
        return data
    raise ValueError(f"Unsupported inventory type: {path.suffix}")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", default="inventory/environment-inventory.xlsx")
    parser.add_argument("--worksheet", default="Envir")
    parser.add_argument("--target-ip", action="append", default=[])
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    args = parser.parse_args()
    root = Path(args.repo_root).resolve()
    configured = (root / args.path).resolve()
    status = "PASS"
    errors, sources, matches = [], [], {}
    if configured.exists():
        candidate_files = [configured]
    else:
        candidates = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in {".xlsx", ".xlsm", ".csv", ".json"}]
        candidates = [p for p in candidates if not any(part in {".git", ".terraform", "node_modules"} for part in p.parts)]
        candidate_files = candidates
        errors.append(f"Configured inventory missing: {configured}")
    if not candidate_files:
        status = "BLOCKED"
        errors.append("No inventory source found. Add inventory/environment-inventory.xlsx with an Envir worksheet.")
    combined = []
    for path in candidate_files:
        try:
            rows = load_rows(path, args.worksheet)
            sources.append({"path": str(path.relative_to(root)), "worksheet": args.worksheet if path.suffix.lower() in {".xlsx", ".xlsm"} else None, "rows": len(rows)})
            combined.extend(rows)
        except (OSError, zipfile.BadZipFile, KeyError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"Cannot read {path}: {exc}")
            status = "BLOCKED"
    for ip in args.target_ip:
        found = inventory_ip_matches(combined, ip)
        matches[ip] = found
        if found: status = "BLOCKED"
    if errors:
        status = "BLOCKED"
    result = {"status": status, "live_ip_availability": "NOT_CHECKED_BY_INVENTORY_SCAN", "sources": sources, "rows_loaded": len(combined), "target_matches": matches, "errors": errors}
    print(json.dumps(result, indent=2))
    return 2 if status == "BLOCKED" or errors else 0

if __name__ == "__main__": sys.exit(main())
