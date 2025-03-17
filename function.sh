#!/bin/bash
MONOPHASIC_TYPHIMURIUM_LIST="$(pwd)/database/complete_genomes/monophasic_Typhimurium_list.txt"
function extract_taxon_info() {
local input="$1"
local taxon_name=""
read -ra words <<< "$input"
if [[ "${words[1]}" == "monophasic" ]]; then
taxon_name="Salmonella enterica subsp. enterica serovar monophasic Typhimurium"
elif [[ "${words[1]}" =~ ^[A-Z] || "${words[1]}" =~ ":" ]]; then
taxon_name="Salmonella enterica subsp. enterica serovar ${words[1]}"
else
taxon_name="$input"
fi
echo "$taxon_name"
}

function get_total_genomes_count() {
local input="$1"
local assembly_level="$2"
local total_genomes=0
local query="$(extract_taxon_info "$input")"
if [[ "$query" == "Salmonella enterica subsp. enterica serovar monophasic Typhimurium" ]]; then
while read -r actual_name; do
count=$(( $(ncbi-genome-download bacteria --genera "Salmonella enterica subsp. enterica serovar $actual_name" --assembly-level "$assembly_level" --section genbank --dry-run  | wc -l) - 1 ))
((total_genomes += count))
done < "$MONOPHASIC_TYPHIMURIUM_LIST"
else
total_genomes=$(( $(ncbi-genome-download bacteria --genera "$query" --assembly-level "$assembly_level" --section genbank --dry-run | wc -l) - 1 ))
fi
echo "$total_genomes"
}

function calculate_sample_size_and_iterations(){
local total_genomes="$1"
local max_iterations=20
if [[ "$total_genomes" -eq 0 ]]; then
echo "0 0"
return
fi
if [[ "$total_genomes" -le 100 ]]; then
echo "$total_genomes 1"
return
fi
# Cochran's formula constants
local Z=1.96
local p=0.5
local e=0.05
local n0=$(echo "scale=6; ($Z^2 * $p * (1 - $p)) / ($e^2)" | bc -l)
# Finite population correction (FPC)
local sample_size=$(echo "scale=6; ($n0 * $total_genomes) / ($total_genomes + $n0 -1)" | bc -l)
sample_size=$(echo "$sample_size" | awk '{printf "%.0f", $1}')
# Compute number of iterations using square-root scaling
if [[ "$sample_size" -gt 0 ]]; then
local iterations=$(echo "scale=6; sqrt($total_genomes / (2 * $sample_size))" | bc -l)
iterations=$(echo "$iterations" | awk '{printf "%.0f", $1}')
else
local iterations=1
fi
if [[ "$iterations" -lt 1 ]]; then
iterations=1
elif [[ "$iterations" -gt "$max_iterations" ]]; then
iterations="$max_iterations"
fi
echo "$sample_size $iterations"
}

function download_random_draft_genomes() {
local input="$1"
local sample_size="$2"
local output_dir="$3"
local iteration="$4"
local query="$(extract_taxon_info "$input")"
local taxon_dir_name="${query// /_}"
taxon_dir_name="${taxon_dir_name//./}"
local iteration_dir="${output_dir}/${taxon_dir_name}/genomes_${iteration}"
mkdir -p "$iteration_dir"
local accessions=""
if [[ "$query" == "Salmonella enterica subsp. enterica serovar monophasic Typhimurium" ]]; then
while read -r actual_name; do
accessions+=$(ncbi-genome-download bacteria --genera "Salmonella enterica subsp. enterica serovar $actual_name" --assembly-level contig --section genbank --dry-run | tail -n +2 | awk -F '/' '{print $NF}' | shuf -n "$sample_size" | awk '{print $1}')
done < "$MONOPHASIC_TYPHIMURIUM_LIST"
else
accessions=$(ncbi-genome-download bacteria --genera "$query" --assembly-level contig --section genbank --dry-run | tail -n +2 | awk -F '/' '{print $NF}' | shuf -n "$sample_size" | awk '{print $1}')
fi
echo "$accessions" > "${iteration_dir}/selected_accessions.txt"
datasets download genome accession --inputfile "${iteration_dir}/selected_accessions.txt" --filename "${iteration_dir}/download.zip"
unzip -q -o "${iteration_dir}/download.zip" -d "${iteration_dir}"
find "${iteration_dir}/ncbi_dataset" -type f -name "*_genomic.fna" -exec mv {} "${iteration_dir}" \;
rm "${iteration_dir}/download.zip"
rm -rf "${iteration_dir}/ncbi_dataset"
} 

function perform_blast(){
local query_gene="$1"
local perc_identity="$2"
local output_dir="$3"
local iteration="$4" # only used for draft genomes
local taxon_file="$5"  # only provide for complete genomes, always empty for draft genomes
if [[ -n "$iteration" ]]; then
echo "Processing draft genomes for iteration $iteration"
local taxon_dirs=("${EB_DRAFT_GENOMES_DIR}"/*/)
local taxon=$(basename "${taxon_dirs[0]%/}")
local genome_dir="${EB_DRAFT_GENOMES_DIR}/${taxon}/genomes_${iteration}"
local blast_db="${DRAFT_BLAST_DB_DIR}/${taxon}/iteration_${iteration}"
mkdir -p "$(dirname "$blast_db")"
local concatenated_genome="${genome_dir}/combined.fna"
cat "$genome_dir"/*_genomic.fna > "$concatenated_genome"
makeblastdb -in "$concatenated_genome" -dbtype nucl -out "$blast_db"
local blast_output="${output_dir}/${taxon}/iteration_${iteration}_draft_blast_results.txt"
mkdir -p "$(dirname "$blast_output")"
blastn -query "$query_gene" -db "$blast_db" -out "$blast_output" -outfmt 6 -perc_identity "$perc_identity"
echo "BLAST results saved to: $blast_output"
else
if [[ -n "$taxon_file" ]]; then
while read -r taxon || [[ -n "$taxon" ]]; do
# Skip empty lines
[[ -z "$taxon" ]] && continue
local blast_db_name="${taxon// /_}"
blast_db_name="${blast_db_name//./}"
local blast_db="${BLAST_DB_DIR}/${blast_db_name}"
local blast_output="${output_dir}/${blast_db_name}_complete_blast_results.txt"
blastn -query "$query_gene" -db "$blast_db" -out "$blast_output" -outfmt 6 -perc_identity "$perc_identity"
echo "BLAST results saved to $blast_output"
done < "$taxon_file"
else
echo "No taxon file provided. Processing all pre-built BLAST database"
find "$BLAST_DB_DIR" -name "*.nsq" -exec basename {} .nsq \; | sed -E '/[._][0-9]{2}$/s/[._][0-9]{2}$//' | sort -u | while read -r line; do
local blast_db_name="${taxon// /_}"
blast_db_name="${blast_db_name//./}"
local blast_db="${BLAST_DB_DIR}/${blast_db_name}"
local blast_output="${output_dir}/${blast_db_name}_complete_blast_results.txt"
blastn -query "$query_gene" -db "$blast_db" -out "$blast_output" -outfmt 6 -perc_identity "$perc_identity"
echo "BLAST results saved to $blast_output"
done
fi
fi
echo "BLAST analysis completed. Results saved in: $output_dir"
}

function filter_blast_results() {
local blast_result_file="$1"  # Full path containing blast results
local output_dir="$2"
local coverage_threshold="$3"
local genome_type="$4"
local base_name="$(basename "$blast_result_file")"
if [[ "$genome_type" == "draft" ]]; then
local taxon="$(basename "$(dirname "$blast_result_file")")"
local iteration="$(grep -o '[0-9]\+' <<< "$base_name")"
local filtered_result="${output_dir}/${taxon}/filtered_iteration${iteration}_draft_blast_results.txt"
mkdir -p "$(dirname "$filtered_output")"
awk -v cov="$coverage_threshold" '(($4/($8 - $7 + 1)*100) >= cov) {print $0}' "$blast_result_file" > "$filtered_result"
echo "Filtered BLAST results for draft genomes are saved to $filtered_result"
else
local filtered_result="$output_dir/filtered_${base_name}"
awk -v cov="$coverage_threshold" '(($4/($8 - $7 + 1)*100) >= cov) {print $0}' "$blast_result_file" > "$filtered_result"
echo "Filtered BLAST results for complete genomes are saved to $filtered_result"
fi
}
