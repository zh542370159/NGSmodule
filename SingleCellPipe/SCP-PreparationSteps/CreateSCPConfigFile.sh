#!/usr/bin/env bash

if [[ $1 != "" ]];then
    ConfigFile=$1
    if [[ -f $ConfigFile ]];then
        tmp=(`date +"%Y%m%d%H%M%S"`)
        mv ${ConfigFile} bk_${tmp}_${ConfigFile}
    fi
else
    tmp=(`date +"%Y%m%d%H%M%S"`)
    ConfigFile=temp_${tmp}.config
fi

cat <<- EOF >$ConfigFile
############# Global Paramaters ###########################################################################
maindir="$(pwd)"        ## Absolute path of your project directory.
rawdata_dir="$(pwd)/rawdata/"
total_threads=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)                             ## Total threads.
total_memory=$(free -g | awk 'NR==2 {print $7}')                             ## Total memory(gigabytes).
ntask_per_run="ALL"
SampleInfoFile="$(pwd)/temp_Sample_info.csv" ## Absolute path of a .csv SampleInfoFile.
SampleGrepPattern=""                          ## Optional. Perl-compatible regexps used for matching the SampleID under the NGSmodule_work directory.
force_complete="FALSE"

############# CreateWorkDir Paramaters ###################################################################
### raw_fastq_file_name= LibraryIdPattern  + SufixPattern
### Example: ESC_20200911NB_S244_L004_R1_001.fastq.gz
### LibraryIdPattern=".*"
### SufixPattern="_2020.*\.fastq\.gz"
RunIDPattern=".*"                                                          ## This pattern must could be matched with the LibraryId after excluding Sufix.    
R1_SufixPattern="_2020.*_S\d+_L\d+_R1_\d+\.((fastq)|(fq))\.gz"             ## Must start with and end with a fixed string. 
R2_SufixPattern="_2020.*_S\d+_L\d+_R2_\d+\.((fastq)|(fq))\.gz"             ## Must start with and end with a fixed string. 
R1_to_R2="_R1_/_R2_"

############# Cellranger Paramaters #######################################################################
### FastqScreen ###
FastqScreen_config="/data/database/FastQ_Screen/FastQ_Screen_Genomes/fastq_screen.conf"

### cellranger ###
cellranger_ref="/data/database/CellRanger/refdata-gex-GRCh38-2020-A"

### velocyto and dropEst ###
dropEst_config="/home/zhanghao/Program/NGS/SingleCell/dropEst/configs/10x_v3.xml"
gene_gtf="\$cellranger_ref/genes/genes.gtf"
rmsk_gtf="\$cellranger_ref/genes/rmsk.gtf"

############# Intergration #######################################################################
### base parameters ###
datasets="ESC,iPSC,PGCd6,CellLine1,CellLine2;"
species="Homo_sapiens"                           # Homo_sapiens,Mus_musculus,Macaca_fascicularis,Macaca_mulatta,Drosophila_melanogaster 
exogenous_genes="GFP"

### cell-filtering ###
cell_calling_methodNum=3
mito_threshold=0.2

### integration ###
HVF_source="separate"
nHVF=4000
anchor_dims=30
integrate_dims=30

### clustering ###
maxPC=100
resolution=1


EOF

echo -e "ConfigFile: $ConfigFile\n"
echo -e "\n****************** CreateSCPConfigFile Finished ******************\n"
