<!-- dx-header -->
# AmazingApp (DNAnexus Platform App)
DNA Nexus app of the [CARE pipeline](https://github.com/UCSC-Treehouse/CARE/tree/25ad888d8b67e80b68e5943d11664fe720e08755)

<!-- Insert a description of your app here -->
## What does this app do?
Eggd_care is used to compare the gene expression of a single cancer sample against a tumour compendium of > 10,000 tumour specimens and highly expressed genes indentified as outliers.

## What are the typical use cases for this app?
N-of-1 analysis for gene expression in a cancer sample compared to a tumour compendium. It uses files outputted by [eggd_treehouse_pipeline](https://github.com/eastgenomics/eggd_treehouse_pipeline).

## What are the inputs?
| Input | Class | Description |
|---|---|---|
| `eggd_treehouse_expression_folder` | array:file | Folder path name for expression results outputted by eggd_treehouse_pipeline. Essential files: /rsem_genes.results, QC/STAR/Log.final.out, QC/fastQC/R1_fastqc.html Optional file for isoforms analysis: RSEM/rsem_isoforms.results.
| `umend_qc_json` | file | bam_umend_qc.json file produced by qc functionality of eggd_treehouse_pipeline.
| `diagnosis` | string | Harmonised diagnosis of the focus sample. Must match a value in the 'disease' column of the Treehouse compendium clinical data (clinical_TumorCompendium_v10_PolyA_2019-07-25.tsv). Leave blank to skip disease-specific outlier analysis and run pan-disease only.
| `care_source_code_tar` | file | DNA Nexus file for Compressed source code (.tar.gz) of the UCSC CARE pipeline - [tag 0.17.1.0](https://hub.docker.com/layers/ucsctreehouse/care/0.17.1.0/images/sha256-52eaaf6804101a74a105043c5926b39d2bbe903a54f0923cb77b9f6ba85f4a6b).
| `compendium` | file | DNA Nexus file for Treehouse tumour compendium archive (e.g. TumorCompendium_v10_PolyA.tgz). Downloaded from https://xena.treehouse.gi.ucsc.edu/download/CARE/TumorCompendium_v10_PolyA.tgz.
| `references` | file | DNA Nexus file for CARE reference archive (e.g. TreehouseReferences-2020-03-30.tgz). Downloaded from https://xena.treehouse.gi.ucsc.edu/download/CARE/TreehouseReferences-2020-03-30.tgz.

## How does this app work?
1. **Download all inputs files** - All input files are downloaded into their respective /home/dnanexus/in/* folder.
2. **Check input files** - Check that the sample specific files are present (expression and qc files) and flatten folder if required (references and tumour compendium).
3. **Run CARE docker** - Run the actual CARE pipeline through its docker image.
4. **Upload output** - Upload all outputs into a DNA Nexus project of choice.

## What are the outputs?
| Output | Class | Description |
|---|---|---|
| `CARE_full_output` | array:file | All files and subfolders from 'outputs/<SAMPLE_ID>/' outputted by CARE.

The results are stored in the folder 'outputs/<SAMPLE_ID>/' and it is uploaded in the project of choice as '<SAMPLE_ID>/'.
Several files are created. Among these, files with outlier gene results are:
- outlier_results_<SAMPLE_ID>: this file contains the report of the N-of-1 analysis.
- expression_plots/<genesymbol_pancancer.png>: expression plot for outlier pan-cancer gene(s).
- expression_plots/<genesymbol_pandisease.png>: expression plot for outlier pan-disease gene(s).
- Correlations_<SAMPLE_ID>_vs_tumor_v10_polyA.tsv: pairwise correlation between single sample and tumour compendium.
- log.txt: log file of the CARE pipeline.
The tool also outputted results with regards druggable genes and geneset analyses: drug-relevant_expression_info_<SAMPLE_ID>.tsv; 
druggableGeneAggregation.txt; top5_gsea_results.txt.

Other output files included:
- One Jupyter Notebook for each step of the analysis containing the code that has been executed.
- The programmatic output of each Jupyter Notebook is stored in the correspondingly-numbered JSON file.
- Summary.html and Slides.html: human-readable format, of the JSON files. The Summary.html includes QC results for normal range of:
  - Uniquely-mapped-exonic-nonduplicated reads (UMEND)/Total reads;
  - Duplicate reads/Total reads;
  - RNA integrity number; Expressed genes (*1000);
  - Pan-cancer up outliers (count); 95th percentile of genes in sample (log2(tpm+1)).
Summary.html and Slides.html are automatically populated with the high-level results of the analysis, but need human intervention to display the clinical data. See [CARE pipeline](https://github.com/UCSC-Treehouse/CARE/tree/25ad888d8b67e80b68e5943d11664fe720e08755) for further information about customisation.


## How to run this app from command line?
```
dx run app-J8x5PG84zFqfgyZfxBgYQYkG \
  -ieggd_treehouse_expression_folder="project-<project-ID>:/path_to_eggdtreehousepipeline_expression_merged" \
  -iumend_qc_json=file-<file-ID> \
  -idiagnosis="Acute myeloid leukemia" \
  --destination project-<projec-ID>:/path_to_folder/ \
  -y --brief
```

## Acknowledgements
We wish to acknowledge the author of the [CARE](https://github.com/UCSC-Treehouse/CARE/tree/master) pipeline for the original tool and their support while building this app. We wish to acknowledge the [UCSC Treehouse Childhood Cancer Initiative](https://treehousegenomics.ucsc.edu/_public-data/) for making the tumour compendium and the reference data publicly available.