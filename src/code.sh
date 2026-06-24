#!/bin/bash
# eggd_care: DNAnexus app to run UCSC Treehouse CARE outlier analysis
# on a sample previously processed by eggd_treehouse_pipeline.
#
# Inputs
#   rsem_genes_results      : rsem_genes.results file from eggd_treehouse_pipeline (expression function)
#   umend_qc                : bam_umend_qc.json file from eggd_treehouse_pipeline (qc function)
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
    # Takes a UMEND_QC.json file and check that the required keys are present and they have the right format
    # Excepted format:
    ## {"input":"readDist.txt","uniqMappedNonDupeReadCount":1708,"estExonicUniqMappedNonDupeReadCount":1554.175,"qc":"FAIL"}
    ## Arguments:
        ## $umend_qc 

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
    #Check it contains files in RSEM and QC subfolders

    ##check that RSEM includes:
    ## rsem_genes.results - this is essential
    ## rsem_isoforms.results - optional for isoforms analysis
    ##check that QC includes:
    ## QC/STAR/Log.final.out - essential to have more comprehensive QC on the sample
    ## QC/fastQC/R1_fastqc.html - essential to have more comprehensive QC on the sample

    ## Arguments:
        ## $rsem_genes_results
    
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

flatten_dir(){
    #Flatten a folder by removing an intermediate folder
    #Arguments:
        ## upstream directory_path in which move the contents in the folder to be flattened
    root_dir=$1
    echo ">>> Folder to flatten contents:"
    ls -lthr $root_dir
    if [ "$(ls -1 ${root_dir} | wc -l)" -eq 1 ]; then
        toflatten_dir=$(ls ${root_dir})
        if [ -d "${root_dir}/${toflatten_dir}" ]; then
            echo ">>> Flattening cohort structure"
            #shopt -s to include hidden files in for the mv command
            shopt -s dotglob
            mv ${root_dir}/${toflatten_dir}/* ${root_dir}
            rmdir ${root_dir}/${toflatten_dir}
            #shopt -u to reset default way for the mv command
            shopt -u dotglob
            echo ">>> Folder contents after flatten:"
            ls -lthr ${root_dir}
        fi
    fi
}

download_and_stage_input(){
    #Download input files and stage them correctly
    #Flatten compendium and references folder to have the right folder structure required by CARE docker
    #Run validation of umend_qc_json file and expression folder
    #Create manifest.tsv and add diagnosis if provided as input
    
    echo ">>> Downloading inputs"
    dx-download-all-inputs
    
    mkdir -p /home/dnanexus/references
    tar -vxzf /home/dnanexus/in/references/*.tgz -C /home/dnanexus/references
    flatten_dir /home/dnanexus/references

    mkdir -p /home/dnanexus/cohort
    tar -vxzf /home/dnanexus/in/compendium/*.tgz -C /home/dnanexus/cohort
    flatten_dir /home/dnanexus/cohort
    
    # check umend_qc_json file
    echo "Validate QC .json file"
    validate_qc_json /home/dnanexus/in/umend_qc_json/*.json
    
    # check expression folder
    echo "Validate expression folder for three essential files and one optional file"
    dx download -r "${eggd_treehouse_expression_folder}/"
    expr_folder_name=$(basename "$eggd_treehouse_expression_folder")
    validate_expression_folder "${expr_folder_name}"

    # move qc and expression in the right folder:
    mkdir -p /home/dnanexus/secondary && cd /home/dnanexus/secondary
    mv "/home/dnanexus/${expr_folder_name}/" ucsc_cgl-rnaseq-cgl-pipeline-0.0.0-0000000/
    mkdir ucsctreehouse-bam-umend-qc-0.0.0-0000000
    mv /home/dnanexus/in/umend_qc_json/*.json ucsctreehouse-bam-umend-qc-0.0.0-0000000/
    cd

    # create inputs and sample folder and move expression and qc data there
    mkdir -p /home/dnanexus/inputs && cd /home/dnanexus/inputs
    sample=$(basename "$eggd_treehouse_expression_folder" | cut -d '-' -f 2)
    mkdir "${sample}"
    cd
    mv /home/dnanexus/secondary/ "/home/dnanexus/inputs/${sample}/"
   
   # add diagnosis if present
    if [[ -n "$diagnosis" ]]; then
        echo -e "${sample}\t${diagnosis}" > manifest.tsv
    else
        echo "${sample}" > manifest.tsv
    fi  
}


run_care_docker() {
    # Run the CARE pipeline with docker image
    # Local folders need to be mounted to be seen by Docker and arguments needs to be specified
    echo ">>> Run CARE docker"

    docker load -i /home/dnanexus/in/care_source_code_tar/*.tar.gz
    docker_image_id=$(docker images --format="{{.Repository}} {{.ID}}" \
        | grep "^ucsctreehouse/care" \
        | cut -d' ' -f2)

    mkdir -p /home/dnanexus/workdir
    mkdir -p /home/dnanexus/rollup
    mkdir -p /home/dnanexus/workdir/outputs 

    docker run \
      --rm \
      --user $UID \
      -v /home/dnanexus/workdir:/work \
      -v /home/dnanexus/manifest.tsv:/work/manifest.tsv:ro \
      -v /home/dnanexus/inputs:/work/inputs:ro \
      -v /home/dnanexus/cohort:/work/cohort:ro \
      -v /home/dnanexus/references:/work/references:ro \
      ${docker_image_id} pass-args \
        --inputs /work/inputs \
        --cohort /work/cohort \
        --references /work/references \
        --outputs /work/outputs \
        --rollup /work/outputs
}


upload_outputs() {
    # Stage and upload outputs to DNAnexus.
    echo ">>> Staging CARE outputs..."
    mkdir -p /home/dnanexus/out/CARE_full_output  
    mv /home/dnanexus/workdir/outputs/* /home/dnanexus/out/CARE_full_output

    echo ">>> Uploading CARE outputs..."
    dx-upload-all-outputs --parallel
}



main() {
    # Run the main pipeline with the functions in order

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