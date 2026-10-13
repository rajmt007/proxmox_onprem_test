#!/usr/bin/env python3
"""Convert newline-delimited check objects into Markdown, JSON, and CSV reports."""
import argparse, csv, json
from datetime import datetime, timezone
from pathlib import Path

FIELDS = ["name", "status", "timestamp_utc", "command", "evidence", "remediation"]
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="JSON Lines check data")
    ap.add_argument("--prefix", required=True, help="Output file prefix (without extension)")
    ap.add_argument("--title", default="Automation report")
    args = ap.parse_args()
    inp, prefix = Path(args.input), Path(args.prefix)
    rows = []
    for line in inp.read_text(encoding="utf-8").splitlines():
        if line.strip(): rows.append(json.loads(line))
    stamp = datetime.now(timezone.utc).isoformat()
    fail_states = {"FAIL", "BLOCKED", "NOT RUN", "NOT_RUN", "UNKNOWN_BLOCKED", "CONFLICT", "BLOCKED_BY_FIREWALL"}
    overall = "FAIL" if any(str(r.get("status", "")).upper() == "FAIL" for r in rows) else (
        "BLOCKED" if any(str(r.get("status", "")).upper() in fail_states for r in rows) else "PASS")
    result = {"title": args.title, "generated_at_utc": stamp, "overall_status": overall, "checks": rows}
    prefix.parent.mkdir(parents=True, exist_ok=True)
    Path(str(prefix) + ".json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    with Path(str(prefix) + ".csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader(); writer.writerows(rows)
    lines = [f"# {args.title}", "", f"- Generated UTC: `{stamp}`", f"- Overall status: **{overall}**", ""]
    for row in rows:
        lines += [f"## {row.get('name', 'Unnamed check')} — {row.get('status', 'NOT RUN')}", "",
                  f"- Timestamp UTC: `{row.get('timestamp_utc', stamp)}`",
                  f"- Command/test: `{row.get('command', '')}`",
                  f"- Evidence: {row.get('evidence', '')}"]
        if row.get("remediation"): lines.append(f"- Remediation: {row['remediation']}")
        lines.append("")
    Path(str(prefix) + ".md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Overall: {overall}; checks: {len(rows)}; outputs: {prefix}.md, .json, .csv")
    return 2 if overall != "PASS" else 0
if __name__ == "__main__": raise SystemExit(main())
