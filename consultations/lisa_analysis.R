# Jane Carlen's analysis of Lisa Rosenthal's spore data
# Jan 2019
#
# TO DO:
# 
# try non-constant (species specific) variance for individual effects
# simulate more data from the model and re-fit. See what is recovered. 
# sensitivity analysis
# plot sampled data from the bayesian fit against true data

# Questions:
# Q1 - Do species have an effect? 
# Q2 - How to handle individual variation (repeated measures)
# Q3 - Model to describe the data?
# Q4 - Bayesian analysis?
# Q5 - Power analysis / how much data we need to rank or group the species?

##############################################################################################################

# 0. Setup ----

library(dplyr)
library(rstan)
Sys.setenv(USE_CXX14 = 1)
rstan_options(auto_write = T)
library(tidyr)
library(forcats)
library(lme4)
library(plotly)
library(reshape2)
library(ggridges)
library(cowplot)

wide = read.csv("MASTERMERGED_wide.csv")

wide.treatment <- filter(wide, trt=="T")

#    Modificiations to data for preliminary analysis ----
# standardize repetitions
# remove species with only one individual
# replace na's with median value
wide.treatment = filter(wide.treatment, species !="CEOL") # CEOL has only one individual -- removing it for preliminary
wide.treatment = droplevels(wide.treatment)
wide.treatment %>% group_by(species) %>% summarize(n_distinct(ind)) # all others have three individuals
# most individuals have six observations but a couple 12 -- making them all 6 for preliminary:
wide.treatment %>% group_by(species, ind) %>% summarize(n())
wide.treatment = wide.treatment %>% group_by(species, ind) %>% 
  arrange(is.na(countS)) %>% #get rid of NAs first if need to get rid of anything
  mutate(index = 1:n(), countS.ind.mean = mean(countS, na.rm = T)) %>% filter(index <=6) #cuts 18
wide.treatment = wide.treatment %>% arrange(species, ind) %>% 
  mutate(ind2 = ind+3*as.numeric(species)) %>% ungroup()
         
# replace NAs with median if necessary:
# wide.treatment = wide.treatment %>% group_by(species, ind) %>% mutate(counts = replace_na(countS, median(countS, na.rm = T)))

# 1. EDA ----

# boxplots for individuals group by species also showing data points
ind.boxplot = ggplot(wide.treatment, aes(y = countS, x = species, group = interaction(species,ind))) +
         geom_boxplot() + theme_bw() +
         geom_point(aes(y = countS, group = interaction(species,ind), color = as.factor(ind), shape = as.factor(ind)))
ggplotly(ind.boxplot) #enables zoom in for species near zero

# point distributions for individuals, colored by species
ind.plot = ggplot(wide.treatment, aes(y = countS, x = interaction(ind, species))) + geom_point(aes(color = species)) + theme_bw() +
  theme(axis.text.x = element_text(angle = 90))

# point distributions for individual means, colored by species
ind.means.plot = ggplot(wide.treatment) + geom_point(aes(y= countS.ind.mean, x = species, color = species)) + 
                  theme(axis.text.x = element_text(angle = 90))

# 2. Anova/GLM 
#    One-way ANOVA (bad) (Q1) ----

# We individual means instead of individual observations to deal with non-independence of repeated measures of individuals.
# Other assumptions of ANOVA (normality of residuals, homoskedasticity, aren't met)
# We shouldn't use these results. 

lm1 = lm(countS.ind.mean ~ -1 + species, data = wide.treatment) # removed intercept for easily interpretable estiamtes
summary(lm1)
aov1 = aov(lm1); aov1
plot(aov1)

#    Anova with one random effect and one fixed effect (Q2) ----

  # Helpful references:
    # http://www.maths.bath.ac.uk/~jjf23/mixchange/rbd.html
    # https://cran.r-project.org/web/packages/lme4/vignettes/lmer.pdf
    # Extending the linear model with R (faraway) chapter 8 and 9.2

  # Our scenario
  # We have repeated measures of each individual
  # Species is fixed and individual is a random effect (not a level/type chosen by the researcher)
  # (Standard 2-way anova would assume two fixed effects)

  # lisa.mmod <- glmer(countS ~ species + (1|ind), wide.treatment, family = "poisson") bad, groups individuals into just 1,2,3 groups
  # random effect of individual nested in species
  # Assumes constant variance for random effects

  # Normal (bad) ----
  # Our data is not normal. There are outliers and our response var is non-neg.
  # So we won't use these results either, but here's what the implementation would look like.

  lisa.mmod <- lmer(countS ~ -1 + species + (1|species:ind), wide.treatment) 
  #lisa.mmod <- lmer(countS ~ -1 + species + (1|ind2), wide.treatment) 
  summary(lisa.mmod)
  anova(lisa.mmod) # can check the species effect with an anova
  lisa.mmod.ci = data.frame(confint(lisa.mmod)[-c(1,2),]); names(lisa.mmod.ci) = c("lower_2.5","upper_97.5")
  lisa.mmod.ci$effect = as.factor(rownames(lisa.mmod.ci))
  ggplot(lisa.mmod.ci) + geom_segment(aes(x = lower_2.5, xend = upper_97.5, y = effect, yend = effect)) + 
                         geom_point(data = data.frame(summary(lisa.mmod)$coefficients),
                                    aes(x = Estimate, y = 1:12)) + theme_bw()
  
  # Poisson (also bad)  ----
  
  # This captures the non-negativite of our data (counts), but way underestimates the variance (see "Poisson lack of fit" below)
  lisa.gmmod <- glmer(countS ~ species + (1|species:ind), wide.treatment, family = "poisson") 
  summary(lisa.gmmod)
  #confint(lisa.gmmod) fails?

  # Neg.binom (better, but still has problems) ----
  
  # This model captures non-negativity of our data (counts) AND the greater dispersion,
  # but still assumes constant variance for random effects
  lisa.gmmod.nb <- glmer.nb(countS ~ -1 + species + (1|species:ind), wide.treatment) 
  summary(lisa.gmmod.nb)
  lisa.gmmod.nb.ci = confint(lisa.gmmod.nb)
  lisa.gmmod.nb.ci =  data.frame(lisa.gmmod.nb.ci); names(lisa.gmmod.nb.ci) = c("lower_2.5","upper_97.5")
  lisa.gmmod.nb.ci$effect = c("sig01", rownames(lisa.mmod.ci))
  lisa.gmmod.nb.species = ggplot(lisa.gmmod.nb.ci[-1,]) + geom_segment(aes(x = lower_2.5, xend = upper_97.5, y = effect, yend = effect)) + 
    geom_point(data = data.frame(summary(lisa.gmmod.nb)$coefficients), aes(x = Estimate, y = 1:12)) + theme_bw()

  # We look below with the bayesian results (which are similar for the simplified model) at how well the negative binomial fits our data
  
# 3. Poisson lack of fit (Q3) ----
  
  # Observed distributions are way more dispersed than a poisson.
  # We'll show that by looking at the "major" outliers
  # using the following cutoff for probability of a point under the corresponding poisson
  cutoff1 = 1.0e-10
  
     # Poisson distribution of individual observations given individual means? ----
  wide.treatment %>% group_by(species, ind) %>% 
    mutate(
      ind.mean = round(mean(countS)),
      dpois = dpois(countS, lambda = ind.mean),
      major_outlier = dpois < cutoff1) %>% 
    select(ind.mean, countS, dpois, major_outlier) %>%
    ggplot(aes(x = fct_reorder(interaction(species, ind), as.numeric(species)), y = countS, 
               color = species, size = major_outlier)) + 
    geom_point(alpha = .5) + theme(axis.text.x = element_text(angle = 90))
  
  
     # Poisson distribution of individual means given species means? ----
  wide.treatment %>% group_by(species) %>%
    mutate(species.mean = mean(countS)) %>%
    group_by(species, ind) %>%
    summarize(ind.mean = round(mean(countS)),
              species.mean = round(first(species.mean)),
              dpois = dpois(round(ind.mean), lambda = species.mean),
              major_outlier = dpois < cutoff1
    ) %>% 
    select(species.mean, ind.mean, dpois, major_outlier) %>%
    ggplot(aes(x = species, y = ind.mean, color = species, size = major_outlier)) + 
    geom_point(alpha = .5) +  theme(axis.text.x = element_text(angle = 90))  

# 4. Should we use negative binomial (uses bayesian output below)? (Q4) ----
  
  # This converts from stan's neg_binomial_2 implementation of negative binomial with mean and variance to
  # R's neg binom implementation with size and probability parameters
  convert_to_nbinom <- function(lambda, phi) {
    prob = phi/(1+lambda)
    size = lambda*phi/(1+lambda - phi)
    return(list(size = size, prob = prob))
  }
  
  # Look for major outliers from negative binomial bayesian fit ----
  lambda = lisa_summary[grepl("lambda", rownames(lisa_summary)), 1]
  phi = lisa_summary[grepl("phi", rownames(lisa_summary)), 1]
  sp = convert_to_nbinom(as.vector(lambda), phi)
  with(sp, {assign("mean.lisa", size*(1-prob)/prob, pos = 1)})  # should equal lambda
  with(sp, {assign("var.lisa", size*(1-prob)/prob^2, pos = 1)}) # some very large variances
  
  # How many major outliers given cutoff1 set above?
  lisa.nb.prob = dnbinom(wide.treatment$countS, size = sp$size, p = sp$prob) # Better, fewer huge variances and means are closer in
  sum(lisa.nb.prob < cutoff1) # 
  # much more reasonable range of probabilities than poisson:
  hist(lisa.nb.prob, breaks = 100) 
  # but variances can be very large:
  hist(var.lisa, breaks = 1000)
  
# 5. Bayesian (Q4) ####
#    model with individual effects drawn from species level means ----

# data
lisa_data = list(
  S = n_distinct(wide.treatment$species),
  I = 3,
  J = 6,
  Y = wide.treatment$countS # data arranged by species then individual 
)

# fit
lisa_model = "~/Documents/DSI/consultations/lisa_model.stan"
stanc(lisa_model)
lisa_fit = stan(file = lisa_model, model_name = "lisa", data = lisa_data, 
                 control = list(max_treedepth = 15), verbose = TRUE, iter = 1000,
                chains = 2)

# results
print(lisa_fit)
plot(lisa_fit, pars = c("alpha_s", "alpha0")) # means
plot(lisa_fit, pars = "beta") # individual
plot(lisa_fit, pars = c("sigma_s", "sigma0", "phi")) # dispersion
lisa_summary = summary(lisa_fit, pars = c("alpha_s", "phi", "sigma_s", "beta","lambda"), probs = c(0.1, 0.9))$summary
lisa_extracted = rstan::extract(lisa_fit)

#    visualize marginal posteriors ----

# species mean
alpha_s_data = lisa_extracted$alpha_s
colnames(alpha_s_data) = as.character(unique(wide.treatment$species))
alpha_s_traceplot = ggplot(melt(alpha_s_data)) + geom_line(aes(x = iterations, y = value, group = Var2)) + facet_wrap(~Var2)
alpha_s = ggplot(melt(alpha_s_data)) + geom_density_ridges(aes(x = value, y = Var2))

# We can see that the estiamtes from the negative binomial model and the simple Bayesian model are basically the same,
# though the posterior sample in the basesian fit gives us more information:
plot_grid(lisa.gmmod.nb.species, alpha_s)

# individual mean
beta_data = melt(lisa_extracted$beta)
colnames(beta_data) = c("iterations", "species", "ind", "value")
beta_s = ggplot(beta_data) + geom_density_ridges(aes(x = value, y = interaction(ind,species), fill = as.factor(species))) +
  guides(fill = "none")

# species variance (for betas) --> can make this species-specific later
sigma_s_data = lisa_extracted$sigma_s
sigma_s = ggplot(melt(sigma_s_data)) + geom_density(aes(x = value), fill = "gray") +
  ggtitle("Posterior distribution of sigma_s, variance for individuals effects") +
  xlab("sigma_s") + theme(plot.title = element_text(size = 10))

# phi (overdispersion) -- close to 1, but note that variance already has a squared relationship to mean under this neg binom
phi_data = data.frame(lisa_extracted$phi)
phi = ggplot(phi_data) + geom_density(aes(x = lisa_extracted.phi), fill = "gray") +
  ggtitle("Posterior distribution of phi, overdispersion parameter") +
  xlab("phi") + theme(plot.title = element_text(size = 10))

marginal_post_plots = list(alpha_s = alpha_s, beta_s = beta_s, sigma_s = sigma_s, phi = phi) #store in list so new doesn't overwrite

plot_grid(ind.plot, beta_s, sigma_s, phi, nrow = 2, rel_heights = c(7,3))

#    (preliminary - ignore) model with individual effects ----

# data
lisa_data_individual = list(
  S = n_distinct(wide.treatment$species),
  I = 3,
  J = 6,
  Y = wide.treatment$countS # data arranged by species then individual 
)

# fit
lisa_model_individual = "~/Documents/DSI/consultations/lisa_individual.stan"
stanc(lisa_model_individual)
# lisa_fit_individual_poisson -- stored result before switching to neg binom
lisa_fit_individual = stan(file = lisa_model_individual, model_name = "lisa_individual", 
                           data = lisa_data_individual, 
                           control = list(max_treedepth = 15), verbose = TRUE, iter = 1000, chains = 2)

# results
print(lisa_fit_individual)
#plot(lisa_fit_individual_poisson, pars = "alpha") # species
plot(lisa_fit_individual, pars = "alpha") # species
#plot(lisa_fit_individual_poisson, pars = "beta") # species
plot(lisa_fit_individual, pars = "beta") # individual
plot(lisa_fit_individual, pars = "phi") # individual
lisa_summary_individual = summary(lisa_fit_individual, pars = c("phi", "alpha","beta","lambda"), probs = c(0.1, 0.9))$summary

lisa_extracted_individual = rstan::extract(lisa_fit_individual)


#    (preliminary - ignore) model with only species effects ----

# data
lisa_data_species = list(
  S = n_distinct(wide.treatment$species),
  I = 3,
  Y = round((wide.treatment %>% group_by(species, ind) %>% summarize(mean = mean(countS)))$mean)# data arranged by species then individual 
)

lisa_model_species = "~/Documents/DSI/consultations/lisa_species.stan"
stanc(lisa_model_species)
lisa_fit_species= stan(file = lisa_model_species, model_name = "lisa_species", data = lisa_data_species, 
                           control = list(max_treedepth = 15), verbose = TRUE, iter = 1000, chains = 2)

# results
print(lisa_fit_species)
plot(lisa_fit_species, pars = c("alpha","alpha0")) # species
lisa_summary_species = summary(lisa_fit_species, pars = c("phi", "alpha", "lambda"), probs = c(0.1, 0.9))$summary
lisa_extracted_species = rstan::extract(lisa_fit_species)

#    (preliminary - ignore) investigate poisson lack of fit using stan output ----
lisa_summary_individual_poisson = summary(lisa_fit_individual_poisson, pars = c("lambda"))$summary
lambda = lisa_summary_individual_poisson[grepl("lambda", rownames(lisa_summary_individual_poisson)), 1]
dpois(wide.treatment$countS, lambda) #not so good
sum(.Last.value < cutoff1)

lisa_summary_species_poisson = summary(lisa_fit_individual_poisson, pars = c("lambda"))$summary
lambda = lisa_summary_individual_poisson[grepl("lambda", rownames(lisa_summary_individual_poisson)), 1]
dpois(wide.treatment$countS, lambda) #not so good
sum(.Last.value < cutoff1)


#------------------------------------------------ Future Additions ------------------------------------------------------------------------
# 6. Extend Bayesian to allow species-specific variance for indiviual effects ----

# data
lisa_data_sigmas = list(
  S = n_distinct(wide.treatment$species),
  I = 3,
  J = 6,
  Y = wide.treatment$countS # data arranged by species then individual 
)

# fit
lisa_model_sigmas = "~/Documents/DSI/consultations/lisa_model_sigmas.stan"
stanc(lisa_model_sigmas)
lisa_fit_sigmas = stan(file = lisa_model_sigmas, model_name = "lisa_sigmas", data = lisa_data_sigmas, seed = 1,
                control = list(max_treedepth = 15), verbose = TRUE, iter = 1000, chains = 2, save_warmup = TRUE)

# results
print(lisa_fit_sigmas)
plot(lisa_fit_sigmas, pars = c("alpha_s", "alpha0")) # means
plot(lisa_fit_sigmas, pars = "beta") # individual
plot(lisa_fit_sigmas, pars = c("sigma_s", "sigma0", "phi")) # dispersion
lisa_summary_sigmas = summary(lisa_fit_sigmas, pars = c("alpha_s", "phi", "sigma_s", "beta","lambda"), probs = c(0.1, 0.9))$summary
lisa_extracted = rstan::extract(lisa_fit_sigmas) #overwrites simple model

#    visualize marginal posteriors ----
# species mean
alpha_s_data = lisa_extracted$alpha_s
colnames(alpha_s_data) = as.character(unique(wide.treatment$species))
alpha_s_traceplot = ggplot(melt(alpha_s_data)) + geom_line(aes(x = iterations, y = value, group = Var2)) + facet_wrap(~Var2)
alpha_s = ggplot(melt(alpha_s_data)) + geom_density_ridges(aes(x = value, y = Var2)) +
  ggtitle("Posterior distribution of alpha_s, species effects") +
# Now compare these estimates to the estimates from the negative binomial model and the simple Bayesian model:
plot_grid(lisa.gmmod.nb.species, marginal_post_plots$alpha_s, alpha_s, nrow = 1)

# individual mean
beta_data = melt(lisa_extracted$beta)
colnames(beta_data) = c("iterations", "species", "ind", "value")
beta_s = ggplot(beta_data) + geom_density_ridges(aes(x = value, y = interaction(ind,species), fill = as.factor(species))) +
  guides(fill = "none")

# species variance (for betas) --> now species-specific
sigma_s_data = lisa_extracted$sigma_s
colnames(sigma_s_data) = unique(wide.treatment$species)
sigma_s = ggplot(melt(sigma_s_data)) + geom_density_ridges(aes(x = value, y = Var2, fill = Var2), bandwidth = .05) + 
  ggtitle("Posterior distribution of sigma_s, species-specific variance for individuals effects") +
  guides(fill = guide_legend(reverse = T)) +
  xlim(c(0,10)) +
  xlab("sigma_s") + theme(plot.title = element_text(size = 10))

# phi (overdispersion) -- close to 1, but note that variance already has a squared relationship to mean under this neg binom
phi_data = data.frame(lisa_extracted$phi)
phi = ggplot(phi_data) + geom_density(aes(x = lisa_extracted.phi), fill = "gray") +
  ggtitle("Posterior distribution of phi, overdispersion parameter") +
  xlab("phi") + theme(plot.title = element_text(size = 10))

marginal_post_plots_sigmas = list(alpha_s = alpha_s, ind.effects = ind.effects, sigma_s = sigma_s, phi = phi) #store in list so new doesn't overwrite

#Compare the results from the two models (simpler model top row) ----
plot_grid(marginal_post_plots$alpha_s, marginal_post_plots$beta_s, marginal_post_plots$sigma_s,
          alpha_s, beta_s, sigma_s, nrow = 2, rel_heights = c(5,5))

# not sure why this pattern in posterior sigmas. not enough data to overwhelm the prior except in one case?
# sensitive to the prior on sigma_s

# look at mcmc ---
lisa_inits = get_inits(lisa_fit_sigmas)
lisa_sample_params = get_sampler_params(lisa_fit_sigmas, inc_warmup = FALSE)
colMeans(lisa_sample_params[[1]]) # one for each chain
colMeans(lisa_sample_params[[2]])

lisa_posterior = as.array(lisa_fit_sigmas)
mcmc_scatter(lisa_posterior, pars =  c("alpha_s[1]","sigma_s[1]"))

# 7. Power using simulated data ----

# How would the Bayesian results look with different levels of data and spread?
# How much data to be need to recover true parameters?

# 8. Sensitivity ----

# Try changing priors
# Plot prior joint density of parameters ala (http://www.rss.org.uk/Images/PDF/events/2018/Gabry-5-Sept-2018.pdf/https://www.youtube.com/watch?v=E8vdXoJId8M)
