"""Thin wrapper around the `bq` CLI (works the same locally and on GitHub Actions)."""

import csv
import io
import os
import subprocess

PROJECT = os.environ.get("GCP_PROJECT_ID", "bigquery-457902")
MAX_BYTES = os.environ.get("BQ_MAX_BYTES", "5000000000")


def _bq(args, sql, run_date=None):
    cmd = ["bq", "--quiet", f"--project_id={PROJECT}", "query",
           "--use_legacy_sql=false", f"--maximum_bytes_billed={MAX_BYTES}", *args]
    if run_date:
        cmd.append(f"--parameter=run_date:DATE:{run_date}")
    result = subprocess.run(cmd, input=sql, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"bq failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def run_script(sql, run_date):
    """Run a multi-statement script with @run_date."""
    _bq([], sql, run_date)


def query_csv(sql, run_date=None):
    """Run a SELECT and return the raw CSV text."""
    return _bq(["--format=csv", "--max_rows=10000"], sql, run_date)


def rows(csv_text):
    return list(csv.DictReader(io.StringIO(csv_text)))
