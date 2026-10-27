#!/usr/bin/env python3
"""Offline CSL-JSON normalization, duplicate auditing, and conservative BibTeX export."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import tempfile
import unicodedata
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit


STATUSES = {"已核验", "待核验", "材料缺失"}
TRACKING_QUERY_PREFIXES = ("utm_",)
TRACKING_QUERY_NAMES = {"fbclid", "gclid", "mc_cid", "mc_eid"}


class CitationLedgerError(ValueError):
    """Raised when an input or output violates the citation ledger contract."""


def normalize_doi(value: object) -> str:
    text = str(value or "").strip()
    if re.match(r"^https?://(?:dx\.)?doi\.org/", text, flags=re.IGNORECASE):
        text = unquote(urlsplit(text).path.lstrip("/"))
    else:
        text = re.sub(r"^doi:\s*", "", text, flags=re.IGNORECASE)
    return text.strip().rstrip(". ").lower()


def normalize_url(value: object) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    parts = urlsplit(text)
    if parts.scheme.lower() not in {"http", "https"} or not parts.netloc:
        return text
    query = [(key, val) for key, val in parse_qsl(parts.query, keep_blank_values=True)
             if key.lower() not in TRACKING_QUERY_NAMES
             and not key.lower().startswith(TRACKING_QUERY_PREFIXES)]
    path = parts.path or "/"
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, urlencode(query), ""))


def normalize_title_key(value: object) -> str:
    text = unicodedata.normalize("NFKC", str(value or "")).casefold()
    return "".join(char for char in text if char.isalnum())


def issued_year(record: dict) -> int | None:
    issued = record.get("issued")
    if not isinstance(issued, dict):
        return None
    parts = issued.get("date-parts")
    if not isinstance(parts, list) or not parts or not isinstance(parts[0], list) or not parts[0]:
        return None
    year = parts[0][0]
    if isinstance(year, bool):
        return None
    try:
        year_int = int(year)
    except (TypeError, ValueError):
        return None
    return year_int if 1000 <= year_int <= 9999 else None


def _identifier(record: dict, *names: str) -> str:
    for name in names:
        value = record.get(name)
        if value is not None and str(value).strip():
            return str(value).strip().casefold()
    return ""


def load_records(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except OSError as exc:
        raise CitationLedgerError(f"cannot read input: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise CitationLedgerError(f"invalid JSON at line {exc.lineno}, column {exc.colno}") from exc
    if not isinstance(data, list):
        raise CitationLedgerError("input must be a CSL-JSON array")
    if not data:
        raise CitationLedgerError("input contains no citation records")
    records = []
    seen_ids: set[str] = set()
    for index, item in enumerate(data, 1):
        if not isinstance(item, dict):
            raise CitationLedgerError(f"record {index}: expected an object")
        record_id = str(item.get("id") or "").strip()
        title = str(item.get("title") or "").strip()
        if not record_id:
            raise CitationLedgerError(f"record {index}: non-empty id is required")
        if record_id in seen_ids:
            raise CitationLedgerError(f"record {index}: duplicate CSL id {record_id!r}")
        if not title:
            raise CitationLedgerError(f"record {index} ({record_id}): non-empty title is required")
        seen_ids.add(record_id)
        records.append(copy.deepcopy(item))
    return records


def normalize_record(record: dict) -> tuple[dict, list[str]]:
    result = copy.deepcopy(record)
    warnings: list[str] = []
    result["id"] = str(result["id"]).strip()
    result["title"] = str(result["title"]).strip()
    if "DOI" in result or "doi" in result:
        doi = normalize_doi(result.get("DOI") or result.get("doi"))
        result.pop("doi", None)
        if doi:
            result["DOI"] = doi
            if not re.match(r"^10\.\d{4,9}/\S+$", doi):
                warnings.append("DOI has an unusual shape and remains unverified")
        else:
            result.pop("DOI", None)
            warnings.append("empty DOI removed")
    if "URL" in result or "url" in result:
        url = normalize_url(result.get("URL") or result.get("url"))
        result.pop("url", None)
        if url:
            result["URL"] = url
        else:
            result.pop("URL", None)
    authors = result.get("author")
    if authors is not None:
        if not isinstance(authors, list):
            raise CitationLedgerError(f"record {result['id']}: author must be an array")
        for position, author in enumerate(authors, 1):
            if not isinstance(author, dict) or not any(str(author.get(key) or "").strip() for key in ("family", "given", "literal")):
                raise CitationLedgerError(f"record {result['id']}: invalid author at position {position}")
    if result.get("issued") is not None and issued_year(result) is None:
        warnings.append("issued date exists but has no valid four-digit year")
    audit = result.get("_audit")
    if audit is None:
        audit = {"verification_status": "待核验", "metadata_source": "", "checked_at": "", "notes": []}
        warnings.append("verification status defaulted to 待核验")
    elif not isinstance(audit, dict):
        raise CitationLedgerError(f"record {result['id']}: _audit must be an object")
    else:
        audit = copy.deepcopy(audit)
    status = str(audit.get("verification_status") or "待核验")
    if status not in STATUSES:
        raise CitationLedgerError(f"record {result['id']}: unsupported verification_status {status!r}")
    audit["verification_status"] = status
    audit["metadata_source"] = str(audit.get("metadata_source") or "")
    audit["checked_at"] = str(audit.get("checked_at") or "")
    notes = audit.get("notes", [])
    if not isinstance(notes, list):
        raise CitationLedgerError(f"record {result['id']}: _audit.notes must be an array")
    audit["notes"] = [str(note) for note in notes]
    result["_audit"] = audit
    return result, warnings


def audit_records(records: list[dict]) -> tuple[list[dict], dict]:
    normalized: list[dict] = []
    warnings: dict[str, list[str]] = {}
    for record in records:
        clean, record_warnings = normalize_record(record)
        normalized.append(clean)
        if record_warnings:
            warnings[clean["id"]] = record_warnings

    exact_index: dict[tuple[str, str], list[str]] = {}
    title_index: dict[tuple[str, int | None], list[str]] = {}
    for record in normalized:
        identifiers = {
            "doi": normalize_doi(record.get("DOI")),
            "pmid": _identifier(record, "PMID", "pmid"),
            "pmcid": _identifier(record, "PMCID", "pmcid"),
            "arxiv": _identifier(record, "arXiv", "arxiv", "arxiv_id"),
        }
        for kind, value in identifiers.items():
            if value:
                exact_index.setdefault((kind, value), []).append(record["id"])
        title_key = normalize_title_key(record.get("title"))
        if title_key:
            title_index.setdefault((title_key, issued_year(record)), []).append(record["id"])

    exact_groups = [
        {"identifier_type": kind, "identifier": value, "record_ids": ids}
        for (kind, value), ids in exact_index.items() if len(ids) > 1
    ]
    exact_pairs = {
        frozenset((left, right))
        for group in exact_groups
        for pos, left in enumerate(group["record_ids"])
        for right in group["record_ids"][pos + 1:]
    }
    possible_groups = []
    for (title_key, year), ids in title_index.items():
        if len(ids) < 2:
            continue
        pairs = [frozenset((left, right)) for pos, left in enumerate(ids) for right in ids[pos + 1:]]
        if any(pair not in exact_pairs for pair in pairs):
            possible_groups.append({"match": "normalized_title_and_year", "year": year,
                                    "title_key": title_key, "record_ids": ids})

    missing_fields = {}
    for record in normalized:
        missing = [field for field in ("type", "author", "issued") if not record.get(field)]
        if not record.get("DOI") and not record.get("URL"):
            missing.append("DOI_or_URL")
        if missing:
            missing_fields[record["id"]] = missing

    report = {
        "record_count": len(normalized),
        "exact_duplicate_groups": exact_groups,
        "possible_duplicate_groups": possible_groups,
        "missing_fields": missing_fields,
        "warnings": warnings,
        "notes": [
            "No record was deleted or merged.",
            "Duplicate groups are candidates for human review, not proof that metadata is correct.",
            "No network verification was performed.",
        ],
    }
    return normalized, report


def _bibtex_escape(value: object) -> str:
    text = str(value or "")
    replacements = {"\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
                    "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}"}
    return "".join(replacements.get(char, char) for char in text)


def _author_text(authors: object) -> str:
    if not isinstance(authors, list):
        return ""
    rendered = []
    for author in authors:
        if not isinstance(author, dict):
            continue
        literal = str(author.get("literal") or "").strip()
        if literal:
            rendered.append("{" + _bibtex_escape(literal) + "}")
            continue
        family = str(author.get("family") or "").strip()
        given = str(author.get("given") or "").strip()
        if family and given:
            rendered.append(f"{_bibtex_escape(family)}, {_bibtex_escape(given)}")
        elif family or given:
            rendered.append(_bibtex_escape(family or given))
    return " and ".join(rendered)


def _citation_key(record: dict, used: set[str]) -> str:
    base = re.sub(r"[^A-Za-z0-9]+", "", str(record.get("id") or "")) or "ref"
    if base not in used:
        used.add(base)
        return base
    identity = normalize_doi(record.get("DOI")) or normalize_title_key(record.get("title"))
    suffix = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:8]
    candidate = f"{base}{suffix}"
    if candidate in used:
        raise CitationLedgerError(f"cannot create a unique BibTeX key for {record['id']}")
    used.add(candidate)
    return candidate


def render_bibtex(records: list[dict]) -> str:
    type_map = {
        "article-journal": "article", "article-magazine": "article", "article-newspaper": "article",
        "book": "book", "chapter": "incollection", "paper-conference": "inproceedings",
        "report": "techreport", "thesis": "phdthesis", "webpage": "misc", "dataset": "misc",
    }
    used: set[str] = set()
    entries = []
    for record in records:
        entry_type = type_map.get(str(record.get("type") or ""), "misc")
        key = _citation_key(record, used)
        fields: list[tuple[str, object]] = [("title", record.get("title"))]
        author = _author_text(record.get("author"))
        if author:
            fields.append(("author", author))
        year = issued_year(record)
        if year:
            fields.append(("year", year))
        mapping = [
            ("journal", "container-title"), ("booktitle", "collection-title"),
            ("volume", "volume"), ("number", "issue"), ("pages", "page"),
            ("publisher", "publisher"), ("address", "publisher-place"),
            ("doi", "DOI"), ("url", "URL"), ("isbn", "ISBN"), ("issn", "ISSN"),
        ]
        for bib_name, csl_name in mapping:
            value = record.get(csl_name)
            if value:
                fields.append((bib_name, value))
        lines = [f"@{entry_type}{{{key},"]
        for name, value in fields:
            rendered = value if name == "author" else _bibtex_escape(value)
            lines.append(f"  {name} = {{{rendered}}},")
        lines.append("}")
        entries.append("\n".join(lines))
    return "\n\n".join(entries) + "\n"


def _validate_outputs(input_path: Path, outputs: list[Path | None], overwrite: bool) -> None:
    source = input_path.resolve()
    resolved = [path.resolve() for path in outputs if path is not None]
    if len(resolved) != len(set(resolved)):
        raise CitationLedgerError("output paths must be distinct")
    for path in resolved:
        if path == source:
            raise CitationLedgerError("an output path cannot be the input path")
        if path.exists() and not overwrite:
            raise CitationLedgerError(f"output exists; pass --overwrite yes only after explicit approval: {path}")


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="CSL-JSON array")
    parser.add_argument("--normalized-json", type=Path)
    parser.add_argument("--report-json", type=Path)
    parser.add_argument("--bibtex", type=Path)
    parser.add_argument("--overwrite", choices=["yes", "no"], default="no")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    outputs = [args.normalized_json, args.report_json, args.bibtex]
    try:
        _validate_outputs(args.input, outputs, args.overwrite == "yes")
        normalized, report = audit_records(load_records(args.input))
        normalized_text = json.dumps(normalized, ensure_ascii=False, indent=2) + "\n"
        report_text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.normalized_json:
            _atomic_write(args.normalized_json.resolve(), normalized_text)
        if args.report_json:
            _atomic_write(args.report_json.resolve(), report_text)
        if args.bibtex:
            _atomic_write(args.bibtex.resolve(), render_bibtex(normalized))
        if not any(outputs):
            print(json.dumps({"normalized_records": normalized, "audit_report": report}, ensure_ascii=False, indent=2))
        return 0
    except (CitationLedgerError, OSError) as exc:
        print(f"error: {exc}", file=os.sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
