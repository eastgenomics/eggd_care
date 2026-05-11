
#!/bin/bash
# eggd_care: DNAnexus app to run UCSC Treehouse CARE outlier analysis
# on a sample previously processed by eggd_treehouse_pipeline.
#
# Inputs
#   rsem_genes_results  : rsem_genes.results file from eggd_treehouse_pipeline
#   sample_id           : unique sample identifier
#   diagnosis           : harmonised disease diagnosis (optional)
#   care_docker         : CARE Docker image (.tar.gz)
#   compendium          : Treehouse tumour compendium archive (.tgz)
#   references          : CARE reference files archive (.tgz)
#   care_version        : CARE release version string (for logging)
#
# Outputs
#   summary_html        : Summary.html
#   slides_html         : Slides.html
#   output_json_files   : array of JSON result files
#   output_notebooks    : array of executed .ipynb notebooks

set -exo pipefail

main() {
    echo "==== eggd_care: starting CARE outlier analysis ===="
    echo "Sample ID   : ${sample_id}"
    echo "Diagnosis   : ${diagnosis:-<not provided — pan-disease only>}"
    echo "CARE version: ${care_version}"
    date

    # -----------------------------------------------------------------------
    # 1. Download all inputs
    # -----------------------------------------------------------------------
    echo "--- Downloading inputs ---"
    dx-download-all-inputs --except care_docker --except compendium --except references

    echo "--- Downloading large reference/docker files ---"
    dx download "${care_docker_file_id}"     -o care_docker.tar.gz
    dx download "${compendium_file_id}"      -o compendium.tgz
    dx download "${references_file_id}"      -o references.tgz

    # -----------------------------------------------------------------------
    # 2. Load the CARE Docker image
    # -----------------------------------------------------------------------
    echo "--- Loading CARE Docker image ---"
    docker load -i care_docker.tar.gz
    CARE_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i care | head -1)
    echo "CARE image loaded: ${CARE_IMAGE}"

    # -----------------------------------------------------------------------
    # 3. Extract compendium and references into the CARE resources/ directory
    # -----------------------------------------------------------------------
    echo "--- Extracting compendium and references ---"
    mkdir -p care_run/resources
    tar -xzf compendium.tgz  -C care_run/resources/
    tar -xzf references.tgz  -C care_run/resources/

    # -----------------------------------------------------------------------
    # 4. Build the CARE input directory structure
    #
    # CARE expects:
    #   inputs/<SAMPLE_ID>/secondary/
    #       ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000/
    #           RSEM/
    #               rsem_genes.results
    # -----------------------------------------------------------------------
    echo "--- Staging sample input files ---"

    PIPELINE_DIR="ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000"
    INPUT_BASE="care_run/inputs/${sample_id}/secondary/${PIPELINE_DIR}/RSEM"
    mkdir -p "${INPUT_BASE}"

    cp "${rsem_genes_results_path}" "${INPUT_BASE}/rsem_genes.results"

    # -----------------------------------------------------------------------
    # 5. Write the manifest.tsv
    #
    # Format: <SAMPLE_ID>\t<diagnosis>
    # Diagnosis may be empty (pan-disease analysis only).
    # -----------------------------------------------------------------------
    echo "--- Writing manifest.tsv ---"
    printf '%s\t%s\n' "${sample_id}" "${diagnosis:-}" > care_run/manifest.tsv
    echo "manifest.tsv:"
    cat care_run/manifest.tsv

    # -----------------------------------------------------------------------
    # 6. Run CARE inside Docker
    #
    # We replicate what `make run` does inside the CARE repo:
    #   - mount the inputs/, outputs/, resources/, and manifest.tsv
    #   - pass SAMPLE_ID so CARE processes only our focus sample
    # -----------------------------------------------------------------------
    echo "--- Running CARE Docker container ---"

    mkdir -p care_run/outputs

    docker run --rm \
        -v "$(pwd)/care_run/inputs:/CARE/inputs" \
        -v "$(pwd)/care_run/outputs:/CARE/outputs" \
        -v "$(pwd)/care_run/resources:/CARE/resources" \
        -v "$(pwd)/care_run/manifest.tsv:/CARE/manifest.tsv" \
        "${CARE_IMAGE}" \
        bash -c "cd /CARE && python care/run_care.py --sample ${sample_id}"

    echo "--- CARE run complete ---"

    # -----------------------------------------------------------------------
    # 7. Locate outputs
    # -----------------------------------------------------------------------
    SAMPLE_OUT="care_run/outputs/${sample_id}"

    if [[ ! -d "${SAMPLE_OUT}" ]]; then
        echo "ERROR: Expected output directory not found: ${SAMPLE_OUT}"
        echo "Contents of care_run/outputs/:"
        ls -lR care_run/outputs/ || true
        exit 1
    fi

    echo "Output directory contents:"
    ls -lR "${SAMPLE_OUT}"

    # -----------------------------------------------------------------------
    # 8. Upload outputs to DNAnexus
    # -----------------------------------------------------------------------
    echo "--- Uploading outputs ---"

    # Summary HTML
    SUMMARY="${SAMPLE_OUT}/Summary.html"
    if [[ -f "${SUMMARY}" ]]; then
        summary_html=$(dx upload "${SUMMARY}" --brief --destination "${sample_id}_Summary.html")
        dx-jobutil-add-output summary_html "${summary_html}" --class=file
    else
        echo "WARNING: Summary.html not found"
    fi

    # Slides HTML
    SLIDES="${SAMPLE_OUT}/Slides.html"
    if [[ -f "${SLIDES}" ]]; then
        slides_html=$(dx upload "${SLIDES}" --brief --destination "${sample_id}_Slides.html")
        dx-jobutil-add-output slides_html "${slides_html}" --class=file
    else
        echo "WARNING: Slides.html not found"
    fi

    # JSON result files
    echo "--- Uploading JSON result files ---"
    while IFS= read -r -d '' json_file; do
        json_id=$(dx upload "${json_file}" --brief --destination "${sample_id}_$(basename "${json_file}")")
        dx-jobutil-add-output output_json_files "${json_id}" --class=file --array
    done < <(find "${SAMPLE_OUT}" -name "*.json" -print0)

    # Executed Jupyter notebooks
    echo "--- Uploading executed notebooks ---"
    while IFS= read -r -d '' nb_file; do
        nb_id=$(dx upload "${nb_file}" --brief --destination "${sample_id}_$(basename "${nb_file}")")
        dx-jobutil-add-output output_notebooks "${nb_id}" --class=file --array
    done < <(find "${SAMPLE_OUT}" -name "*.ipynb" -print0)

    echo "==== eggd_care: finished successfully ===="
    date
}