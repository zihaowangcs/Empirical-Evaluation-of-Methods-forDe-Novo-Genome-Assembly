#!/bin/bash -x

#
# Example assembly of reads
#

IN1=<datset-directory>.fastq
IN2=<dataset-directory>.fastq

#
# Parameters
#

# Program paths
SGA_BIN=sga
BWA_BIN=bwa
SAMTOOLS_BIN=samtools
BAM2DE_BIN=sga-bam2de.pl
ASTAT_BIN=sga-astat.py
PYTHON_BIN=python2

# The number of threads to use
CPU=16

# Correction k-mer 
CORRECTION_K=41

# The minimum overlap to use when computing the graph.
# The final assembly can be performed with this overlap or greater
MIN_OVERLAP=85

# The overlap value to use for the final assembly
ASSEMBLE_OVERLAP=111

# Branch trim length
TRIM_LENGTH=400

# The minimum length of contigs to include in a scaffold
MIN_CONTIG_LENGTH=200

# The minimum number of reads pairs required to link two contigs
MIN_PAIRS=10

# Check the files are found
file_list="$IN1 $IN2"
for input in $file_list; do
    if [ ! -f $input ]; then
        echo "Error input file $input not found"; exit 1;
    fi
done

#
# Preprocessing
#

# Preprocess the data to remove ambiguous basecalls
$SGA_BIN preprocess --pe-mode 1 -o reads.pp.fastq $IN1 $IN2

#
# Error Correction
#

# Build the index that will be used for error correction
# As the error corrector does not require the reverse BWT, suppress
# construction of the reversed index
$SGA_BIN index -a ropebwt -t $CPU --no-reverse reads.pp.fastq

# Perform k-mer based error correction.
# The k-mer cutoff parameter is learned automatically.
$SGA_BIN correct -k $CORRECTION_K --learn -t $CPU -o reads.ec.fastq reads.pp.fastq


#
# Primary (contig) assembly
#
$SGA_BIN index -a ropebwt -t $CPU reads.ec.fastq

# Remove exact-match duplicates and reads with low-frequency k-mers
$SGA_BIN filter -x 2 -t $CPU reads.ec.fastq

# Compute the structure of the string graph
$SGA_BIN overlap -m $MIN_OVERLAP -t $CPU reads.ec.filter.pass.fa

# Perform the contig assembly
$SGA_BIN assemble -m $ASSEMBLE_OVERLAP --min-branch-length $TRIM_LENGTH -o primary reads.ec.filter.pass.asqg.gz

#
# Scaffolding
#

PRIMARY_CONTIGS=primary-contigs.fa
PRIMARY_GRAPH=primary-graph.asqg.gz

# Align the reads to the contigs
$BWA_BIN index $PRIMARY_CONTIGS
$BWA_BIN aln -t $CPU $PRIMARY_CONTIGS $IN1 > $IN1.sai
$BWA_BIN aln -t $CPU $PRIMARY_CONTIGS $IN2 > $IN2.sai
$BWA_BIN sampe $PRIMARY_CONTIGS $IN1.sai $IN2.sai $IN1 $IN2 | $SAMTOOLS_BIN view -Sb - > libPE.bam

# Convert the BAM file into a set of contig-contig distance estimate
$BAM2DE_BIN -n $MIN_PAIRS -m $MIN_CONTIG_LENGTH --prefix libPE libPE.bam

# Compute copy number estimates of the contigs

$PYTHON_BIN /home/firaol/anaconda3/bin/sga-astat.py -m $MIN_CONTIG_LENGTH libPE.bam > libPE.astat

# Build the scaffolds
$SGA_BIN scaffold -m $MIN_CONTIG_LENGTH -a libPE.astat -o scaffolds.scaf --pe libPE.de $PRIMARY_CONTIGS

# Convert the scaffolds to FASTA format
$SGA_BIN scaffold2fasta --use-overlap --write-unplaced -m $MIN_CONTIG_LENGTH -a $PRIMARY_GRAPH -o sga-scaffolds.fa scaffolds.scaf