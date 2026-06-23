#!/bin/bash
# eggd_care: DNAnexus app to run UCSC Treehouse CARE outlier analysis
# on a sample previously processed by eggd_treehouse_pipeline.
#
# Inputs
#   rsem_genes_results      : rsem_genes.results file from eggd_treehouse_pipeline (expression function)
#   umend_qc                : bam_umend_qc.tsv file from eggd_treehouse_pipeline (qc function)
#   diagnosis               : harmonised disease diagnosis (optional)
#   care_source_code_tar    : CARE source code (.tar.gz)
#   compendium              : Treehouse tumour compendium archive (.tgz)
#   references              : CARE reference files archive (.tgz)
#
# Outputs
#   CARE_full_output        : All output files, folders, and subfolders from CARE

# prefixes all lines of commands written to stdout with datetime
PS4='\000[$(date)]\011'
export TZ=Europe/London

# Exit at any point if there is any error and output each line as it is executed (for debugging)
# -e = exit on error; -x = output each line that is executed to log; -o pipefail = throw an error if there's an error in pipeline
set -e -x -o pipefail


validate_qc_json() {
    local json_file="$1"

    # Check file exists and is valid JSON
    if ! jq empty "$json_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON in $json_file" >&2
        return 1
    fi

    # Check required keys exist
    for key in input uniqMappedNonDupeReadCount estExonicUniqMappedNonDupeReadCount qc; do
        if ! jq -e "has(\"$key\")" "$json_file" > /dev/null 2>&1; then
            echo "ERROR: Missing key '$key' in $json_file" >&2
            return 1
        fi
    done

    # Check 'input' is a string
    if ! jq -e '.input | type == "string"' "$json_file" > /dev/null 2>&1; then
        echo "ERROR: 'input' is not a string" >&2
        return 1
    fi

    # Check numeric fields are numbers
    for key in uniqMappedNonDupeReadCount estExonicUniqMappedNonDupeReadCount; do
        if ! jq -e ".$key | type == \"number\"" "$json_file" > /dev/null 2>&1; then
            echo "ERROR: '$key' is not numeric" >&2
            return 1
        fi
    done

    # Check 'qc' is PASS or FAIL
    qc_val=$(jq -r '.qc' "$json_file")
    if [[ "$qc_val" != "PASS" && "$qc_val" != "FAIL" ]]; then
        echo "ERROR: 'qc' must be PASS or FAIL, got '$qc_val'" >&2
        return 1
    fi

    echo "QC JSON is valid"
    return 0
}

validate_expression_folder(){
    #check it contains RSEM, QC subfolders

    ##check that RSEM includes:
    ## rsem_genes.results - this is essential
    ## rsem_isoforms.results - optional for isoforms analysis
    ##check that QC includes:
    ## QC/STAR/Log.final.out - essential to have more comprehensive QC on the sample
    ## QC/fastQC/R1_fastqc.html - essential to have more comprehensive QC on the sample
    
    local_expr_fold="$1"
    if [[ ! -e ${local_expr_fold}/RSEM/rsem_genes.results ]]; then
        echo "ERROR: RSEM/rsem_genes.results not found" >&2
        return 1
    fi

    if [[ ! -e ${local_expr_fold}/RSEM/rsem_isoforms.results ]]; then
        echo "Warning: RSEM/rsem_isoforms.results - Isoforms analysis will not be possible" >&2
    fi

    if [[ ! -e ${local_expr_fold}/QC/fastQC/R1_fastqc.html ]]; then
        echo "ERROR: QC/fastQC/R1_fastqc.html not found" >&2
        return 1
    fi

    if [[ ! -e ${local_expr_fold}/QC/STAR/Log.final.out ]]; then
        echo "ERROR: QC/STAR/Log.final.out not found" >&2
        return 1
    fi
}

download_and_stage_input(){
    #Downaload input files and stage them correctly
    echo ">>> Downloading inputs"
    dx-download-all-inputs

    mkdir -p /home/dnanexus/resources
    tar -xzf /home/dnanexus/in/compendium/*TumorCompendium*.tgz  -C /home/dnanexus/resources/
    tar -xzf /home/dnanexus/in/references/*TreehouseReferences*.tgz  -C /home/dnanexus/resources/

    # check umend_qc_json file
    ##Expected format:
    ## {"input":"readDist.txt","uniqMappedNonDupeReadCount":1708,"estExonicUniqMappedNonDupeReadCount":1554.175,"qc":"FAIL"}
    
    echo "Validate QC .json file"
    validate_qc_json /home/dnanexus/in/umend_qc_json/*.json
    
    # check expression folder
    echo "Validate expression folder for three essential files and one optional file"
    dx download -r $eggd_treehouse_expression_folder/
    expr_folder_name=$(basename $eggd_treehouse_expression_folder | cut -d '/' -f -1)
    validate_expression_folder ${expr_folder_name}

    # move qc and expression in the right folder:
    mkdir -p /home/dnanexus/secondary && cd /home/dnanexus/secondary
    mv ${expr_folder_name}/ /ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000/
    mkdir ucsctreehouse-bam-umend-qc-0.0.0-0000000
    mv /home/dnanexus/in/umend_qc_json/*.json /home/dnanexus/secondary/ucsctreehouse-bam-umend-qc-0.0.0-0000000
    cd

    # create inputs and sample folder and move expression and qc data there
    mkdir -p /home/dnanexus/inputs && cd inputs
    sample=$(basename "$eggd_treehouse_expression_folder" | cut -d '-' -f 2)
    mkdir ${sample}
    cd
    mv secondary/ inputs/${sample}
   
   # add diagnosis if present
    if [[ -n "$diagnosis" ]]; then
        echo -e "${sample}\t${diagnosis}" > manifest.tsv
    else
        echo "${sample}" > manifest.tsv
    fi  
}


run_care_docker() {
    echo ">>> Run CARE docker"
    docker load -i /home/dnanexus/in/care_source_code_tar/*.tar.gz
    docker_image_id=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^ucsctreehouse/care" | cut -d' ' -f2)

    docker run \
    --rm \
    --user $UID \
    -v 'pwd'/:/work \
    -v 'pwd'/manifest.tsv:/work/manifest.tsv:ro \
    -v 'pwd'/inputs:/work/inputs:ro \
    ${docker_image_id}  run
}


upload_outputs() {
    # Stage and upload outputs to DNAnexus.
    echo ">>> Staging CARE outputs..."
    mkdir -p /home/dnanexus/out/CARE_full_output  
    mv outputs/* /home/dnanexus/out/CARE_full_output

    echo ">>> Uploading CARE outputs..."
    dx-upload-all-outputs --parallel
}



main() {
    # Run the main pipeline with the function in order

    echo "=========================================="
    echo "eggd_care: starting CARE outlier analysis in DNA Nexus"
    date
    echo "=========================================="

    download_and_stage_input
    run_care_docker
    upload_outputs

    echo ">>> eggd_care: complete."
    date
}