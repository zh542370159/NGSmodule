#!/usr/bin/env bash

###### check_logfile <sample> <tool> <logfile> ######
color_echo() {
  local color=$1
  local text=$2
  if [[ $color == "red" ]]; then
    echo -e "\033[31m$text\033[0m"
  elif [[ $color == "green" ]]; then
    echo -e "\033[32m$text\033[0m"
  elif [[ $color == "yellow" ]]; then
    echo -e "\033[33m$text\033[0m"
  elif [[ $color == "blue" ]]; then
    echo -e "\033[34m$text\033[0m"
  fi
}

###### processbar <current> <total> <label> ######
processbar() {
  local current=$1
  local total=$2
  local label=$3
  local maxlen=60
  local barlen=50
  local perclen=14
  local format="%-${barlen}s%$((maxlen - barlen))s %s"
  local perc="[$current/$total]"
  local progress=$((current * barlen / total))
  local prog=$(for i in $(seq 0 $progress); do printf '='; done)
  printf "\r$format\n" $prog $perc $label
}
bar=0

###### check_logfile <sample> <tool> <logfile> ######
check_logfile() {
  local sample=$1
  local tool=$2
  local logfile=$3

  if [[ $(grep -iP "(error)|(terrible)|(corrupted)|(unexpected)|(denied)|(refused)|(unrecognized)|(no such file or directory)" ${logfile}) ]]; then
    color_echo "red" "ERROR! ${sample}: Detected problems in ${tool} logfile: ${logfile} ; Skipped the remaining steps."
    return 1
  else
    color_echo "blue" "+++++ ${sample}: ${tool} done +++++"
    return 0
  fi
}

################################################################################################################

work_dir=$maindir/NGSmodule_work/
if [[ ! -d $work_dir ]] && [[ $1 != "prepare" ]]; then
  color_echo "red" "Error! Can not find the work_dir: $work_dir\nPlease run 'NGSmodule PrepareWorkDir -c <Config_file>' first!"
  exit 1
fi

declare -A Species_arr=(["human"]="Homo_sapiens" ["mouse"]="Mus_musculus" ["machin"]="Macaca_fascicularis" ["rhesus"]="Macaca_mulatta" ["fly"]="Drosophila_melanogaster")

types=("rna" "dna" "BSdna")
if [[ " ${types[*]} " != *" $SequenceType "* ]]; then
  color_echo "red" "ERROR! SequenceType is wrong.\nPlease check theParamaters in your ConfigFile.\n"
  exit 1
fi

if [[ $SortmeRNA_ref_direct == "" ]]; then
  SortmeRNA_ref="$SortmeRNA_Dir/$SortmeRNA_Type.${Species_arr[$Species]}.${SortmeRNA_DataVersion}.fa"
else
  SortmeRNA_ref=$SortmeRNA_ref_direct
fi

if [[ "$SequenceType" == "BSdna" ]]; then
  FastqScreen_mode="--bisulfite"
else
  FastqScreen_mode=""
fi

if [[ $Genome_direct == "" ]]; then
  genome="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/WholeGenomeFasta/$Genome_name"
else
  genome=$Genome_direct
fi

if [[ $GTF_direct == "" ]]; then
  gtf="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Annotation/Genes/genes.gtf"
else
  gtf=$GTF_direct
fi

bwa_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/BWAIndex/$Genome_name"
bowtie_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/BowtieIndex/${Genome_name%%.fa}"
bowtie2_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/Bowtie2Index/${Genome_name%%.fa}"
hisat2_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/Hisat2Index/${Genome_name%%.fa}"
star_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/STARIndex/${Genome_name%%.fa}"
bismark_bowtie2_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/BismarkIndex/${Genome_name%%.fa}/bowtie2"
bismark_hisat2_index="$iGenomes_Dir/${Species_arr[$Species]}/$Database/$Genome_build/Sequence/BismarkIndex/${Genome_name%%.fa}/hisat2"
tophat2_index=$bowtie2_index

if [[ $Index_direct == "" ]]; then
  eval "index=\${${Aligner}_index}"
else
  index=$Index_direct
fi

############# Load SampleInfoFile ###################################################################
declare -A Sample_dict
declare -A Layout_dict
if [[ -f $SampleInfoFile ]]; then
  while IFS=',' read -r RunID SampleID Group Layout BatchID BatchInfo Other; do
    Sample_dict[$RunID]=$SampleID
    Layout_dict[$SampleID]=$Layout
  done <$SampleInfoFile
else
  color_echo "red" "ERROR! Cannot find SampleInfoFile: $SampleInfoFile. Please check your config!\n"
  exit 1
fi

###### START ######
if [[ -d $work_dir ]]; then
  arr=($(find $work_dir -mindepth 1 -maxdepth 1 -type l -o -type d -printf '%P\n' | grep -P "$SampleGrepPattern"))
  total_task=${#arr[@]}
  if [[ "$ntask_per_run" =~ ^[0-9]+$ ]]; then
    ntask_per_run=$ntask_per_run
  elif [[ "$ntask_per_run" = "ALL" ]]; then
    if ((total_task > total_threads)); then
      ntask_per_run=$total_threads
    else
      ntask_per_run=$total_task
    fi
  else
    color_echo "red" "ERROR! ntask_per_run should be 'ALL' or an interger!"
    exit 1
  fi
  threads=$((($total_threads + $ntask_per_run) / $ntask_per_run - 1))

  if ((threads > 120)); then
    threads=120
  else
    threads=$threads
  fi

  if ((threads > 16)); then
    threads_fastp=16
  else
    threads_fastp=$threads
  fi

  if ((threads > 64)); then
    threads_featurecounts=64
  else
    threads_featurecounts=$threads
  fi

  ###### fifo ######
  tempfifo=$$.fifo
  trap "exec 1000>&-;exec 1000<&-;rm -f $tempfifo;exit 0" SIGINT SIGTERM EXIT
  mkfifo $tempfifo
  exec 1000<>$tempfifo
  rm -f $tempfifo
  for ((i = 1; i <= $ntask_per_run; i++)); do
    echo >&1000
  done

  ###### temp file ######
  tmpfile=$(mktemp /tmp/NGSmodule.XXXXXXXXXXXXXX) || exit 1
  trap "rm -f $tmpfile;exit 0" SIGINT SIGTERM EXIT

else

  total_task="Waiting for the preparation of the workdir"
  ntask_per_run="Waiting for the preparation of the workdir"
  threads="1"
fi

################################################################################################################
echo -e "########################### Global config patameters ###########################\n"
echo -e "  SequenceType: $SequenceType\n  maindir: ${maindir}\n  rawdata_dir: ${rawdata_dir}\n  work_dir: ${work_dir}\n  SampleInfoFile: ${SampleInfoFile}\n  SampleGrepPattern: ${SampleGrepPattern}\n\n  Total_tasks: ${total_task}\n  nTask_per_run: ${ntask_per_run}\n  Total_threads: ${total_threads}\n  Threads_per_task: ${threads} (max=120)\n"
echo -e "################################################################################\n\n\n"
