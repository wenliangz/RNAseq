## script to analyse eRNA defined by HCILB RNA-seq

pipeline_path=$HOME/neurogen/pipeline/RNAseq
source $pipeline_path/config.txt

cd ~/projects/PD/results/eRNA/externalData/RNAseq

inputBG=/data/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bedGraph

################################################
# eRNA definition:
# 1) density higher than the basal level,  
# 2) summit >0.05 RPM, --> p<0.05 comparing to the transcriptional noise
# 3) located in non-generic regions (e.g. 500bp away from any annotated exons),
# 4) at least 100bp in length,
# 5) not from highly actively transcribing genes (e.g. pre-mRNA, intronic coverage > 50% & exonic coverage >90%)
# 6) q-value<0.05 when comparing with random non-functional background
################################################

#: background region to measure transcriptional noise: genomic regions excluding the known regions with RNA activities (exons+/-500bp, rRNA, CAGE-defined enhancers, promoters)
ANNOTATION=$GENOME/Annotation/Genes
cat $ANNOTATION/gencode.v19.annotation.bed12 $ANNOTATION/knownGene.bed12 $ANNOTATION/NONCODEv4u1_human_lncRNA.bed12 | bed12ToBed6 | cut -f1-3 | grep -v "_" | slopBed -g $GENOME/Sequence/WholeGenomeFasta/genome.fa.fai -b 500 > /tmp/bg.bed
cut -f1-3 $ANNOTATION/rRNA.bed >> /tmp/bg.bed  # rRNA
grep -v track ~/projects/PD/results/eRNA/externalData/CAGE/TSS_human.bed | grep -v "211,211,211" | cut -f1-3 | grep -v "_" | slopBed -g $GENOME/Sequence/WholeGenomeFasta/genome.fa.fai -b 500 >> /tmp/bg.bed # +/-500bp flanking around the CAGE-predicted TSS (downloaded from: http://fantom.gsc.riken.jp/5/datafiles/latest/extra/TSS_classifier/)
cat $ANNOTATION/SINE.bed $ANNOTATION/LINE.bed | cut -f1-3 >> /tmp/bg.bed  # LINE and SINE
cat /tmp/bg.bed | sortBed | mergeBed > ../toExclude.bed
grep -v track ~/projects/PD/results/eRNA/externalData/CAGE/permissive_enhancers.bed | cut -f1-3 >> /tmp/bg.bed # CAGE-enhancer
cat /tmp/bg.bed | sortBed | mergeBed > ../blacklist.bed

# RNAseq signal distribution in the background region
#intersectBed -a $inputBG -b ../blacklist.bed -v | awk '{OFS="\t"; print $3-$2, $4}' | shuf > transcriptional.noise.rpm.txt
intersectBed -a $inputBG -b ../blacklist.bed -v | awk '{OFS="\t"; print $3-$2, $4}' > transcriptional.noise.woLINESINE.rpm.txt

#R
df=read.table("transcriptional.noise.wo.LINESINE.rpm.txt", comment.char = "", nrows = 2000000)
df=log10(as.numeric(do.call('c',apply(df, 1, function(x) rep(x[2],x[1])))))
library(fitdistrplus)
fitn=fitdist(df,'norm')
pdf("transcriptional.noise.distribution.pdf", width=8, height=6)
hist(df, breaks=100, prob=TRUE, xlab='log10(RPM)', main='Distribution of transcriptional noise')
lines(density(df, bw=0.15))
m=round(as.numeric(fitn$estimate[1]),digits=3)
sd=round(as.numeric(fitn$estimate[2]),digits=3)
lines(density(rnorm(n=2000000, mean=m, sd=sd),bw=0.25), col='blue',lty=2)
p=round(qnorm(.05, mean=m, sd=sd, lower.tail = F), digits=3)
lines(y=c(0,0.3),x=c(p,p),col='red')
text(p,0.2,paste0("P(X>",p,") = 0.05\nRPM=10**",p,"=",round(10**p,digits=3)), adj=c(0,0))
legend("topright", c("empirical density curve", paste0("fitted normal distribution \n(mean=",m,", sd=",sd,")")), col=c('black','blue'), lty=c(1,2), bty='n')
dev.off()

# Dsig: 10**-0.997 == 0.101

## any region with RPM density > 0.101
#basalLevel=0.101
#j=`basename ${inputBG/bedGraph/eRNA.bed}`
#awk -vmin=$basalLevel '{OFS="\t"; if($4>min) print $1,$2,$3,".",$4}' $inputBG | mergeBed -d 100 -scores max | intersectBed -a - -b ../toExclude.bed -v > $j
##wc -l $j
##40451 trimmedmean.uniq.normalized.HCILB_SNDA.eRNA.bed

#for i in /data/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bedGraph;
#do
#    basalLevel=`tail -n1 $i | cut -f2 -d'=' | cut -f1 -d' '`
#    echo $i, $basalLevel;
#    j=`basename ${i/bedGraph/eRNA.bed}`
#    awk -vmin=$basalLevel '{OFS="\t"; if($4>=2*min) print $1,$2,$3,".",$4}' $i | mergeBed -scores max | awk '{OFS="\t"; if($4>=0.05) print $1,$2,$3,".",$4}' | mergeBed -d 100 -scores max | intersectBed -a - -b ../toExclude.bed -v > $j &
#done

# step1: any regions with summit RPM > peakLevel and border > baseLevel
basalLevel=`tail -n1 $inputBG | cut -f2 -d'=' | cut -f1`
awk -vmin=$basalLevel '{OFS="\t"; if($4>=min) print $1,$2,$3,".",$4}' $inputBG | mergeBed -scores max > eRNA.tmp1

# step2: summit RPM >=Dsig (density with p<0.05)
Dsig=0.101
awk -vD=$Dsig '{OFS="\t"; if($4>=D) print $1,$2,$3,".",$4}' eRNA.tmp1 | mergeBed -d 100 -scores max > eRNA.tmp2

# step3: located in non-generic regions (e.g. 500bp away from any annotated exons),
intersectBed -a eRNA.tmp2 -b ../toExclude.bed -v > eRNA.tmp3

# step4: length > 100nt
awk '{OFS="\t"; if(($3-$2)>100) print $1,$2,$3,$1"_"$2"_"$3}' eRNA.tmp3 > eRNA.tmp4

# step5: not from highly actively transcribing genes (e.g. pre-mRNA, intronic coverage > 50% & exonic coverage >90%)
# require to run premRNA.sh ahead
intersectBed -a eRNA.tmp4 -b RNAseq.aboveBasal.bigwig.exons-introns.bed -wao | sort -k4,4 -k12,12gr | awk '{OFS="\t"; if($4!=id) {print; id=$4;}}' | cut -f1-4,8-13 | sed 's/\t\./\t-1/g' | awk '{if(($8<0.9 || $9<0.5)) print $0}' | cut -f1-4 > eRNA.tmp5


# step6: calculate the significance of eRNA
#1: create 100,000 random regions (400bp each) as background and calculate their signals
for i in ~/neurogen/rnaseq_PD/run_output/[HI]*_SNDA*/uniq/accepted_hits.normalized.bw ~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw;
do
    bsub -q normal -n 1 "bedtools random -g $GENOME/Annotation/Genes/ChromInfo.txt -l 400 -n 500000 | grep -v chrM | intersectBed -a - -b ../blacklist.bed -v | head -n100000 | bigWigAverageOverBed $i stdin $i.rdbg; bigWigAverageOverBed $i eRNA.tmp5 stdout | cut -f1,5 | sort -k1,1 | awk '{OFS=\"\t\"; print \$1, \$2*1000+0}'> $i.eRNA.RPKM"
done

### 2: distribution of random background, in order to define the cutoff with p=0.0001 significance
R
# significance
path=c("~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw", "~/neurogen/rnaseq_PD/run_output/[HI]*_SNDA*/uniq/accepted_hits.normalized.bw")
pdf("background.RNAseq.cummulative.plot.pdf")

## read in only the 80 subjects/samples (w/ genotype)
IDs=read.table('~/neurogen/rnaseq_PD/results/merged/RNAseqID.wGenotyped.list',stringsAsFactors =F)[,1]
IDs=IDs[grep("^[HI].*_SNDA", IDs)]

EXP=data.frame(); PV=data.frame(); QV=data.frame(); id="locus"
for(i in Sys.glob(path)){
    ii=ifelse(grepl("merged", i), sub(".*merged/(.*).bw.*","\\1", i), sub(".*run_output/(.*)/uniq.*","\\1", i));
    if(! (ii %in% IDs || grepl("trimmedmean",ii))) next;
    print(i)
    # read background
    df=read.table(paste(i,"rdbg",sep="."), header=F)[,5] * 1000  # convert mean RPM to RPKM
    Fn=ecdf(df)
    
    # plot the cummulative plot
    plot(Fn, verticals = TRUE, do.points = FALSE, main=ii, ylim=c(0.99, 1), xlab="RPKM", ylab="cummulative percentage (approx. 1-p)")
    inv_ecdf <- function(f){ x <- environment(f)$x; y <- environment(f)$y; approxfun(y, x)}; g <- inv_ecdf(Fn);
    abline(h=0.999, v=g(0.999), col='red', lty=2, lwd=1)
    points(g(0.999), 0.999, col='red', pch=19)
    text(g(0.999), 0.999, round(g(0.999),2), cex=5, adj=c(0,1))
    
    if(grepl("trimmedmean",ii)) next;
    id=c(id, ii)

    # read expression
    expression=read.table(paste(i,"eRNA.RPKM",sep="."), header=F)
    pvalue=as.numeric(format(1-Fn(expression[,2]), digits=3));
    qvalue=as.numeric(format(p.adjust(pvalue, "BH"), digits=3));
    write.table(cbind(expression[,1:2], pvalue=pvalue, qvalue=qvalue), file=paste(i,"eRNA.RPKM.significance",sep="."), quote=F, sep ="\t", col.names =F, row.names=F)
    
    # merge
    if(ncol(EXP)==0) { EXP=expression; expression[,2]=pvalue; PV=expression; expression[,2]=qvalue; QV=expression; }
    else {EXP=cbind(EXP, expression[,2]); PV=cbind(PV, pvalue); QV=cbind(QV, qvalue); }
}
dev.off()

colnames(EXP)=id; colnames(PV)=id; colnames(QV)=id;
write.table(EXP, "eRNA.80samples.RPKM.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(PV, "eRNA.80samples.pvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(QV, "eRNA.80samples.qvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)

# QV=read.table("eRNA.80samples.qvalue.xls", header=T)
rownames(QV)=QV[,1]; QV=QV[,-1];
rM=rowMeans(QV<=0.05)
pdf("eRNA.80samples.qvalue.hist.pdf", width=8, height=6)
hist(rM, breaks=50, xlim=c(0,1), main="",xlab="Percentage of HC/ILB SNDA samples (out of 80) with q-value <= 0.05", ylab="Count of eRNAs", freq=T)
abline(v=0.25, lty=2, col='red')
dev.off()

write.table(round(rM[rM>0.25],3), "eRNA.80samples.QV0.05.25pc.xls", row.names=T, col.names=F, sep="\t", quote=F)

## R end

awk '{OFS="\t"; split($1,a,"_"); print a[1],a[2],a[3],$1}' eRNA.80samples.QV0.05.25pc.xls > eRNA.bed
rsync -azv eRNA.bed xd010@panda.dipr.partners.org:~/public_html/rnaseq_PD/version2/merged

################################################
# measure the eRNA expression level (raw reads count, RPKM, intron/exon rate of host gene (if any))
################################################

### RPKM (Note: this RPKM is different from the normal RPKM, they might have a factor of read length difference)
# mean0: average over bases with non-covered bases counting as zeroes
#--------

bigWigAverageOverBed ${inputBG/bedGraph/bw} eRNA.bed stdout | cut -f1,5 | sort -k1,1 | awk '{OFS="\t"; print $1, $2*1000+0}' > eRNA.RPKM

### raw reads count for DEseq2
# Note: use '-split' to exclude spliced reads when counting for intronic eRNA
for i in ~/neurogen/rnaseq_PD/run_output/*/uniq/accepted_hits.bam; do bsub -q normal -n 1 $HOME/neurogen/pipeline/RNAseq/modules/_get_readscount_per_region.sh $i eRNA.bed $i.eRNA.rawcount; done

# merge into a big matrix
echo -ne "locus\t" > eRNA.allsamples.rawcount.tab;
ls ~/neurogen/rnaseq_PD/run_output/* -d | xargs -i basename '{}' | sed -n '1{x;d};${H;x;s/\n/\t/g;p};{H}' >> eRNA.allsamples.rawcount.tab
awk '{OFS="\t"; a[FNR] = (a[FNR] ? a[FNR] OFS : "") $5 } END { for(i=1;i<=FNR;i++) print a[i] }' $(ls -1 ~/neurogen/rnaseq_PD/run_output/*/uniq/accepted_hits.bam*rawcount) | paste <(cut -f4 eRNA.bed | sort) - >> eRNA.allsamples.rawcount.tab

# splicing ratio & intron coverage
# run premRNA.sh first
#--------
intersectBed -a eRNA.bed -b RNAseq.aboveBasal.bigwig.exons-introns.bed -wao | sort -k4,4 -k12,12gr | awk '{OFS="\t"; if($4!=id) {print; id=$4;}}' | cut -f1-4,8-13 | sed 's/\t\./\t-1/g' > eRNA.premRNAratio
gawk '{OFS="\t"; if($5!=-1) {$5=gensub("(.*)__ENST.*__(.*)\\..*","\\1__\\2","g",$5);  print}}' eRNA.premRNAratio | cut -f5 | sort | uniq -c | sed -e 's/^[ \t]*//;s/__/\t/g;s/ /\t/g' | sort -k1,1nr > eRNA.premRNAratio.sortbyeRNAcount.tab
awk '$1>=20' eRNA.premRNAratio.sortbyeRNAcount.tab > eRNA.premRNAratio.eRNAcount.gt20.tab


## R
df=read.table("eRNA.premRNAratio", header=F)
colnames(df)=c("chr","start","end","ID", "host_gene","rpkm_exon", "rpkm_intron", "cov_exon", "cov_intron", "splicing_ratio")
attach(df)
length=pmin(end-start,2000)

pdf("eRNA.size.pdf")
hist(length, breaks=1000, freq=F, ylim=c(0,0.004), col='gray', border='gray')
lines(density(length,bw=2),col='green')
lines(density(length[cov_exon>0.9 & cov_intron>0.5],bw=5),col='red')
lines(density(length[cov_exon<=0.9 | cov_intron<=0.5],bw=2),col='blue')

par(mfrow=c(3,1))
hist(length, breaks=1000, freq=F, ylim=c(0,0.004), col='gray', border='gray')
lines(density(length,bw=2),col='green')

hist(length[cov_exon>0.9 & cov_intron>0.5], breaks=500, freq=F, ylim=c(0,0.004))
lines(density(length[cov_exon>0.9 & cov_intron>0.5],bw=5),col='red')

hist(length[cov_exon<=0.9 | cov_intron<=0.5], breaks=1000, freq=F, ylim=c(0,0.004))
lines(density(length[cov_exon<=0.9 | cov_intron<=0.5],bw=2),col='blue')

dev.off()

df=read.table("eRNA.premRNAratio.eRNAcount.gt100.tab")
pdf("eRNA.hostgene.pdf", width=15, height=6)
barplot(df$V1,
    names.arg =df$V2,
    ylab="eRNAs count in host gene",
    las=2, cex.names=.5,
    col=ifelse(grepl("protein_coding",df$V4),"gray","red"),
    space=0.8,
    legend.text = c("protein-coding", "non-protein-coding"),
    args.legend = list(x = "topright", bty = 'n', fill=c("gray","red")))
dev.off()

################################################
# calculate the significance of eRNA
################################################

### 1: create random regions (100,000 regions of 300bp each) for background
### ------------------------------------------------------------

#1b:
for i in ~/neurogen/rnaseq_PD/run_output/[HI]*_SNDA*/uniq/accepted_hits.normalized.bw ~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw;
do
    bsub -q normal -n 1 "bedtools random -g $GENOME/Annotation/Genes/ChromInfo.txt -l 400 -n 500000 | grep -v chrM | intersectBed -a - -b ../blacklist.bed -v | head -n100000 | bigWigAverageOverBed $i stdin $i.rdbg; bigWigAverageOverBed $i eRNA.tmp5 stdout | cut -f1,5 | sort -k1,1 | awk '{OFS=\"\t\"; print \$1, \$2*1000+0}'> $i.eRNA.RPKM"
done


### 2: distribution of random background, in order to define the cutoff with p=0.0001 significance
### ------------------------------------------------------------

R
# significance
path=c("~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw", "~/neurogen/rnaseq_PD/run_output/[HI]*_SNDA*/uniq/accepted_hits.normalized.bw")
pdf("background.RNAseq.cummulative.plot.pdf")

## read in only the 80 subjects/samples (w/ genotype)
IDs=read.table('~/neurogen/rnaseq_PD/results/merged/RNAseqID.wGenotyped.list',stringsAsFactors =F)[,1]
IDs=IDs[grep("^[HI].*_SNDA", IDs)]

EXP=data.frame()
PV=data.frame()
QV=data.frame()
id="locus"
for(i in Sys.glob(path)){
    ii=ifelse(grepl("merged", i), sub(".*merged/(.*).bw.*","\\1", i), sub(".*run_output/(.*)/uniq.*","\\1", i));
    
    if(! (ii %in% IDs || grepl("trimmedmean",ii))) next;
        
    print(i)
    
    # read background
    df=read.table(paste(i,"rdbg",sep="."), header=F)[,5] * 1000  # convert mean RPM to RPKM
    Fn=ecdf(df)
    
    # plot the cummulative plot
    plot(Fn, verticals = TRUE, do.points = FALSE, main=ii, ylim=c(0.99, 1), xlab="RPKM", ylab="cummulative percentage (approx. 1-p)")
    inv_ecdf <- function(f){ x <- environment(f)$x; y <- environment(f)$y; approxfun(y, x)}; g <- inv_ecdf(Fn);
    abline(h=0.999, v=g(0.999), col='red', lty=2, lwd=1)
    points(g(0.999), 0.999, col='red', pch=19)
    text(g(0.999), 0.999, round(g(0.999),2), cex=5, adj=c(0,1))
    
    if(grepl("trimmedmean",ii)) next;
    id=c(id, ii)

    # read expression
    expression=read.table(paste(i,"eRNA.RPKM",sep="."), header=F)
    pvalue=as.numeric(format(1-Fn(expression[,2]), digits=3));
    qvalue=as.numeric(format(p.adjust(pvalue, "BH"), digits=3));
    write.table(cbind(expression[,1:2], pvalue=pvalue, qvalue=qvalue), file=paste(i,"eRNA.RPKM.significance",sep="."), quote=F, sep ="\t", col.names =F, row.names=F)
    
    # merge
    if(ncol(EXP)==0) { EXP=expression; expression[,2]=pvalue; PV=expression; expression[,2]=qvalue; QV=expression; }
    else {EXP=cbind(EXP, expression[,2]); PV=cbind(PV, pvalue); QV=cbind(QV, qvalue); }
}
dev.off()

colnames(EXP)=id; colnames(PV)=id; colnames(QV)=id;
write.table(EXP, "eRNA.80samples.RPKM.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(PV, "eRNA.80samples.pvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(QV, "eRNA.80samples.qvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)

# QV=read.table("eRNA.80samples.qvalue.xls", header=T)
rownames(QV)=QV[,1]; QV=QV[,-1];
rM=rowMeans(QV<=0.05)
pdf("eRNA.80samples.qvalue.hist.pdf", width=8, height=6)
hist(rM, breaks=50, xlim=c(0,1), main="",xlab="Percentage of HC/ILB SNDA samples (out of 80) with q-value <= 0.05", ylab="Count of eRNAs", freq=T)
abline(v=0.25, lty=2, col='red')
dev.off()

write.table(round(rM[rM>0.25],3), "eRNA.80samples.QV0.05.25pc.xls", row.names=T, col.names=F, sep="\t", quote=F)

## R end

awk '{OFS="\t"; split($1,a,"_"); print a[1],a[2],a[3],$1}' eRNA.80samples.QV0.05.25pc.xls | eRNA.final.bed
rsync -azv eRNA.QV0.05.*bed xd010@panda.dipr.partners.org:~/public_html/rnaseq_PD/results/

#############################################################
# final set of signifant eRNAs and their measurement
#############################################################

# filter with length, signifance, and premRNA ratio
sort <(awk '{if(($3-$2)>100 && ($8<0.9 || $9<0.5)) print $4}' eRNA.premRNAratio) <(cut -f1 eRNA.QV0.05.50pc.txt) | uniq -d | awk '{OFS="\t"; split($1,a,"_"); print a[1],a[2],a[3],$1}' > eRNAfinal.bed
for i in eRNA.allsamples.*tab; do echo $i; head -n1 $i > ${i/eRNA/eRNAfinal}; cut -f4 eRNAfinal.bed | fgrep -wf - $i >> ${i/eRNA/eRNAfinal}; done

#############################################################
# clustering of eRNA expression
#############################################################
Rscript eRNA.clustering.R eRNAfinal.allsamples.RPKM.tab
Rscript eRNA.clustering.R eRNAfinal.allsamples.rawcount.tab

#############################################################
# eQTL of eRNA (by GL)
#############################################################

#############################################################
# DESeq of eRNA (by BZ)
#############################################################

#############################################################
# how much RNA-defined eRNA overlap with other enhancers --> venn diagram
#############################################################
# Roadmap Epigenomics enhancers for substantial nigro (https://sites.google.com/site/anshulkundaje/projects/epigenomeroadmap)
curl -s http://www.broadinstitute.org/~anshul/projects/roadmap/segmentations/models/coreMarks/parallel/set2/final/E074_15_coreMarks_segments.bed | awk '$4~/E6|E7|E12/' | intersectBed -a eRNAfinal.bed -b stdin -c | sort -k4,4 > eRNAfinal.overlap.txt

# CAGE-defined enhancers
intersectBed -a eRNAfinal.bed -b ../CAGE/permissive_enhancers.bed -c | sort -k4,4 | cut -f5 | paste eRNAfinal.overlap.txt - > tmp.list
mv tmp.list eRNAfinal.overlap.txt

# DNase cluster
intersectBed -a eRNAfinal.bed -b ../DNase/DNase.distal.bed -c | sort -k4,4 | cut -f5 | paste eRNAfinal.overlap.txt - > tmp.list
mv tmp.list eRNAfinal.overlap.txt

# TFBS
intersectBed -a eRNAfinal.bed -b ../TFBS/TFBS.distal.bed -c | sort -k4,4 | cut -f5 | paste eRNAfinal.overlap.txt - > tmp.list
mv tmp.list eRNAfinal.overlap.txt

# Conservation
intersectBed -a eRNAfinal.bed -b ../Conservation/Conservation.distal.bed -c | sort -k4,4 | cut -f5 | paste eRNAfinal.overlap.txt - > tmp.list
mv tmp.list eRNAfinal.overlap.txt

## blood enhancer defined by H3k4me1/2/3  --> TO REMOVE
#intersectBed -a eRNAfinal.bed -b ../Histone/blood.enhancers.PMID25103404.tab -c | sort -k4,4 | cut -f5 | paste eRNAfinal.overlap.txt - > tmp.list
#mv tmp.list eRNAfinal.overlap.txt

## overlap %
cat eRNAfinal.overlap.txt | datamash mean 5 mean 6 mean 7 mean 8 mean 9
#0.14033710217755	0.017535594639866	0.069906825795645	0.019603224455611	0.01062604690117

# fisher exact test to see the signifiance


## core enhancers supported by at least 2 evidences
awk '{s=0; for(i=5;i<10;i++) if($i>0) s++;  if(s>2) print}' eRNAfinal.overlap.txt | wc -l
# N=254
awk '{s=0; for(i=5;i<10;i++) if($i>0) s++;  if(s>0) print}' eRNAfinal.overlap.txt > eRNAcore.txt


#############################################################
# measure eRNA, binarily and continously, with other features (e.g. CAGE, DNase, histone etc.)
#############################################################
# CAGE+
~/neurogen/pipeline/RNAseq/bin/toBinRegionsOnBigwig.sh ../CAGE/CAGE.fwd.bigwig eRNAfinal.bed 1 max | sort -k1,1 > eRNAfinal.onOtherFeatures.txt

# CAGE-
~/neurogen/pipeline/RNAseq/bin/toBinRegionsOnBigwig.sh ../CAGE/CAGE.rev.bigwig eRNAfinal.bed 1 max | sort -k1,1 | cut -f2 | paste eRNAfinal.onOtherFeatures.txt - > tmp.list
mv tmp.list eRNAfinal.onOtherFeatures.txt

# H3k4me1, H3K4me3 H3K27ac K3K27me3 H3K36me3 H3K9ac
for i in H3K4me1 H3K4me3 H3K27ac H3K27me3 H3K36me3 H3K9ac; do
    echo $i;
    ~/neurogen/pipeline/RNAseq/bin/toBinRegionsOnBigwig.sh ../Histone/Histone.SN.$i.bigwig eRNAfinal.bed 1 max | sort -k1,1 | cut -f2 | paste eRNAfinal.onOtherFeatures.txt - > tmp.list
    mv tmp.list eRNAfinal.onOtherFeatures.txt
done

# DNase, TFBS, Conservation
for i in DNase TFBS Conservation; do
    echo $i;
    ~/neurogen/pipeline/RNAseq/bin/toBinRegionsOnBigwig.sh ../$i/$i.bigwig eRNAfinal.bed 1 max | sort -k1,1 | cut -f2 | paste eRNAfinal.onOtherFeatures.txt - > tmp.list
    mv tmp.list eRNAfinal.onOtherFeatures.txt
done

# add header
echo -e "locus\tCAGE.fwd\tCAGE.rev\tH3K4me1\tH3K4me3\tH3K27ac\tH3K27me3\tH3K36me3\tH3K9ac\tDNase\tTFBS\tConservation" > tmp.list
cat eRNAfinal.onOtherFeatures.txt >> tmp.list
mv tmp.list eRNAfinal.onOtherFeatures.txt

## clustering
R
df=read.table("eRNAfinal.onOtherFeatures.txt", header=T)
rownames(df)=df[,1]; df=df[,-1]

cage=df[,c('CAGE.fwd','CAGE.rev')]
library(pheatmap) # IF NOT, install.packages('pheatmap')
library("RColorBrewer")

pheatmap(log(1+df),scale='column',
    show_rownames=F,
    cluster_cols=F,
    clustering_distance_rows="correlation",
    color = colorRampPalette(c("navy", "white", "firebrick3"))(50),
    filename="eRNAfinal.onOtherFeatures.png")
)



#############################################################
# target genes of eRNA assigned by correlation of expression
#############################################################

cut -f1,9- ~/neurogen/rnaseq_PD/results/merged/genes.fpkm.allSamples.uniq.xls > genes.fpkm.allSamples.uniq.xls
Rscript ~/neurogen/pipeline/RNAseq/src/eRNA.target.correlation.R eRNAfinal.allsamples.RPKM.tab genes.fpkm.allSamples.uniq.xls eRNAfinal.correlate.gene.in.RPKM
Rscript ~/neurogen/pipeline/RNAseq/src/eRNA.target.correlation.R eRNAfinal.allsamples.readscount.tab ~/neurogen/rnaseq_PD/results/DE_DESeq2/PDvsHC/htseqcount.raw.allsamples.xls eRNAfinal.correlate.gene.in.readscount.tab

# join pcc and rho
join -j 1 <(awk '{print $1"__"$2,$3;}' eRNAfinal.correlate.gene.in.RPKM.pcc.tab|sort) <(awk '{print $1"__"$2,$3;}' eRNAfinal.correlate.gene.in.RPKM.rho.tab|sort) | sort -r | sed 's/__/\t/g;s/ /\t/g' >eRNAfinal.correlate.gene.in.RPKM.cor.tab

# eRNA per gene
cut -f2 eRNAfinal.correlate.gene.in.RPKM.tab | sort | uniq -c | sed 's/^\s*//g;s/ /\t/g' | datamash mean 1
#9.451491660794
# gene per eRNA
cut -f1 eRNAfinal.correlate.gene.in.RPKM.tab | sort | uniq -c | sed 's/^\s*//g;s/ /\t/g' | datamash mean 1
#15.613116026387

# top eRNA with most target genes
cut -f1 eRNAfinal.correlate.gene.in.RPKM.tab | sort | uniq -c | sort -k1,1nr

# xyplot

grep chr eRNAfinal.correlate.gene.in.RPKM.rho.tab | head -n20 | while read x y rest ; do
echo $x, $y;
set -v
    grep -P "$x|locus" eRNAfinal.allsamples.RPKM.tab > /tmp/xyplot.tab
    grep $y genes.fpkm.allSamples.uniq.xls >> /tmp/xyplot.tab
    Rscript ~/neurogen/pipeline/RNAseq/src/eRNA.target.correlation.xyplot.R /tmp/xyplot.tab "$x.$y"
set +v
done

#############################################################
# overlap of GWAS SNPs with eRNA, exons etc. 
#############################################################
awk 'BEGIN{FS="\t";} $9<=1e-8' /data/neurogen/referenceGenome/Homo_sapiens/UCSC/hg19/Annotation/Variation/gwascatalog2014AUGID.selected.txt | cut -f2 | sed 's/ (.*//g' | sort | uniq -c | sort -k2,2 | awk '$1>30'




# RPM with p=0.001 in all samples is: 0.64
# RPM with p=0.001 in HC_SNDA.trimmedmean.uniq.normalized is: 0.17

#3: robust set of eRNA


# length distribution
for i in *.trimmedmean.uniq.normalized.eRNA.bed; do echo $i; wc -l $i; awk '{print $3-$2}' $i | textHistogram -binSize=20 -maxBinCount=50 stdin; done

awk '{OFS="\t"; if(($3-$2)>=200) print $1, $2, $3, $1"_"$2"_"$3, $4}' HC_SNDA.trimmedmean.uniq.normalized.eRNA.bed > eRNA.bed

# Total counts of CAGE reads
toBinRegionsOnBigwig.sh ../CAGE/ctssTotalCounts.fwd.bw eRNA.bed 1 max > eRNA.CAGE.fwd.bed &
toBinRegionsOnBigwig.sh ../CAGE/ctssTotalCounts.rev.bw eRNA.bed 1 max > eRNA.CAGE.rev.bed &

# TF count
toBinRegionsOnBigwig.sh ../TFBS/TFBS.bigwig eRNA.bed 1 max > eRNA.TFBS.bed &

# Histone
toBinRegionsOnBigwig.sh ../Histone/Histone.SN.H3K27ac.bigwig eRNA.bed 1 max > eRNA.SN.H3K27ac.bed &

# DNase
toBinRegionsOnBigwig.sh ../DNase/DNase.bigwig eRNA.bed 1 max > eRNA.DNase.bed &

echo -e "position\tRNAseq\tCAGE.fwd\tCAGE.rev\tDNase\tH3K27ac\tTFBS" > eRNA_merged.txt
paste eRNA.*bed | sed 's/ /\t/g' | cut -f4,5,7,9,11,13,15 >> eRNA_merged.txt

R
df=read.table("eRNA_merged.txt", header=T)
rownames(df)=df[,1]; df=df[,-1]
attach(df)
x=log10(1+cbind(CAGE.fwd, CAGE.rev))
plot(x, pch=1, col='#ff000022', cex=sqrt(RNAseq))

library(flashClust)
d=df[,grep('CAGE',colnames(df))]
d=d[sample(nrow(d),2000),]
dis=dist(d)
hc <- hclust(dis)
plot(hc)

df=df[with(df, order(RNAseq)),]
for(i in 1:ncol(df)){
    image(t(df[,i,drop=F]))
}
