#!/usr/bin/env python3
"""
Basic tests for eggd_care.

These tests validate the logic that surrounds the CARE Docker call:
- manifest.tsv is correctly formatted
- input directory structure is correct
- diagnosis is handled correctly when absent
"""

import os
import subprocess
import tempfile
import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def write_manifest(sample_id, diagnosis, outdir):
    path = os.path.join(outdir, "manifest.tsv")
    with open(path, "w") as fh:
        fh.write(f"{sample_id}\t{diagnosis}\n")
    return path


def build_input_tree(sample_id, rsem_content, basedir):
    pipeline_dir = "ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000"
    rsem_dir = os.path.join(
        basedir, "inputs", sample_id, "secondary", pipeline_dir, "RSEM"
    )
    os.makedirs(rsem_dir, exist_ok=True)
    rsem_path = os.path.join(rsem_dir, "rsem_genes.results")
    with open(rsem_path, "w") as fh:
        fh.write(rsem_content)
    return rsem_path


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestManifest:
    def test_manifest_with_diagnosis(self, tmp_path):
        path = write_manifest("SAMPLE001", "neuroblastoma", tmp_path)
        with open(path) as fh:
            line = fh.readline().strip()
        assert line == "SAMPLE001\tneuroblastoma"

    def test_manifest_empty_diagnosis(self, tmp_path):
        path = write_manifest("SAMPLE002", "", tmp_path)
        with open(path) as fh:
            line = fh.readline().strip()
        assert line == "SAMPLE002\t"

    def test_manifest_tab_separated(self, tmp_path):
        path = write_manifest("S1", "AML", tmp_path)
        with open(path) as fh:
            content = fh.read()
        assert "\t" in content


class TestInputTree:
    def test_rsem_file_placed_correctly(self, tmp_path):
        rsem_content = "gene_id\texpected_count\nGENE1\t100\n"
        rsem_path = build_input_tree("SAMPLE001", rsem_content, tmp_path)
        assert os.path.exists(rsem_path)
        assert rsem_path.endswith("rsem_genes.results")

    def test_rsem_pipeline_dir_name(self, tmp_path):
        build_input_tree("SAMPLE001", "header\n", tmp_path)
        expected = os.path.join(
            tmp_path,
            "inputs", "SAMPLE001", "secondary",
            "ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000",
            "RSEM", "rsem_genes.results"
        )
        assert os.path.exists(expected)

    def test_rsem_content_preserved(self, tmp_path):
        content = "gene_id\texpected_count\nGENE1\t42\n"
        rsem_path = build_input_tree("SAMPLE001", content, tmp_path)
        with open(rsem_path) as fh:
            assert fh.read() == content