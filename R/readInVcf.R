#' Calculate population statistics along contigs
#'
#' @description Carries out common sequence diversity and distance calculations on individuals or populations.
#'
#' @details As reading in the variant data is currently the runtime bottleneck it is advised to run all statistics
#' simultaniously to reduce overall runtime. \cr
#' \code{dxy}: Nei's absolute distance between two populations X and Y. \cr
#' \code{pi}: Nei's within populaition nucleotide diversity. \cr
#' \code{da}: Nei's net genetic distance between two populations X and Y
#'
#'
#' @param fileName A \code{character} vector of length one containing the full path name for a Tabix indexed VCF
#' @param contigs \code{character}. Default is \code{"all"} Contigs to extract windows from.
#' @param winSize \code{numeric}. Default is \code{100000}. Window size in base pairs.
#' @param minSites \code{numeric}. Default is 10 percent of winSize. The minimum number of sites within a window to consider it.
#' @param ploidy \code{numeric}. The ploidy of the VCF, as called by Variant Caller.
#' @param stat \code{character}. Default is to perform all statistics. The statistics to carry out on the windows
#' options are \code{dxy}, \code{pi}, \code{da}, and \code{Dt}.
#' @param pops \code{data.frame}. If not suplied statistics will be calculated on an individual basis.
#' \code{data.frame} should contain two columns \code{sampleNames} specifying sample names as they appear in
#' the VCF sample field and \code{pop} defines the populations of the samples. See example.
#' @param nCores \code{numeric}. Number of cores to run analysis on.
#'
#'
#' @return A \code{tibble} containing populations statistics passed from \code{stat}
#'
#'
#' @importFrom pbapply pblapply
#' @importFrom tibble data_frame
#' @importFrom magrittr %>%
#' @importFrom dplyr bind_rows
#' @importFrom dplyr bind_cols
#' @importFrom pegas tajima.test
#'
#'
#' @examples
#'
#'
#' @export
#' @rdname popStatWindows
#
library(readr)
library(ape)
library(magrittr)
library(dplyr)
library(tidyr)
library(scales)
library(parallel)
library(ggplot2)
library(plotly)
library(geiger)
library(phytools)
library(VariantAnnotation)
library(stringr)
library(msa)
library(d3heatmap)
library(poppr)
library(pegas)
library(phangorn)
library(pbapply)
library(ggtree)
#
#
# winSize <- 100000
# nCores <- 6
# fileName <- "~/Desktop/Tree-TipR/Plutella_SNPsOnly.vcf.gz"
# minSites <- 100
# ploidy <- 2
# stat <- c("dxy")

# sequenceNames <- rownames(dna)
# sampleNames <- gsub("/.*", "", sequenceNames) %>% unique()
# pops <- data.frame(sampleNames = sampleNames, pop = c("PxC", "PxC", "PaC", rep("PxH", 7), "PaG",
#                                                       "PxH", "PaR", "PxS", "PaS","PxS", "PaS","PxS",
#                                                       "PaS", "PaS", "PxS", "PxG", "PaG", "PaG",
#                                                       "PxG", "PaG", "PaC", "PaC", "PaC"))

# VCFheader <- scanVcfHeader(fileName)
#
# contigMD <- as.data.frame(VCFheader@header$contig)
# contigs <- rownames(contigMD)
# #
#
# #alastairu
# pl <- c("KLS0337",
#         "KLS0333","KLS0219","KLS0348","WAM174520",
#         "DARK_TENIUS","KLS0119","MT182","R36639",
#         "MT174","X01049","KLS0114","A00998","X01014",
#         "X01044","X01010","MW04719","KLS0118")
#
# ## Sample/Population dataframe
# pops <- data.frame(sampleNames = pl, pop = c(rep("Afuscus",2), rep("Alaevis",2), rep("Atenius",2), rep("Hcurtus",3),
#                                              "Hcogg", rep("Hcyano",3), rep("Hmelano",2), "Hparvi", rep("Hviper",2)))

# contigs <- c("scaffold1|size703937","scaffold2|size540562","scaffold3|size527680",
#              "scaffold4|size481093","scaffold5|size399909","scaffold6|size324431",
#              "scaffold7|size322635","scaffold8|size308202","scaffold9|size294065",
#              "scaffold10|size290244","scaffold11|size286520","scaffold12|size270235")
# #
#
# prog <- c()
# start.time <- Sys.time()

popStatWindows <- function(fileName, contigs = "all", winSize = 100000,
                           minSites, ploidy = 2, stat = c("dxy", "pi", "da"),
                           pops, nCores = 1){

  #read in VCF header
  VCFheader <- scanVcfHeader(fileName)

  #get contig Metadata
  contigMD <- as.data.frame(VCFheader@header$contig)

  if(all(contigs == "all")) contigs <- rownames(contigMD)

  # set minSites to 1
  if(missing(minSites)) minSites <- 0.05 * winSize


  data <- pblapply(contigs, function(con){
    length <- as.integer(filter(contigMD, rownames(contigMD) == con)$length)
    if(length >= winSize){
      nWindows <- floor(length / winSize)

      pbmclapply(seq(1, nWindows), mc.cores = nCores, function(winN){

        pos <- winN * winSize + 1
        start <- pos - winSize
        end <- pos

        p <- ScanVcfParam(which = GRanges(seqnames = con, ranges = IRanges(start = start, end = end)))

        nSites <- tryCatch(length(scanVcf(TabixFile(fileName), param = p)[[1]]$rowRanges),  error=function(e) 0)

        if(nSites >= minSites){
          #read in vcf
          dna <- vcfWindow(fileName = fileName, contig = con, param = p, ploidy = ploidy)
          #get raw distances using ape::dist.dna as a matrix to calculate dxy, pi and da from
          dist <- dist.dna(dna, as.matrix = TRUE, model = "raw", pairwise.deletion = TRUE)

          #using formula from http://mycor.nancy.inra.fr/egglib/releases/3.0.0a/stats.pdf

          #make pop list
          popList <-  split(pops, pops$pop)

          #calculate dxy for populations from Nei 1987

          if("dxy" %in% stat){
            dxy <- neisDxy(dist, popList)
          } else {
            dxy <- c()
          }

          #calculate nucleotide diversity from Nei 1987
          if("pi" %in% stat){
            pi <- neisPi(dist, popList)
          } else {
            pi <- c()
          }

          #calculate da from from Nei 1987
          #can only calculate da if dxy and pi are known
          if(all(c("pi", "dxy", "da") %in% stat)){

           neisDa(dxy, pi)

          } else {
            da <- c()
          }

          #bind all columns together
          div <- bind_cols(scaffold = con, start = start, end = end, midpoint = (start + end) /2, nSites = nSites, dxy, pi, da)

        }
        else {
          div <- data_frame(scaffold = con, start = start, end = end, midpoint = (start + end) /2, nSites = nSites)
        }
      }) %>% bind_rows() #bind all windows on contig together
    }
    else{
      data_frame(scaffold = con)
    }
  }) %>% bind_rows() #bind all contigs together
data
}

#
# end.time <- Sys.time()
# time.taken <- end.time - start.time
# time.taken
