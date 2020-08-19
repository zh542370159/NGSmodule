#!/usr/bin/env bash
trap 'trap - SIGTERM && kill -- -$$;kill $(jobs -pr);kill 0' SIGINT SIGTERM

#### User can prepare the SRP meta file using the command 'pysradb srp-to-srr --detailed --desc --expand --saveto ${SRP}.tsv ${SRP}'
#### Requirement:
#### sra-tools (https://github.com/ncbi/sra-tools)
#### pigz (https://zlib.net/pigz)
#### reformat (https://jgi.doe.gov/data-and-tools/bbtools/bb-tools-user-guide/reformat-guide)

#############################  Paramaters #############################
rawdata_dir="$(pwd)/rawdata/"
SRPfile="$(pwd)/SRP_meta_file.tsv"
ifs='\t'
threads=4
ntask_per_run=90
force_process="FALSE"

########################################################################

###### fifo ######
tempfifo=$$.fifo
trap "exec 1000>&-;exec 1000<&-;exit 0" 2
mkfifo $tempfifo
exec 1000<>$tempfifo
rm -rf $tempfifo
for ((i = 1; i <= $ntask_per_run; i++)); do
  echo >&1000
done

if [[ ! -d $rawdata_dir ]]; then
  mkdir -p $rawdata_dir
fi

if [[ ! -f $SRPfile ]]; then
  echo "ERROR! No such file: $SRPfile"
  exit 1
fi

var_extract=$(awk -F $ifs '
  NR==1 {
      for (i=1; i<=NF; i++) {
          f[$i] = i
      }
  }
  { print $(f["study_accession"]) "$ifs" $(f["run_accession"]) "$ifs" $(f["experiment_accession"]) "$ifs" $(f["sample_accession"]) "$ifs" $(f["run_total_spots"]) }
  ' "$SRPfile")

while IFS=$ifs read line; do
  srp=$(awk -F "$ifs" '{print $1}' <<<"$line")
  srr=$(awk -F "$ifs" '{print $2}' <<<"$line")
  if [[ "$srr" =~ SRR* ]]; then
    {
      while [[ ! -e $rawdata_dir/$srp/$srr/$srr.sra ]] || [[ -e $rawdata_dir/$srp/$srr/$srr.sra.tmp ]] || [[ -e $rawdata_dir/$srp/$srr/$srr.sra.lock ]]; do
        echo -e "+++++ $srp/$srr: Prefetching SRR +++++"
        cd $rawdata_dir
        prefetch --output-directory ${srp} --max-size 1000000000000 ${srr}
        sleep 60
      done
    } &
  fi
done <<<"$var_extract"

line_count=1
total_count=$(cat "$SRPfile" | wc -l)

while IFS=$ifs read line; do
  srp=$(awk -F "$ifs" '{print $1}' <<<"$line")
  srr=$(awk -F "$ifs" '{print $2}' <<<"$line")
  srx=$(awk -F "$ifs" '{print $3}' <<<"$line")
  srs=$(awk -F "$ifs" '{print $4}' <<<"$line")
  nreads=$(awk -F "$ifs" '{print $5}' <<<"$line")

  echo -e "########### $line_count/$total_count ###########"
  ((line_count++))
  echo $srp/$srr

  if [[ "$srr" =~ SRR* ]]; then
    read -u1000
    {

      force=${force_process}
      status="uncompleted"
      attempt=0

      while [[ $status == "uncompleted" ]] && (("$attempt" <= 1)); do
        if [[ -e $rawdata_dir/$srp/$srr/$srr.sra ]] && [[ ! -e $rawdata_dir/$srp/$srr/$srr.sra.tmp ]] && [[ ! -e $rawdata_dir/$srp/$srr/$srr.sra.lock ]]; then
          ((attempt++))
          if [[ $attempt != 1 ]]; then
            echo -e "+++++ $srp/$srr: Number of attempts: $attempt +++++"
          fi

          echo -e "+++++ $srp/$srr: Processing sra file +++++"
          cd $rawdata_dir/$srp/$srr

          if [[ $force == "TRUE" ]]; then
            rm -f $rawdata_dir/$srp/$srr/fasterq_dump.log $rawdata_dir/$srp/$srr/fasterq_dump_process.log $rawdata_dir/$srp/$srr/pigz.log $rawdata_dir/$srp/$srr/reformat_vpair.log
          fi

          if [[ ! -f $rawdata_dir/$srp/$srr/fasterq_dump.log ]]; then
            rm -rf ./fasterq.tmp*
            fasterq-dump -f --threads $threads --split-3 ${srr}.sra -o $srr 2>$rawdata_dir/$srp/$srr/fasterq_dump_process.log
            if [ -e ${srr} ]; then
              mv ${srr} ${srr}.fastq
            fi
            echo -e "fasterq-dump finished" >$rawdata_dir/$srp/$srr/fasterq_dump.log
            echo -e "+++++ $srp/$srr: fasterq-dump done +++++"
          else
            echo -e "+++++ $srp/$srr: fasterq-dump skipped +++++"
          fi

          if [[ ! -f $rawdata_dir/$srp/$srr/pigz.log ]] && [[ $(ls ./ | grep -E "(*.fastq$)|(*.fq$)") ]]; then
            ls ./ | grep -E "(*.fastq$)|(*.fq$)" | xargs -i pigz -f --processes $threads {}
            echo -e "pigz finished" >$rawdata_dir/$srp/$srr/pigz.log
            echo -e "+++++ $srp/$srr: pigz done +++++"
          else
            echo -e "+++++ $srp/$srr: pigz skipped +++++"
          fi

          if [[ -f ${srr}_1.fastq.gz ]] && [[ -f ${srr}_2.fastq.gz ]]; then

            if [[ ! -f $rawdata_dir/$srp/$srr/reformat_vpair.log ]] || [[ ! $(grep "Names appear to be correctly paired" $rawdata_dir/$srp/$srr/reformat_vpair.log) ]]; then
              reformat.sh in1=${srr}_1.fastq.gz in2=${srr}_2.fastq.gz vpair allowidenticalnames=t 2>$rawdata_dir/$srp/$srr/reformat_vpair.log
            fi

            fq1_nlines=$(zcat ${srr}_1.fastq.gz | wc -l)

            if [[ ! $(grep "Names appear to be correctly paired" $rawdata_dir/$srp/$srr/reformat_vpair.log) ]]; then
              fq2_nlines=$(zcat ${srr}_2.fastq.gz | wc -l)
              if [[ $fq1_nlines == $((nreads * 4)) ]] && [[ $fq1_nlines == $fq2_nlines ]]; then
                echo -e "fq1_nlines:$fq1_nlines\nfq2_nlines:$fq2_nlines\nNames appear to be correctly paired(custom)" >>$rawdata_dir/$srp/$srr/reformat_vpair.log
                status="completed"
                echo -e "+++++ $srp/$srr: Processing completed +++++"
              else
                echo -e "fq1_nlines:$fq1_nlines\nfq2_nlines:$fq2_nlines\n" >>$rawdata_dir/$srp/$srr/reformat_vpair.log
                force="TRUE"
                status="uncompleted"
                echo -e "Warning! $srp/$srr has different numbers of lines between paired files: fq1=$fq1_nlines/ fq2=$fq2_nlines or with that SRA meta file recorded: fq1=$fq1_nlines / recorded=$((nreads * 4))"
              fi
            else
              if [[ $fq1_nlines == $((nreads * 4)) ]]; then
                status="completed"
                echo -e "+++++ $srp/$srr: Processing completed +++++"
              else
                force="TRUE"
                status="uncompleted"
                echo -e "Warning! $srp/$srr has different numbers of lines with that SRA meta file recorded: fq1=$fq1_nlines / recorded=$((nreads * 4))"
              fi
            fi

          elif [[ -f ${srr}.fastq.gz ]]; then
            fq1_nlines=$(zcat ${srr}.fastq.gz | wc -l)
            if [[ $fq1_nlines == $((nreads * 4)) ]]; then
              status="completed"
              echo -e "+++++ $srp/$srr: Processing completed +++++"
            else
              force="TRUE"
              status="uncompleted"
              echo -e "Warning! $srp/$srr has different numbers of lines with that SRA meta file recorded: fq1=$fq1_nlines / recorded=$((nreads * 4))"
            fi
          else
            force="TRUE"
            status="uncompleted"
            echo -e "Warning! Can not find fastq.gz file! $srp/$srr has to restart the processing."
          fi

        else
          sleep 60
        fi
      done

      if [[ $status == "uncompleted" ]]; then
        text="ERROR! $srp/$srr interrupted. Please check the processing log or re-download the SRA file."
        echo -e "\033[31m$text\033[0m"
      fi

      echo >&1000
    } &

  fi

done <<<"$var_extract"

wait
echo "done"
