makeMarkerList = function(pos) paste(paste('trait:chrom', pos[1],"_", c('A', 'D'), pos[2], sep = ''), collapse = ' + ')
markerMatrix = ldply(1:19, function(x) data.frame(chrom = x, locus = 1:loci_per_chrom[[x]]))
markerList = alply(markerMatrix, 1, makeMarkerList)

runSingleLocusMCMCModel <- function(marker_term, null_formula, start = NULL, ...){
    genotype.formula = paste(null_formula, marker_term, sep = ' + ')
    prior = list(R = list(V = diag(num_area_traits), n = 0.002),
                 G = list(G1 = list(V = diag(num_area_traits) * 0.02, n = num_area_traits+1)))
    area_MCMC_singleLocus = MCMCglmm(as.formula(genotype.formula),
                                random = ~us(trait):FAMILY,
                                data = as.data.frame(area_data),
                                rcov = ~us(trait):units,
                                family = rep("gaussian", num_area_traits),
                                start = start,
                                prior = prior,
                                verbose = FALSE,
                                ...)
    return(area_MCMC_singleLocus)
}

start <- list(R = list(V = R_mcmc), G = list(G1 = G_mcmc), liab = matrix(area_MCMC_null_model$Liab[1,], ncol = num_area_traits))

all_loci_MCMC = llply(markerList, runSingleLocusMCMCModel, null_formula, start, nitt=20300, thin=10, burnin=300, .parallel = TRUE)
save(all_loci_MCMC, file = paste0(Rdatas_folder, "area_singleLocusMapping.Rdata"))
load(paste0(Rdatas_folder, "area_singleLocusMapping.Rdata"))
x = all_loci_MCMC[[1]]
all_effects_mcmc = ldply(all_loci_MCMC,
      function(x){
           ad = summary(x)$solutions[(num_area_traits+1):(num_area_traits+num_area_traits), ]
           colnames(ad) = paste("ad", colnames(ad), sep = "_")
           dm = summary(x)$solutions[(2*num_area_traits+1):(2*num_area_traits+num_area_traits), ]
           colnames(dm) = paste("dm", colnames(dm), sep = "_")
           p_ad = colSums((x$Sol[,(num_area_traits+1):(num_area_traits+num_area_traits)]) > 0)/nrow(x$Sol)
           p_dm = colSums((x$Sol[,(2*num_area_traits+1):(2*num_area_traits+num_area_traits)]) > 0)/nrow(x$Sol)
           pos = na.omit(as.numeric(unlist(strsplit(unlist(as.character(x$Fixed$formula)[3]), "[^0-9]+"))))[2:3]
           data.frame(chrom = pos[1], marker = pos[2], trait = 1:num_area_traits, ad, dm, p_ad, p_dm)
      }, .id = NULL, .parallel = TRUE) %>% tbl_df %>%
      dplyr::mutate(count = rep(seq(markerList), each = num_area_traits)) %>%
      dplyr::select(count, everything()) %>% dplyr::select(-locus)
write_csv(all_effects_mcmc, "./data/area traits/effectsSingleLocus.csv")
all_effects_mcmc = read_csv("./data/area traits/effectsSingleLocus.csv")
dmSend("Finished area single locus mapping", "diogro")

singleLocus_DIC_df <- 
  ldply(all_loci_MCMC, `[[`, "DIC") %>% 
  mutate(singleLocus_DICDiff = area_MCMC_null_model$DIC - V1) %>% 
  rename(singleLocus_DIC = V1) %>% tbl_df
write_csv(singleLocus_DIC_df, "./data/area traits/singleLocusDIC.csv")
