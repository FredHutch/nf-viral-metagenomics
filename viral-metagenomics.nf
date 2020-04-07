#!/usr/bin/env nextflow

// Using DSL-2
nextflow.preview.dsl=2

// Preprocessing options
params.adapter = "CTGTCTCTTATACACATCT"
params.qual_threshold = 20
params.min_len = 20
params.max_n_prop = 0.1
params.min_hg_align_score = 20

// Import modules used in the workflow
include join_fastqs_by_specimen from './modules/modules'
include cutadapt from './modules/modules' params(
  adapter: params.adapter,
  min_len: params.min_len,
  max_n_prop: params.max_n_prop,
  qual_threshold: params.qual_threshold
)
include collectCountReads from './modules/modules'
include countReads as countReadsInput from './modules/modules' params(count_reads_label: "raw")
include countReads as countReadsFiltered from './modules/modules' params(count_reads_label: "filtered")
include remove_human from './modules/modules' params(
  min_hg_align_score: params.min_hg_align_score
)
include assemble from './modules/modules'

// Function which prints help message text
def helpMessage() {
    log.info"""
    Usage:

    nextflow run FredHutch/VMAA <ARGUMENTS>
    
    Required Arguments:
      --manifest            CSV file listing samples (see below)
      --output_folder       Folder to place analysis outputs
      --output_prefix       Text used as a prefix for output files
      --human_genome_tar    Indexed human genome, gzipped tarball

    Manifest:
      The manifest is a CSV with a header indicating which samples correspond to which files.
      The file must contain the columns `specimen` and `fastq`. FASTQ files should be gzip-compressed.

    """.stripIndent()
}

workflow {

  // Show help message if the user specifies the --help flag at runtime
  params.help = false
  if (params.help || params.manifest == null || params.output_folder == null || params.output_prefix == null || params.human_genome_tar == null){
      // Invoke the function above which prints the help message
      helpMessage()
      // Exit out and do not run anything else
      exit 1
  }

  // Check to make sure that the manifest file can be found
  if (file(params.manifest).isEmpty()){
    log.info"""
    Cannot find ${params.manifest}
    """.stripIndent()
    exit 1
  }

  // Check to make sure that the human genome tarball can be found
  if (file(params.human_genome_tar).isEmpty()){
    log.info"""
    Cannot find ${params.human_genome_tar}
    """.stripIndent()
    exit 1
  }

  // Parse the manifest file
  fastq_ch = Channel.from(
    file(params.manifest).splitCsv(
          header: true, 
          sep: ","
      )
  )

  // First thing, join together files which are from the same specimen
  join_fastqs_by_specimen(
    fastq_ch
  )

  // Count the number of input reads
  countReadsInput(
    join_fastqs_by_specimen.out
  )

  // Trim adapters, also perform some quality trimming and filtering
  cutadapt(
    join_fastqs_by_specimen.out
  )

  // Subtract any human sequences by alignment against the human genome
  remove_human(
    cutadapt.out,
    file(params.human_genome_tar)
  )

  // Count the number of filtered reads
  countReadsFiltered(
    remove_human.out
  )

  // Join the summary of reads from each step
  collectCountReads(
    countReadsFiltered.out.mix(
      countReadsInput.out
    ).toSortedList()
  ) 

  // Perform de novo assembly on the combined set of reads
  assemble(
    remove_human.out.map {
      r -> r[1]
    }.toSortedList()
  )

  // Count the number of reads which pass human read filtering

}