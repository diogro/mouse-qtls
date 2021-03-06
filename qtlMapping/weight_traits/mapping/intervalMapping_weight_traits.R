makeMarkerList = function(pos) paste(paste('trait:chrom', pos[1],"_", c('A', 'D'), pos[2], sep = ''), collapse = ' + ')
markerMatrix = ldply(1:19, function(x) data.frame(chrom = x, marker = 1:loci_per_chrom[[x]]))
markerList = alply(markerMatrix, 1, makeMarkerList)
markerPositions = cbind(markerMatrix, read_csv("./data/markers/marker_positions.csv")[,3])
names(markerPositions)[3] = "cM"

runIntervalMCMCModel <- function(marker_term, null_formula, start = NULL, ...){
    pos = na.omit(as.numeric(unlist(strsplit(unlist(as.character(marker_term)), "[^0-9]+"))))[3:2]
    focal_cm = filter(markerPositions, chrom == pos[1], marker == pos[2])$cM
    possible_flank = filter(markerPositions, chrom == pos[1], abs(cM - focal_cm) > flank_dist)
    flanking = NULL
    for(line in 1:nrow(possible_flank)){
        if(possible_flank[line,"cM"] > focal_cm){ flanking = rbind(flanking, possible_flank[line,1:2]); break }
    }
    if(line > 1 & line != nrow(possible_flank)) flanking = rbind(possible_flank[line-1, 1:2], flanking)
    if(line == nrow(possible_flank)) flanking = rbind(possible_flank[line, 1:2], flanking)

    flanking_formula = paste(null_formula, paste(alply(flanking, 1, makeMarkerList), collapse = " + "), sep = " + ")

    prior = list(R = list(V = diag(num_weight_traits), n = 0.002),
                 G = list(G1 = list(V = diag(num_weight_traits) * 0.02, n = num_weight_traits+1)))
    weight_MCMC_flanking = MCMCglmm(as.formula(flanking_formula),
                                random = ~us(trait):FAMILY,
                                data = as.data.frame(weight_data),
                                rcov = ~us(trait):units,
                                family = rep("gaussian", num_weight_traits),
                                start = start,
                                prior = prior,
                                verbose = FALSE,
                                ...)

    genotype.formula = paste(flanking_formula, marker_term, sep = ' + ')

    prior = list(R = list(V = diag(num_weight_traits), n = 0.002),
                 G = list(G1 = list(V = diag(num_weight_traits) * 0.02, n = num_weight_traits+1)))
    weight_MCMC_focal = MCMCglmm(as.formula(genotype.formula),
                                random = ~us(trait):FAMILY,
                                data = as.data.frame(weight_data),
                                rcov = ~us(trait):units,
                                family = rep("gaussian", num_weight_traits),
                                start = start,
                                prior = prior,
                                verbose = FALSE,
                                ...)
    return(list(flanking = weight_MCMC_flanking,
                focal    = weight_MCMC_focal))
}

start <- list(R = list(V = R_mcmc), G = list(G1 = G_mcmc), liab = matrix(weight_MCMC_null_model$Liab[1,], ncol = num_weight_traits))

intervalMapping_MCMC = llply(markerList, runIntervalMCMCModel, null_formula, start, nitt=20300, thin=10, burnin=300, .parallel = TRUE)
model_file = paste0(Rdatas_folder, "weight_intervalMapping_", flank_dist, "cM_mcmc.Rdata")
save(intervalMapping_MCMC, file = model_file)
load(model_file)
all_effectsInterval_mcmc = ldply(intervalMapping_MCMC,
      function(model_pair){
           focal = model_pair$focal
           sf = summary(focal)
           neff = nrow(sf$solutions)
           effects = sf$solutions[(neff-15):neff,]
           ad = effects[1:num_weight_traits,]
           colnames(ad) = paste("ad", colnames(ad), sep = "_")
           dm = effects[(num_weight_traits+1):(num_weight_traits+num_weight_traits),]
           colnames(dm) = paste("dm", colnames(dm), sep = "_")
           Sol = focal$Sol[,(neff-15):neff]
           p_ad = colSums((Sol[, 1:num_weight_traits]) > 0)/nrow(Sol)
           p_dm = colSums((Sol[,(num_weight_traits+1):(num_weight_traits+num_weight_traits)]) > 0)/nrow(Sol)
           pos = na.omit(as.numeric(unlist(strsplit(unlist(as.character(focal$Fixed$formula)[3]), "[^0-9]+"))))
           pos = pos[(length(pos)-1):length(pos)]
           data.frame(chrom = pos[1], marker = pos[2], trait = 1:num_weight_traits, ad, dm, p_ad, p_dm)
      }, .id = NULL, .parallel = TRUE) %>% tbl_df %>% mutate(count = rep(seq(intervalMapping_MCMC), each = num_weight_traits)) %>% select(count, everything())
effect_file = paste0("./data/weight traits/weight_effectsInterval_", flank_dist, "cM_mcmc.csv")
write_csv(all_effectsInterval_mcmc, effect_file)
dmSend(paste("Finished weight interval mapping with flanking", flank_dist, "cM"), "diogro")
