poisson.CARlinear <- function(formula, data=NULL, W.quants, burnin, n.sample, thin=1,  prior.mean.beta=NULL, prior.var.beta=NULL, prior.mean.alpha=NULL, prior.var.alpha=NULL, prior.tau2=NULL, rho.slo=NULL, rho.int=NULL, MALA=FALSE, verbose=TRUE, Wstar.eigen = NULL)
{
#### Verbose
a <- common.verbose(verbose)  
    
    
#### Frame object
frame.results <- common.frame(formula, data, "poisson")
N.all <- frame.results$n
p <- frame.results$p
X <- frame.results$X
X.standardised <- frame.results$X.standardised
X.sd <- frame.results$X.sd
X.mean <- frame.results$X.mean
X.indicator <- frame.results$X.indicator 
offset <- frame.results$offset
Y <- frame.results$Y
which.miss <- frame.results$which.miss
n.miss <- frame.results$n.miss  
Y.DA <- Y  

rm( frame.results)
print( paste( "Frame object section at", round(proc.time()[3]-a[3], 1)))

#### Check on MALA argument
    if(length(MALA)!=1) stop("MALA is not length 1.", call.=FALSE)
    if(!is.logical(MALA)) stop("MALA is not logical.", call.=FALSE) 

print( paste( "Check MALA section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Check on the rho arguments
    if(is.null(rho.int))
    {
    rho <- runif(1)
    fix.rho.int <- FALSE   
    }else
    {
    rho <- rho.int
    fix.rho.int <- TRUE
    }
    if(!is.numeric(rho)) stop("rho.int is fixed but is not numeric.", call.=FALSE)  
    if(rho<0 ) stop("rho.int is outside the range [0, 1].", call.=FALSE)  
    if(rho>1 ) stop("rho.int is outside the range [0, 1].", call.=FALSE)    

    if(is.null(rho.slo))
    {
    lambda <- runif(1)
    fix.rho.slo <- FALSE   
    }else
    {
    lambda <- rho.slo
    fix.rho.slo <- TRUE
    }
    if(!is.numeric(lambda)) stop("rho.slo is fixed but is not numeric.", call.=FALSE)  
    if(lambda<0 ) stop("rho.slo is outside the range [0, 1].", call.=FALSE)  
    if(lambda>1 ) stop("rho.slo is outside the range [0, 1].", call.=FALSE)  

print( paste( "Check rho section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### CAR quantities
#W.quants <- common.Wcheckformat.leroux(W)
W <- W.quants$W
K <- W.quants$n
N <- N.all / K
W.triplet <- W.quants$W.triplet
W.n.triplet <- W.quants$n.triplet
W.triplet.sum <- W.quants$W.triplet.sum
n.neighbours <- W.quants$n.neighbours 
W.begfin <- W.quants$W.begfin

print( paste( "CAR quantities section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Priors
    if(is.null(prior.mean.beta)) prior.mean.beta <- rep(0, p)
    if(is.null(prior.var.beta)) prior.var.beta <- rep(100000, p)
    if(is.null(prior.tau2)) prior.tau2 <- c(1, 0.01)
    if(is.null(prior.mean.alpha)) prior.mean.alpha <- rep(0, 1)
    if(is.null(prior.var.alpha)) prior.var.alpha <- rep(100000, 1)
prior.beta.check(prior.mean.beta, prior.var.beta, p)
prior.var.check(prior.tau2)
    if(length(prior.mean.alpha)!=1) stop("the prior mean for alpha is the wrong length.", call.=FALSE)    
    if(!is.numeric(prior.mean.alpha)) stop("the  prior mean for alpha is not numeric.", call.=FALSE)    
    if(sum(is.na(prior.mean.alpha))!=0) stop("the prior mean for alpha has missing values.", call.=FALSE)       
    if(length(prior.var.alpha)!=1) stop("the prior variance for alpha is the wrong length.", call.=FALSE)    
    if(!is.numeric(prior.var.alpha)) stop("the  prior variance for alpha is not numeric.", call.=FALSE)    
    if(sum(is.na(prior.var.alpha))!=0) stop("the  prior variance for alpha has missing values.", call.=FALSE)    
    if(min(prior.var.alpha) <=0) stop("the prior variance for alpha has elements less than zero", call.=FALSE)

print( paste( "Priors section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Compute the blocking structure for beta     
block.temp <- common.betablock(p)
beta.beg  <- block.temp[[1]]
beta.fin <- block.temp[[2]]
n.beta.block <- block.temp[[3]]
list.block <- as.list(rep(NA, n.beta.block*2))
    for(r in 1:n.beta.block)
    {
    list.block[[r]] <- beta.beg[r]:beta.fin[r]-1
    list.block[[r+n.beta.block]] <- length(list.block[[r]])
    }

print( paste( "Compute blocking structure for beta section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### MCMC quantities - burnin, n.sample, thin
common.burnin.nsample.thin.check(burnin, n.sample, thin)

print( paste( "MCMC quantities section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))


#############################
#### Initial parameter values
#############################
time <-(1:N - mean(1:N))/N
time.all <- kronecker(time, rep(1,K))
mod.glm <- glm(Y~X.standardised-1 + time.all, offset=offset, family="quasipoisson")#, model = F, x = F, y = F)
beta.mean <- mod.glm$coefficients
beta.sd <- sqrt(diag(summary(mod.glm)$cov.scaled))
temp <- rnorm(n=length(beta.mean), mean=beta.mean, sd=beta.sd)
beta <- temp[1:p]
alpha <- temp[(p+1)]

print( summary( mod.glm))

log.Y <- log(Y)
log.Y[Y==0] <- -0.1  
res.temp <- log.Y - as.numeric(X.standardised %*% beta) - time.all * alpha - offset
res.sd <- sd(res.temp, na.rm=TRUE)/5
phi <- rnorm(n=K, mean=0, sd = res.sd)
delta <- rnorm(n=K, mean=0, sd = res.sd)
tau2.phi <- var(phi)/10
tau2.delta <- var(delta)/10

print( paste( "Initial parameter values section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Specify matrix quantities
offset.mat <- matrix(offset, nrow=K, ncol=N, byrow=FALSE) 
regression.mat <- matrix(X.standardised %*% beta, nrow=K, ncol=N, byrow=FALSE)   
time.mat <- matrix(rep(time, K), byrow=TRUE, nrow=K)    
delta.time.mat <- apply(time.mat, 2, "*", delta)
phi.mat <- matrix(rep(phi, N), byrow=F, nrow=K)   
lp <- as.numeric(offset.mat + regression.mat + phi.mat + delta.time.mat + alpha * time.mat)
fitted <- exp(lp)

print( paste( "Specify matrix quantities section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

###############################    
#### Set up the MCMC quantities    
###############################
#### Matrices to store samples
n.keep <- floor((n.sample - burnin)/thin)
samples.beta <- array(NA, c(n.keep, p))
samples.alpha <- array(NA, c(n.keep, 1))
samples.phi <- array(NA, c(n.keep, K))
samples.delta <- array(NA, c(n.keep, K))
    if(!fix.rho.int) samples.rho <- array(NA, c(n.keep, 1))
    if(!fix.rho.slo) samples.lambda <- array(NA, c(n.keep, 1))
samples.tau2 <- array(NA, c(n.keep, 2))
colnames(samples.tau2) <- c("tau2.int", "tau2.slo")
samples.fitted <- array(NA, c(n.keep, N.all))
samples.loglike <- array(NA, c(n.keep, N.all))
    if(n.miss>0) samples.Y <- array(NA, c(n.keep, n.miss))

print( paste( "Set up MCMC quantities section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Specify the Metropolis quantities
accept.all <- rep(0,12)
accept <- accept.all
proposal.sd.beta <- 0.01
proposal.sd.phi <- 0.1
proposal.sd.delta <- 0.1
proposal.sd.alpha <- 0.1
proposal.sd.rho <- 0.02
proposal.sd.lambda <- 0.02
proposal.corr.beta <- solve(t(X.standardised) %*% X.standardised)
chol.proposal.corr.beta <- chol(proposal.corr.beta)   
tau2.phi.shape <- prior.tau2[1] + K/2
tau2.delta.shape <- prior.tau2[1] + K/2
    
print( paste( "Specify Metropolis quantities section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))


##############################
#### Specify spatial quantites
##############################
#### Create the determinant     
    if(!fix.rho.int | !fix.rho.slo) 
    {
        if( is.null( Wstar.eigen)){
            Wstar <- diag(apply(W,1,sum)) - W
            Wstar.eigen <- eigen(Wstar)
        }
    Wstar.val <- Wstar.eigen$values
    }else
    {}
    if(!fix.rho.int) det.Q.rho <-  0.5 * sum(log((rho * Wstar.val + (1-rho))))    
    if(!fix.rho.slo) det.Q.lambda <-  0.5 * sum(log((lambda * Wstar.val + (1-lambda))))     

print( paste( "Create the determinant section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))

#### Check for islands
W.list<- mat2listw(W)
W.nb <- W.list$neighbours
W.islands <- n.comp.nb(W.nb)
islands <- W.islands$comp.id
n.islands <- max(W.islands$nc)
    if(rho==1) tau2.phi.shape <- prior.tau2[1] + 0.5 * (K-n.islands)   
    if(lambda==1) tau2.delta.shape <- prior.tau2[1] + 0.5 * (K-n.islands)     

print( paste( "Check for islands section at", round(proc.time()[3]-a[3], 1),
              "and mem_used() is", pryr::mem_used()))


###########################
#### Run the Bayesian model
###########################
## Start timer
    if(verbose)
    {
    cat("Generating", n.keep, "post burnin and thinned (if requested) samples.\n", sep = " ")
    progressBar <- txtProgressBar(style = 3)
    percentage.points<-round((1:100/100)*n.sample)
    }else
    {
    percentage.points<-round((1:100/100)*n.sample)     
    }

    
#### Create the MCMC samples    
    for(j in 1:n.sample)
    {
    ####################################
    ## Sample from Y - data augmentation
    ####################################
        if(n.miss>0)
        {
        Y.DA[which.miss==0] <- rpois(n=n.miss, lambda=fitted[which.miss==0])    
        }else
        {}
    Y.DA.mat <- matrix(Y.DA, nrow=K, ncol=N, byrow=FALSE)
    
        
        
    ####################
    ## Sample from beta
    ####################
    offset.temp <- offset + as.numeric(phi.mat) + as.numeric(delta.time.mat) + as.numeric(alpha * time.mat)      
        if(MALA)
        {
        temp <- poissonbetaupdateMALA(X.standardised, N.all, p, beta, offset.temp, Y.DA, prior.mean.beta, prior.var.beta, n.beta.block, proposal.sd.beta, list.block)
        }else
        {
        temp <- poissonbetaupdateRW(X.standardised, N.all, p, beta, offset.temp, Y.DA, prior.mean.beta, prior.var.beta, n.beta.block, proposal.sd.beta, list.block)
        }
    beta <- temp[[1]]
    accept[1] <- accept[1] + temp[[2]]
    accept[2] <- accept[2] + n.beta.block  
    regression.mat <- matrix(X.standardised %*% beta, nrow=K, ncol=N, byrow=FALSE)  
        
    # print( paste( 'beta is', beta))
    # print( temp)
    # print( cat( 'offset.temp is', offset.temp[1:5]))
    
    ####################
    ## Sample from alpha
    ####################
    proposal.alpha <- rnorm(n=1, mean=alpha, sd=proposal.sd.alpha)
    prob1 <- 0.5 * (alpha - prior.mean.alpha)^2 / prior.var.alpha - 0.5 * (proposal.alpha - prior.mean.alpha)^2 / prior.var.alpha
    lp.current <- offset + as.numeric(regression.mat) + as.numeric(phi.mat) + as.numeric(delta.time.mat) + as.numeric(alpha * time.mat)     
    lp.proposal <- offset + as.numeric(regression.mat) + as.numeric(phi.mat) + as.numeric(delta.time.mat) + as.numeric(proposal.alpha * time.mat)            
    like.current <- Y.DA * lp.current - exp(lp.current)
    like.proposal <- Y.DA * lp.proposal - exp(lp.proposal)
    prob2 <- sum(like.proposal - like.current, na.rm=TRUE)
    prob <- exp(prob1 + prob2)
        if(prob > runif(1))
        {
        alpha <- proposal.alpha
        accept[3] <- accept[3] + 1           
        }else
        {
        }              
    accept[4] <- accept[4] + 1           

        
        
    ####################
    ## Sample from phi
    ####################
    phi.offset <- offset.mat + regression.mat + delta.time.mat + alpha * time.mat
        if(MALA)
        {
        temp1 <- poissoncarupdateMALA(W.triplet, W.begfin, W.triplet.sum, K, phi, tau2.phi, Y.DA.mat, proposal.sd.phi, rho, phi.offset, N, rep(1,N))
        }else
        {
        temp1 <- poissoncarupdateRW(W.triplet, W.begfin, W.triplet.sum, K, phi, tau2.phi, Y.DA.mat, proposal.sd.phi, rho, phi.offset, N, rep(1,N))
        }
    phi <- temp1[[1]]
        if(rho<1)
        {
        phi <- phi - mean(phi)
        }else
        {
        phi[which(islands==1)] <- phi[which(islands==1)] - mean(phi[which(islands==1)])   
        }
    phi.mat <- matrix(rep(phi, N), byrow=F, nrow=K)    
    accept[5] <- accept[5] + temp1[[2]]
    accept[6] <- accept[6] + K  
        
        
        
    ####################
    ## Sample from delta
    ####################
    delta.offset <- offset.mat + regression.mat + phi.mat +  alpha * time.mat
        if(MALA)
        {
        temp2 <- poissoncarupdateMALA(W.triplet, W.begfin, W.triplet.sum, K, delta, tau2.delta,Y.DA.mat, proposal.sd.delta, lambda, delta.offset, N, time)
        }else
        {
        temp2 <- poissoncarupdateRW(W.triplet, W.begfin, W.triplet.sum, K, delta, tau2.delta,Y.DA.mat, proposal.sd.delta, lambda, delta.offset, N, time)
        }
    delta <- temp2[[1]]
        if(lambda <1)
        {
        delta <- delta - mean(delta)
        }else
        {
        delta[which(islands==1)] <- delta[which(islands==1)] - mean(delta[which(islands==1)])   
        }
    delta.time.mat <- apply(time.mat, 2, "*", delta)
    accept[7] <- accept[7] + temp2[[2]]
    accept[8] <- accept[8] + K      
        
        
        
    ######################
    ## Sample from tau2.phi
    #######################
    temp2.phi <- quadform(W.triplet, W.triplet.sum, W.n.triplet, K, phi, phi, rho)
    tau2.phi.scale <- temp2.phi + prior.tau2[2] 
    tau2.phi <- 1 / rgamma(1, tau2.phi.shape, scale=(1/tau2.phi.scale))
        
    
        
    #########################
    ## Sample from tau2.delta
    #########################
    temp2.delta <- quadform(W.triplet, W.triplet.sum, W.n.triplet, K, delta, delta, lambda)
    tau2.delta.scale <- temp2.delta + prior.tau2[2] 
    tau2.delta <- 1 / rgamma(1, tau2.delta.shape, scale=(1/tau2.delta.scale))
    
        
        
    ##################
    ## Sample from rho
    ##################
        if(!fix.rho.int)
        {
        proposal.rho <- rtruncnorm(n=1, a=0, b=1, mean=rho, sd=proposal.sd.rho)   
        temp3 <- quadform(W.triplet, W.triplet.sum, W.n.triplet, K, phi, phi, proposal.rho)
        det.Q.proposal <- 0.5 * sum(log((proposal.rho * Wstar.val + (1-proposal.rho))))              
        logprob.current <- det.Q.rho - temp2.phi / tau2.phi
        logprob.proposal <- det.Q.proposal - temp3 / tau2.phi
        hastings <- log(dtruncnorm(x=rho, a=0, b=1, mean=proposal.rho, sd=proposal.sd.rho)) - log(dtruncnorm(x=proposal.rho, a=0, b=1, mean=rho, sd=proposal.sd.rho)) 
        prob <- exp(logprob.proposal - logprob.current + hastings)
        
        #### Accept or reject the proposal
            if(prob > runif(1))
            {
            rho <- proposal.rho
            det.Q.rho <- det.Q.proposal
            accept[9] <- accept[9] + 1           
            }else
            {}              
        accept[10] <- accept[10] + 1           
        }else
        {}
        
        
    
    #####################
    ## Sample from lambda
    #####################
        if(!fix.rho.slo)
        {
        proposal.lambda <- rtruncnorm(n=1, a=0, b=1, mean=lambda, sd=proposal.sd.lambda)   
        temp3 <- quadform(W.triplet, W.triplet.sum, W.n.triplet, K, delta, delta, proposal.lambda)
        det.Q.proposal <- 0.5 * sum(log((proposal.lambda * Wstar.val + (1-proposal.lambda))))              
        logprob.current <- det.Q.lambda - temp2.delta / tau2.delta
        logprob.proposal <- det.Q.proposal - temp3 / tau2.delta
        hastings <- log(dtruncnorm(x=lambda, a=0, b=1, mean=proposal.lambda, sd=proposal.sd.lambda)) - log(dtruncnorm(x=proposal.lambda, a=0, b=1, mean=lambda, sd=proposal.sd.lambda)) 
        prob <- exp(logprob.proposal - logprob.current + hastings)
        
        #### Accept or reject the proposal
        if(prob > runif(1))
        {
        lambda <- proposal.lambda
        det.Q.lambda <- det.Q.proposal
        accept[11] <- accept[11] + 1           
        }else
        {}              
        accept[12] <- accept[12] + 1           
        }else
        {}
        
        # print( paste( 'accept:', accept))
    
    #########################
    ## Calculate the deviance
    #########################
    lp <- as.numeric(offset.mat + regression.mat + phi.mat + delta.time.mat + alpha * time.mat)
    fitted <- exp(lp)
    loglike <- dpois(x=as.numeric(Y), lambda=fitted, log=TRUE)

    
    ###################
    ## Save the results
    ###################
        if(j > burnin & (j-burnin)%%thin==0)
        {
        ele <- (j - burnin) / thin
        samples.beta[ele, ] <- beta
        samples.phi[ele, ] <- phi
        samples.delta[ele, ] <- delta
        samples.alpha[ele, ] <- alpha
            if(!fix.rho.int) samples.rho[ele, ] <- rho
            if(!fix.rho.slo) samples.lambda[ele, ] <- lambda
        samples.tau2[ele, ] <- c(tau2.phi, tau2.delta)
        samples.fitted[ele, ] <- fitted
        samples.loglike[ele, ] <- loglike
            if(n.miss>0) samples.Y[ele, ] <- Y.DA[which.miss==0]
        }else
        {}
        
        
        
    ########################################
    ## Self tune the acceptance probabilties
    ########################################
    k <- j/100
        if(ceiling(k)==floor(k))
        {
        #### Update the proposal sds
            if(p>2)
            {
            proposal.sd.beta <- common.accceptrates1(accept[1:2], proposal.sd.beta, 40, 50)
            }else
            {
            proposal.sd.beta <- common.accceptrates1(accept[1:2], proposal.sd.beta, 30, 40)    
            }
        proposal.sd.alpha <- common.accceptrates1(accept[3:4], proposal.sd.alpha, 30, 40) 
        proposal.sd.phi <- common.accceptrates1(accept[5:6], proposal.sd.phi, 40, 50)
        proposal.sd.delta <- common.accceptrates1(accept[7:8], proposal.sd.delta, 40, 50)
            if(!fix.rho.int) proposal.sd.rho <- common.accceptrates2(accept[9:10], proposal.sd.rho, 40, 50, 0.5)
            if(!fix.rho.slo) proposal.sd.lambda <- common.accceptrates2(accept[11:12], proposal.sd.lambda, 40, 50, 0.5)
        accept.all <- accept.all + accept
        accept <- rep(0,12)
        }else
        {}
        
        
    
    ################################       
    ## print progress to the console
    ################################
        if(j %in% percentage.points & verbose)
        {
        setTxtProgressBar(progressBar, j/n.sample)
        }
    }
    

#### end timer
    if(verbose)
    {
    cat("\nSummarising results.")
    close(progressBar)
    }else
    {}

#### clean house
print( paste( 'mem_used() before trimming is', pryr::mem_used()))
biggest_objects <- sort( sapply(ls(),function(x){pryr::object_size(get(x))})) 
print( tail( biggest_objects))
rm( W, mod.glm, W.quants)
biggest_objects <- sort( sapply(ls(),function(x){pryr::object_size(get(x))})) 
print( paste( 'mem_used() after trimming is', pryr::mem_used()))
print( tail( biggest_objects))


###################################
#### Summarise and save the results 
###################################
## Compute the acceptance rates
accept.beta <- 100 * accept.all[1] / accept.all[2]
accept.alpha <- 100 * accept.all[3] / accept.all[4]
accept.phi <- 100 * accept.all[5] / accept.all[6]
accept.delta <- 100 * accept.all[7] / accept.all[8]
    if(!fix.rho.int)
    {
    accept.rho <- 100 * accept.all[9] / accept.all[10]
    }else
    {
    accept.rho <- NA    
    }
    if(!fix.rho.slo)
    {
    accept.lambda <- 100 * accept.all[11] / accept.all[12]
    }else
    {
    accept.lambda <- NA    
    }
accept.final <- c(accept.beta, accept.alpha, accept.phi, accept.delta, accept.rho, accept.lambda)
names(accept.final) <- c("beta", "alpha", "phi", "delta", "rho.int", "rho.slo")
   
print( paste( 'mem_used() after computing acceptance rates is', pryr::mem_used()))

#### Compute the fitted deviance
mean.phi <- apply(samples.phi, 2, mean)
mean.delta <- apply(samples.delta, 2, mean)
mean.alpha <- mean(samples.alpha)
mean.phi.mat <- matrix(rep(mean.phi, N), byrow=F, nrow=K)
delta.time.mat <- apply(time.mat, 2, "*", mean.delta)
mean.beta <- apply(samples.beta,2,mean)
regression.mat <- matrix(X.standardised %*% mean.beta, nrow=K, ncol=N, byrow=FALSE)   
lp.mean <- offset.mat + regression.mat + mean.phi.mat + delta.time.mat + mean.alpha * time.mat
fitted.mean <- exp(lp.mean)
deviance.fitted <- -2 * sum(dpois(x=as.numeric(Y), lambda=fitted.mean, log=TRUE), na.rm=TRUE)

print( paste( 'mem_used() after computing the fitted deviance is', pryr::mem_used()))
biggest_objects <- sort( sapply(ls(),function(x){pryr::object_size(get(x))})) 
print( tail( biggest_objects))

#### Model fit criteria
modelfit <- common.modelfit(samples.loglike, deviance.fitted)

print( paste( 'mem_used() after model fit criteria is', pryr::mem_used()))

#### Create the fitted values and residuals
fitted.values <- apply(samples.fitted, 2, mean)
response.residuals <- as.numeric(Y) - fitted.values
pearson.residuals <- response.residuals /sqrt(fitted.values)
residuals <- data.frame(response=response.residuals, pearson=pearson.residuals)
    
print( paste( 'mem_used() after creating fitted values and residuals is', pryr::mem_used()))

#### Transform the parameters back to the origianl covariate scale.
samples.beta.orig <- common.betatransform(samples.beta, X.indicator, X.mean, X.sd, p, FALSE)  

print( paste( 'mem_used() after transforming parameters back to original scale is', pryr::mem_used()))

#### Create a summary object
samples.beta.orig <- mcmc(samples.beta.orig)
summary.beta <- t(apply(samples.beta.orig, 2, quantile, c(0.5, 0.025, 0.975))) 
summary.beta <- cbind(summary.beta, rep(n.keep, p), rep(accept.beta,p), effectiveSize(samples.beta.orig), geweke.diag(samples.beta.orig)$z)
rownames(summary.beta) <- colnames(X)
colnames(summary.beta) <- c("Median", "2.5%", "97.5%", "n.sample", "% accept", "n.effective", "Geweke.diag")
    
summary.hyper <- array(NA, c(5, 7))     
summary.hyper[1,1:3] <- quantile(samples.alpha, c(0.5, 0.025, 0.975))
summary.hyper[2,1:3] <- quantile(samples.tau2[ ,1], c(0.5, 0.025, 0.975))
summary.hyper[3,1:3] <- quantile(samples.tau2[ ,2], c(0.5, 0.025, 0.975))
rownames(summary.hyper) <- c("alpha", "tau2.int", "tau2.slo",  "rho.int", "rho.slo")     
summary.hyper[1, 4:7] <- c(n.keep, accept.alpha, effectiveSize(mcmc(samples.alpha)), geweke.diag(mcmc(samples.alpha))$z)     
summary.hyper[2, 4:7] <- c(n.keep, 100, effectiveSize(mcmc(samples.tau2[ ,1])), geweke.diag(mcmc(samples.tau2[ ,1]))$z)   
summary.hyper[3, 4:7] <- c(n.keep, 100, effectiveSize(mcmc(samples.tau2[ ,2])), geweke.diag(mcmc(samples.tau2[ ,2]))$z)   

    if(!fix.rho.int)
    {
    summary.hyper[4, 1:3] <- quantile(samples.rho, c(0.5, 0.025, 0.975))
    summary.hyper[4, 4:7] <- c(n.keep, accept.rho, effectiveSize(samples.rho), geweke.diag(samples.rho)$z)
    }else
    {
    summary.hyper[4, 1:3] <- c(rho, rho, rho)
    summary.hyper[4, 4:7] <- rep(NA, 4)
    }
    if(!fix.rho.slo)
    {
    summary.hyper[5, 1:3] <- quantile(samples.lambda, c(0.5, 0.025, 0.975))
    summary.hyper[5, 4:7] <- c(n.keep, accept.lambda, effectiveSize(samples.lambda), geweke.diag(samples.lambda)$z)
    }else
    {
    summary.hyper[5, 1:3] <- c(lambda, lambda, lambda)
    summary.hyper[5, 4:7] <- rep(NA, 4)
    }   
    
summary.results <- rbind(summary.beta, summary.hyper)
summary.results[ , 1:3] <- round(summary.results[ , 1:3], 4)
summary.results[ , 4:7] <- round(summary.results[ , 4:7], 1)
    
print( paste( 'mem_used() after creating summary object is', pryr::mem_used()))

## Compile and return the results
#### Harmonise samples in case of them not being generated
    if(fix.rho.int & fix.rho.slo)
    {
    samples.rhoext <- NA
    }else if(fix.rho.int & !fix.rho.slo)
    {
    samples.rhoext <- samples.lambda
    names(samples.rhoext) <- "rho.slo"
    }else if(!fix.rho.int & fix.rho.slo)
    {
    samples.rhoext <- samples.rho  
    names(samples.rhoext) <- "rho.int"
    }else
    {
    samples.rhoext <- cbind(samples.rho, samples.lambda)
    colnames(samples.rhoext) <- c("rho.int", "rho.slo")
    }
    if(n.miss==0) samples.Y = NA

samples <- list(beta=mcmc(samples.beta.orig), alpha=mcmc(samples.alpha), phi=mcmc(samples.phi),  delta=mcmc(samples.delta), tau2=mcmc(samples.tau2), rho=mcmc(samples.rhoext), fitted=mcmc(samples.fitted), Y=mcmc(samples.Y))        
model.string <- c("Likelihood model - Poisson (log link function)", "\nLatent structure model - Spatially autocorrelated linear time trends\n")
results <- list(summary.results=summary.results, samples=samples, fitted.values=fitted.values, residuals=residuals,  modelfit=modelfit, accept=accept.final, localised.structure=NULL, formula=formula, model=model.string,  X=X)
class(results) <- "CARBayesST"

print( paste( 'mem_used() after compiling results is', pryr::mem_used()))

#### Finish by stating the time taken 
    if(verbose)
    {
    b<-proc.time()
    cat("Finished in ", round(b[3]-a[3], 1), "seconds.\n")
    }else
    {}
return(results)
}




