#!/usr/bin/env bash

#######################################################################################
trap_add 'trap - SIGTERM && kill -- -$$' SIGINT SIGTERM

bwa &>/dev/null
[ $? -eq 127 ] && {
  echo -e "Cannot find the command bwa.\n"
  exit 1
}
bowtie --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command bowtie.\n"
  exit 1
}
hisat2 --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command hisat2.\n"
  exit 1
}
STAR --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command STAR.\n"
  exit 1
}
bismark --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command bismark.\n"
  exit 1
}
samtools --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command samtools.\n"
  exit 1
}
sambamba --version &>/dev/null
[ $? -ne 0 ] && {
  echo -e "Cannot find the command sambamba.\n"
  exit 1
}
picard &>/dev/null
[ $? -eq 127 ] && {
  echo -e "Cannot find the command picard.\n"
  exit 1
}
bam &>/dev/null
[ $? -eq 127 ] && {
  echo -e "Cannot find the command bam. User can install mosdepth by 'conda install -c bioconda bamutil'.\n"
  exit 1
}

aligners=("bwa" "bowtie" "bowtie2" "hisat2" "tophat2" "star" "bismark_bowtie2" "bismark_hisat2")
if [[ " ${aligners[*]} " != *" $Aligner "* ]]; then
  color_echo "red" "ERROR! Aligner is wrong.\nPlease check theParamaters in your ConfigFile.\n"
  exit 1
fi

if [[ "$SequenceType" == "BSdna" ]] && [[ ! "$Aligner" =~ bismark_* ]]; then
  color_echo "red" "ERROR! Aligner must be bismark_bowtie2 or bismark_hisat2 for the SequenceType 'BSdna'."
  exit 1
fi

if [[ ! "$SequenceType" == "BSdna" ]] && [[ "$Aligner" =~ bismark_* ]]; then
  color_echo "red" "ERROR! SequenceType must be BSdna for the Aligner '$Aligner'."
  exit 1
fi

if [[ ! -f $genome ]]; then
  color_echo "red" "ERROR! Cannot find the genome file: $genome\nPlease check the Alignment Paramaters in your ConfigFile.\n"
  exit 1
elif [[ ! -f $gtf ]]; then
  color_echo "red" "ERROR! Cannot find the gtf file: $gtf\nPlease check the Alignment Paramaters in your ConfigFile.\n"
  exit 1
fi

echo -e "############################# Alignment Parameters #############################\n"
echo -e "  SequenceType: ${SequenceType}\n  Aligner: ${Aligner}\n"
echo -e "  Genome_File: ${genome}\n  GTF_File: ${gtf}\n  Aligner_Index: ${index}\n"
echo -e "################################################################################\n"

echo -e "****************** Start Alignment ******************\n"
SECONDS=0

for sample in "${arr[@]}"; do
  read -u1000
  {
    dir=$work_dir/$sample
    mkdir -p $dir/$Aligner
    cd $dir/$Aligner

    Layout=${Layout_dict[${sample}]}
    force=${force_complete}
    status="uncompleted"
    attempt=0

    echo "+++++ ${sample} +++++"

    while [[ $status == "uncompleted" ]] && (("$attempt" <= 1)); do
      ((attempt++))
      if [[ $attempt != 1 ]]; then
        echo -e "+++++ ${sample}: Number of attempts: $attempt +++++"
      fi

      ### clear existed logs
      existlogs=()
      while IFS='' read -r line; do
        existlogs+=("$line")
      done < <(find "${dir}" -name "AlignmentStatus.log" -o -name "BAMprocessStatus.log")
      if ((${#existlogs[*]} >= 1)); then
        for existlog in "${existlogs[@]}"; do
          if [[ $(grep -iP "${error_pattern}" "${existlog}") ]] || [[ ! $(grep -iP "${complete_pattern}" "${existlog}") ]]; then
            color_echo "yellow" "Warning! ${sample}: Detected problems in logfile: ${existlog}."
            rm -f "${existlog}"
          fi
          if [[ $force == "TRUE" ]]; then
            color_echo "yellow" "Warning! ${sample}: Force to perform a complete workflow."
            rm -f "${existlog}"
          fi
        done
      fi

      check_logfile "$sample" "Alignment" "$dir"/"$Aligner"/AlignmentStatus.log "$error_pattern" "$complete_pattern" "precheck"
      if [[ $? == 1 ]]; then

        if [[ $Layout == "SE" ]]; then
          fq1=$dir/${sample}_trim.fq.gz
          if [[ "$Aligner" = "bwa" ]]; then
            bwa mem -t $threads -M $index ${fq1} | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "bowtie" ]]; then
            bowtie -p $threads -1 ${fq1} -l 22 --fullref --chunkmbs 512 --best --strata -m 20 -n 2 --mm $index -S | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "bowtie2" ]]; then
            bowtie2 -p $threads -x $index -1 ${fq1} 2>${sample}.${Aligner}.log | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "hisat2" ]]; then
            hisat2 -p $threads -x $index -U ${fq1} --new-summary 2>${sample}.${Aligner}.log | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "tophat2" ]]; then
            tophat2 -p $threads --GTF $gtf --output-dir ./ $index ${fq1}
            samtools view -@ $threads -Shb accepted_hits.bam | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            rm -f accepted_hits.bam
          elif [[ "$Aligner" == "star" ]]; then
            STAR --runThreadN $threads --genomeDir $index --readFilesIn ${fq1} --genomeLoad LoadAndKeep --limitBAMsortRAM 10000000000 \
            --outSAMunmapped Within --outFilterType BySJout --outSAMattributes NH HI AS NM MD \
            --outFilterMultimapNmax 20 --outFilterMismatchNmax 999 --outFilterMismatchNoverReadLmax 0.04 \
            --alignIntronMin 20 --alignIntronMax 1000000 --alignMatesGapMax 1000000 \
            --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 --sjdbScore 1 --readFilesCommand zcat \
            --outSAMtype BAM SortedByCoordinate --quantMode TranscriptomeSAM
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            samtools view -@ $threads -Shb Aligned.sortedByCoord.out.bam | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            rm -f Aligned.sortedByCoord.out.bam
          elif [[ "$Aligner" == "bismark_bowtie2" ]]; then
            bismark --bowtie2 --multicore $((($threads) / 8)) -p 3 --genome $index ${fq1} --quiet \
            --non_directional --nucleotide_coverage \
            --output_dir $dir/$Aligner 2>$dir/$Aligner/bismark.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            for file in ./*_trim*; do mv $file ${file//_trim/}; done
          elif [[ "$Aligner" == "bismark_hisat2" ]]; then
            bismark --hisat2 --multicore $((($threads) / 8)) -p 3 --genome $index ${fq1} --quiet \
            --non_directional --nucleotide_coverage \
            --output_dir $dir/$Aligner 2>$dir/$Aligner/bismark.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            for file in ./*_trim*; do mv $file ${file//_trim/}; done
          fi

        elif [[ $Layout == "PE" ]]; then
          fq1=$dir/${sample}_1_trim.fq.gz
          fq2=$dir/${sample}_2_trim.fq.gz
          if [[ "$Aligner" == "bwa" ]]; then
            bwa mem -t $threads -M $index ${fq1} ${fq2} | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" = "bowtie" ]]; then
            bowtie -p $threads -1 ${fq1} -2 ${fq2} -l 22 --fullref --chunkmbs 512 --best --strata -m 20 -n 2 --mm $index -S | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "bowtie2" ]]; then
            bowtie2 -p $threads -x $index -1 ${fq1} -2 ${fq2} 2>${sample}.${Aligner}.log | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "hisat2" ]]; then
            hisat2 -p $threads -x $index -1 ${fq1} -2 ${fq2} --new-summary 2>${sample}.${Aligner}.log | \
            samtools view -@ $threads -Shb - | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
          elif [[ "$Aligner" == "tophat2" ]]; then
            tophat2 -p $threads --GTF $gtf --output-dir ./ $index ${fq1} ${fq2}
            samtools view -@ $threads -Shb accepted_hits.bam | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            rm -f accepted_hits.bam
          elif [[ "$Aligner" == "star" ]]; then
            STAR --runThreadN $threads --genomeDir $index --readFilesIn ${fq1} ${fq2} --genomeLoad LoadAndKeep --limitBAMsortRAM 10000000000 \
            --outSAMunmapped Within --outFilterType BySJout --outSAMattributes NH HI AS NM MD \
            --outFilterMultimapNmax 20 --outFilterMismatchNmax 999 --outFilterMismatchNoverReadLmax 0.04 \
            --alignIntronMin 20 --alignIntronMax 1000000 --alignMatesGapMax 1000000 \
            --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 --sjdbScore 1 --readFilesCommand zcat \
            --outSAMtype BAM SortedByCoordinate --quantMode TranscriptomeSAM
            samtools view -@ $threads -Shb Aligned.sortedByCoord.out.bam | \
            samtools sort -@ $threads - >${sample}.${Aligner}.bam 2>${sample}.${Aligner}.samtools.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            rm -f Aligned.sortedByCoord.out.bam
          elif [[ "$Aligner" == "bismark_bowtie2" ]]; then
            bismark --bowtie2 --multicore $((($threads) / 8)) -p 3 --genome $index -1 ${fq1} -2 ${fq2} --quiet \
            --non_directional --nucleotide_coverage \
            --output_dir $dir/$Aligner 2>$dir/$Aligner/bismark.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            for file in ./*_1_trim*; do mv $file ${file//_1_trim/}; done
          elif [[ "$Aligner" == "bismark_hisat2" ]]; then
            bismark --hisat2 --multicore $((($threads) / 8)) -p 3 --genome $index -1 ${fq1} -2 ${fq2} --quiet \
            --non_directional --nucleotide_coverage \
            --output_dir $dir/$Aligner 2>$dir/$Aligner/bismark.log
            if [[ $? != 0 ]]; then
              color_echo "yellow" "Warning! ${Aligner} alignment failed."
              continue
            fi
            for file in ./*_1_trim*; do mv $file ${file//_1_trim/}; done
          fi

        else
          color_echo "yellow" "ERROR! ${sample}: Cannot determine the layout of sequencing data!"
          attempt=2
          echo "ERROR! ${sample}: Cannot determine the layout of sequencing data!" >"$dir"/"$Aligner"/AlignmentStatus.log
          continue
        fi

        echo -e "Task completed." >"$dir"/"$Aligner"/AlignmentStatus.log
      fi

      check_logfile "$sample" "Alignment" "$dir"/"$Aligner"/BAMprocessStatus.log "$error_pattern" "$complete_pattern" "precheck"
      if [[ $? == 1 ]]; then

        bam=$(ls ./*.bam)
        samtools quickcheck -v ${bam}
        if [[ $? != 0 ]]; then
          color_echo "yellow" "Warning! $sample: BAM file checked failed."
          force="TRUE"
          continue
        fi

        echo "+++++ Samtools stat: $sample +++++"
        if [[ "$SequenceType" == "BSdna" ]] && [[ "$Aligner" =~ bismark_* ]]; then
          bam=$(ls ./*.bam)
          samtools stats -@ $threads $bam >${bam}.stats
          samtools flagstat -@ $threads $bam >${bam}.flagstat
        else
          samtools index -@ $threads ${sample}.${Aligner}.bam
          samtools stats -@ $threads ${sample}.${Aligner}.bam >${sample}.${Aligner}.bam.stats
          samtools idxstats -@ $threads ${sample}.${Aligner}.bam >${sample}.${Aligner}.bam.idxstats
          samtools flagstat -@ $threads ${sample}.${Aligner}.bam >${sample}.${Aligner}.bam.flagstat
        fi

        if [[ "$SequenceType" == "dna" ]]; then
          echo "+++++ WGS deduplication: $sample +++++"
          sambamba markdup -r -t $threads ${sample}.${Aligner}.bam ${sample}.${Aligner}.dedup.bam
          picard AddOrReplaceReadGroups I=${sample}.${Aligner}.dedup.bam O=${sample}.${Aligner}.dedup.RG.bam RGLB=lib1 RGPL=illumina RGPU=unit1 RGSM=$sample
          picard FixMateInformation I=${sample}.${Aligner}.dedup.RG.bam O=${sample}.${Aligner}.dedup.bam ADD_MATE_CIGAR=true
          rm -f ${sample}.${Aligner}.dedup.RG.bam
          samtools index -@ $threads ${sample}.${Aligner}.dedup.bam
          if [[ $? != 0 ]]; then
            color_echo "yellow" "Warning! $sample: WGS deduplication failed."
            force="TRUE"
            continue
          fi
        fi

        if [[ "$SequenceType" == "rna" ]]; then
          echo "+++++ RNAseq Mark Duplicates: $sample +++++"
          bam dedup --force --noPhoneHome --in ${sample}.${Aligner}.bam --out ${sample}.${Aligner}.markdup.bam --log ${sample}.${Aligner}.markdup.log
          mv ${sample}.${Aligner}.markdup.bam ${sample}.${Aligner}.bam
          samtools index -@ $threads ${sample}.${Aligner}.bam
        fi

        if [[ "$SequenceType" == "BSdna" ]] && [[ "$Aligner" =~ bismark_* ]]; then
          echo "+++++ BS-seq deduplication: $sample +++++"
          mkdir -p $dir/$Aligner/deduplicate_bismark
          bam=$(ls $dir/$Aligner/*.bam)
          deduplicate_bismark --bam $bam --output_dir $dir/$Aligner/deduplicate_bismark 2>$dir/$Aligner/deduplicate_bismark/deduplicate_bismark.log
          if [[ $? != 0 ]]; then
            color_echo "yellow" "Warning! $sample: BS-seq deduplication failed."
            force="TRUE"
            continue
          fi

          echo "+++++ BS-seq methylation extractor: $sample +++++"
          mkdir -p $dir/$Aligner/bismark_methylation_extractor
          bam=$(ls $dir/$Aligner/deduplicate_bismark/*.deduplicated.bam)
          bismark_methylation_extractor --multicore $((($threads) / 2)) --gzip --comprehensive --merge_non_CpG \
          --bedGraph --buffer_size 10G \
          --cytosine_report --genome_folder $index \
          --output $dir/$Aligner/bismark_methylation_extractor $bam 2>$dir/$Aligner/bismark_methylation_extractor/bismark_methylation_extractor.log
          if [[ $? != 0 ]]; then
            color_echo "yellow" "Warning! $sample: BS-seq methylation extractor failed."
            force="TRUE"
            continue
          fi

          echo "+++++ BS-seq html processing report: $sample +++++"
          mkdir -p $dir/$Aligner/bismark2report
          alignment_report=$(ls $dir/$Aligner/*_[SP]E_report.txt)
          dedup_report=$(ls $dir/$Aligner/deduplicate_bismark/*.deduplication_report.txt)
          splitting_report=$(ls $dir/$Aligner/bismark_methylation_extractor/*_splitting_report.txt)
          mbias_report=$(ls $dir/$Aligner/bismark_methylation_extractor/*M-bias.txt)
          nucleotide_report=$(ls $dir/$Aligner/*.nucleotide_stats.txt)
          bismark2report --dir $dir/$Aligner/bismark2report \
          --alignment_report $alignment_report \
          --dedup_report $dedup_report \
          --splitting_report $splitting_report \
          --mbias_report $mbias_report \
          --nucleotide_report $nucleotide_report
                  samtools quickcheck -v ${bam}
          if [[ $? != 0 ]]; then
            color_echo "yellow" "Warning! $sample: BS-seq html report failed."
            force="TRUE"
            continue
          fi
        fi

        echo -e "Task completed." >"$dir"/"$Aligner"/BAMprocessStatus.log
      fi

      status="completed"
      color_echo "blue" "+++++ ${sample}: Alignment completed +++++"

    done

    if [[ "$status" == "completed" ]]; then
      echo "Completed: $sample" >>"$tmpfile"
    else
      echo "Interrupted: $sample" >>"$tmpfile"
      color_echo "red" "ERROR! ${sample} interrupted! Please check the processing log and your raw fastq file."
    fi

    color_echo "green" "***** Completed:$(cat "$tmpfile" | grep "Completed" | uniq | wc -l) | Interrupted:$(cat "$tmpfile" | grep "Interrupted" | uniq | wc -l) | Total:$total_task *****"

    echo >&1000
  } &
  ((bar++))
  processbar $bar $total_task
done
wait

ELAPSED="Elapsed: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
echo -e "\n$ELAPSED"
echo -e "****************** Alignment Done ******************\n"
