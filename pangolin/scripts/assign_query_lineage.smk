from Bio import SeqIO
from Bio import Phylo
import sys

config["query_sequences"]=[i for i in config["query_sequences"].split(',')]

rule all:
    input:
        config["outdir"] + "/lineage_report.csv"

rule expand_query_fasta:
    input:
        config["query_fasta"]
    params:
        config["query_sequences"]
    output:
        temp(expand(config["outdir"] + '/temp/expanded_query/{query}.fasta',query=config["query_sequences"]))
    run:
        for record in SeqIO.parse(input[0],"fasta"):
            with open(config["outdir"] + f'/temp/expanded_query/{record.id}.fasta',"w") as fw:
                fw.write(f">{record.id}\n{record.seq}\n")

rule profile_align_query:
    input:
        aln = config["representative_aln"],
        query = config["outdir"] + '/temp/expanded_query/{query}.fasta'
    output:
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta")
    shell:
        "mafft-profile {input.aln:q} {input.query:q} > {output:q}"

rule iqtree_with_guide_tree:
    input:
        profile_aln = rules.profile_align_query.output,
        guide_tree = config["guide_tree"]
    output:
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.treefile"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.parstree"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.splits.nex"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.contree"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.log"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.ckp.gz"),
        temp(config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.iqtree")
    run:
        iqtree_check = output[0].rstrip("treefile") + "iqtree"
        if os.path.exists(iqtree_check):
            print("Tree exists, going to rerun", iqtree_check)
            shell("iqtree -s {input.profile_aln:q} -bb 1000 -au -alrt 1000 -m HKY -g {input.guide_tree:q} -quiet -o 'outgroup_A' -redo")
        else:
            shell("iqtree -s {input.profile_aln:q} -bb 1000 -au -alrt 1000 -m HKY -g {input.guide_tree:q} -quiet -o 'outgroup_A'")

rule to_nexus:
    input:
        rules.iqtree_with_guide_tree.output
    output:
        temp(config["outdir"] + "/temp/query_alignments/{query}.nexus.tree")
    run:
        Phylo.convert(input[0], 'newick', output[0], 'nexus')

rule assign_lineage:
    input:
        tree = rules.to_nexus.output,
    params:
        query = "{query}"
    output:
        temp(config["outdir"] + "/temp/{query}.txt")
    shell:
        """
        assign_lineage.py  --separator '_' --index 1 \
        --collapse_to_polytomies --taxon '{params.query}' \
        --input {input.tree:q} --output {output:q}
        """
        
rule gather_reports:
    input:
        reports = expand(config["outdir"] + "/temp/{query}.txt", query=config["query_sequences"]),
        key=config["key"]
    output:
        config["outdir"] + "/lineage_report.csv"
    run:
        key_dict = {}
        with open(input.key, "r") as f:
            for l in f:
                l = l.rstrip('\n')
                taxon,key = l.split(",")
                key_dict[key] = taxon

        fw=open(output[0],"w")

        fw.write("taxon,lineage,SH-alrt,UFbootstrap\n")
        for lineage_report in input.reports:
            
            with open(lineage_report, "r") as f:
                for l in f:
                    l=l.rstrip()
                    tokens = l.split(",")
                    lineage,support = tokens[1],tokens[2]
                    taxon = key_dict[tokens[0]]
                    bootstrap = ""
                    print(support)
                    support = support.split("/")
                    if len(support) == 3: 
                        old,alrt,ufboot = support
                        bootstrap = ufboot.split('.')[0]
                        alrt = alrt.split('.')[0]
                        print("alrt",alrt,"bootstrap",bootstrap)
                    elif len(support) == 2:
                        alrt,ufboot = support
                        bootstrap = ufboot.split('.')[0]
                        alrt = alrt.split('.')[0]
                        print("alrt",alrt,"bootstrap",bootstrap)
                    else:
                        alrt=0
                        bootstrap=0

                    fw.write(f"{taxon},{lineage},{alrt},{bootstrap}\n")
        fw.close()

