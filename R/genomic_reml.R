####################################################################################################################
#    Module 4: GREML analysis
####################################################################################################################
#'
#' Genomic REML analysis
#'
#' @description
#' Genomic restricted maximum likelihood estimation (REML) is an analysis used to estimate genomic and residual variance.
#' Genomic variance is the variance associated with the genomic relationship matrix.
#'
#' @details
#' Linear mixed model (LMM) that models covariance among individuals using realized relationships at genotyped loci.
#' This modeling scheme is achieved through the genomic relationship matrix (G).
#' This matrix can be inputted 'as is' or with a more efficient list structure, Glist, that contains information about G.
#' The model can accomodate fixed effects.
#' Individuals may be subsetted for additional analyses such as cross validation.
#' 
#' @param y vector of phenotypes
#' @param X design matrix of fixed effects
#' @param Glist list of information about G matrix
#' @param G genomic relationship matrix
#' @param ids vector of subsetted individuals to retain for analysis, e.g. cross validation
#' @param theta initial values for reml estimation
#' @param maxit maximum number of iterations of reml analysis
#' @param tol tolerance, i.e. the maximum allowed difference between two consecutive iterations of reml to declare convergence
#' @param bin executable file in fortran
#' @param nthreads number of threads
#' @param wkdir working directory
#' @return Returns a list structure, fit, including
#' \item{llik}{log-likelihood at convergence}
#' \item{theta}{initial values for reml estimation}
#' \item{asd}{asymptotic standard deviation}
#' \item{b}{vector of fixed effect estimates}
#' \item{varb}{vector of variances of fixed effect estimates}
#' \item{u}{vector of random effect estimates}
#' \item{e}{vector of residual effects}
#' \item{Vy}{product of variance-covariance matrix of y at convergence and y}
#' \item{Py}{product of projection matrix of y and y}
#' \item{trPG}{trace of product of projection matrix of y and G}
#' \item{trVG}{trace of product of variance-covariance matrix of y at convergence and G}
#' \item{y}{vector of phenotypes}
#' \item{X}{design matrix of fixed effects}
#' \item{ids}{vector of subsetted individuals retained for analysis}
#' \item{yVy}{product of y, variance-covariance matrix of y at convergence, and y}
#' \item{fnamesG}{filename(s) and locations of of G}
#' \item{wd}{working directory}
#' \item{Glist}{list of information about G matrix}
#' @author Peter Sørensen
#' @references Lee, S. H., & van Der Werf, J. H. (2006). An efficient variance component approach implementing an average information REML suitable for combined LD and linkage mapping with a general complex pedigree. Genetics Selection Evolution, 38(1), 25.
#' @examples
#'
#' # Simulate data
#' W <- matrix(rnorm(20000000), ncol = 10000)
#' 	colnames(W) <- as.character(1:ncol(W))
#' 	rownames(W) <- as.character(1:nrow(W))
#' y <- rowSums(W[, 1:10]) + rowSums(W[, 1001:1010]) + rnorm(nrow(W))
#'
#' # Create model
#' data <- data.frame(y = y, mu = 1)
#' fm <- y ~ 0 + mu
#' X <- model.matrix(fm, data = data)
#'
#' # Create framework for lists
#' setsGB <- list(A = colnames(W)) # gblup model
#' setsGF <- list(C1 = colnames(W)[1:1000], C2 = colnames(W)[1001:2000], C3 = colnames(W)[2000:10000]) # gfblup model
#' setsGT <- list(C1 = colnames(W)[1:10], C2 = colnames(W)[1001:1010], C3 = colnames(W)[1:10000]) # true model
#'
#' # Compute G
#' G <- computeG(W = W)
#' GB <- lapply(setsGB, function(x) {computeG(W = W[, x])})
#' GF <- lapply(setsGF, function(x) {computeG(W = W[, x])})
#' GT <- lapply(setsGT, function(x) {computeG(W = W[, x])})
#'
#' # REML analyses
#' fitGB <- greml(y = y, X = X, G = GB, verbose = TRUE)
#' fitGF <- greml(y = y, X = X, G = GF, verbose = TRUE)
#' fitGT <- greml(y = y, X = X, G = GT, verbose = TRUE)
#'
#' # REML analyses and cross validation
#' n <- length(y)
#' fold <- 10
#' nsets <- 5
#' 
#' validate <- replicate(nsets, sample(1:n, as.integer(n / fold)))
#' 
#' cvGB <- greml(y = y, X = X, G = GB, validate = validate)
#' cvGF <- greml(y = y, X = X, G = GF, validate = validate)
#' cvGT <- greml(y = y, X = X, G = GT, validate = validate)
#'
#' cvGB
#' cvGF
#' cvGT
#' 
#' boxplot(cbind(cvGB[,1:4],cvGF[,1:4],cvGT[,1:4]))
#' 
#' @export
#'

greml <- function(y = NULL, X = NULL, Glist=NULL, G=NULL, theta=NULL, ids=NULL, validate=NULL, maxit=100, tol=0.00001,bin=NULL,nthreads=1,wkdir=getwd(), verbose=FALSE)
{
  if(is.null(bin)) { 
    if (is.null(validate)) fit <- remlR(y=y, X=X, Glist=Glist, G=G, theta=theta, ids=ids, maxit=maxit, tol=tol, bin=bin, nthreads=nthreads, verbose=verbose, wkdir=wkdir)
    if (!is.null(validate)) fit <- cvreml(y=y, X=X, Glist=Glist, G=G, theta=theta, ids=ids, validate=validate, maxit=maxit, tol=tol, bin=bin, nthreads=nthreads, verbose=verbose, wkdir=wkdir)
  }
  if(!is.null(bin)) { 
    fit <- remlF(y=y, X=X, Glist=Glist, G=G, ids=ids, theta=theta, maxit=maxit, tol=tol, bin=bin, nthreads=nthreads, verbose=verbose, wkdir=wkdir)
  }
  return(fit)  
}  


####################################################################################################################

# REML interface functions for fortran

remlF <- function(y = NULL, X = NULL, Glist = NULL, G = NULL, theta = NULL, ids = NULL, maxit = 100, tol = 0.00001, bin = NULL, nthreads = 1, wkdir = getwd(), verbose = FALSE ) {
#greml <- function(y = NULL, X = NULL, Glist = NULL, G = NULL, ids = NULL, theta = NULL, maxit = 100, tol = 0.00001, bin = NULL, nthreads = 1, wkdir = getwd()) {
    
	write.reml(y = as.numeric(y), X = X, G = G)
	n <- length(y)
	nf <- ncol(X)
	if (!is.null(G)) fnamesG <- paste("G", 1:length(G), sep = "")
	if (!is.null(Glist$fnG)) fnamesG <- Glist$fnG
	nr <- length(fnamesG) + 1
 	if (is.null(ids)) {indxG <- c(n, 1:n)} 
	if (!is.null(ids)) {indxG <- c(Glist$n, match(ids, Glist$idsG))} 
	write.table(indxG, file = "indxg.txt", quote = FALSE, sep = " ", col.names = FALSE, row.names = FALSE)

	write.table(paste(n, nf, nr, maxit, nthreads), file = "param.txt", quote = FALSE, sep = " ", col.names = FALSE, row.names = FALSE)
	if (is.null(theta)) theta <- rep(sd(y) / nr, nr)
	#if (is.null(theta)) theta <- rep(var(y) / nr, nr)
	write.table(t(theta), file = "param.txt", quote = FALSE, sep = " ", append = TRUE, col.names = FALSE, row.names = FALSE)
	write.table(tol, file = "param.txt", quote = FALSE, sep = " ", append = TRUE, col.names = FALSE, row.names = FALSE)
	write.table(fnamesG, file = "param.txt", quote = TRUE, sep = " ", append = TRUE, col.names = FALSE, row.names = FALSE)

	execute.reml(bin = bin,  nthreads = nthreads)
	fit <- read.reml(wkdir = wkdir)
	fit$y <- y
	fit$X <- X
	fit$ids <- names(y)
	fit$yVy <- sum(y * fit$Vy)
	fit$fnamesG <- fnamesG
	fit$wd <- getwd()
	fit$Glist <- Glist

	clean.reml(wkdir = wkdir)
      
	return(fit)
      
}


write.reml <- function(y = NULL, X = NULL, G = NULL) {
    
	fileout <- file("y", "wb")
	writeBin(y, fileout)
	close(fileout)
      
	filename <- "X"
	fileout <- file(filename, "wb")
	for (i in 1:nrow(X)) {writeBin(X[i, ], fileout)}
	close(fileout)
  
	if (!is.null(G)) {
		for (i in 1:length(G)) {
			fileout <- file(paste("G", i, sep = ""), "wb")
			#writeBin(G[[i]][upper.tri(G[[i]], diag = TRUE)], fileout)
			nr <- nrow(G[[i]])
			for (j in 1:nr) {
				writeBin(G[[i]][j, j:nr], fileout)
			}
			close(fileout)
		}
	}
          
}

execute.reml  <- function (bin = NULL, nthreads = nthreads) {

	HW <- Sys.info()["machine"]
	OS <- .Platform$OS.type
	if (OS == "windows") {
		"my.system" <- function(cmd) {return(system(paste(Sys.getenv("COMSPEC"), "/c", cmd)))}
        
		#my.system(paste("set MKL_NUM_THREADS = ", nthreads))
		test <- my.system(paste(shQuote(bin), " < param.txt > reml.lst", sep = ""))
	}
	if (!OS == "windows") {
		system(paste("cp ", bin, " reml.exe", sep = ""))
		#system(paste("export MKL_NUM_THREADS=", nthreads))
		system("time ./reml.exe < param.txt > reml.lst")
	}
      
} 
   
read.reml <- function (wkdir = NULL) {
    
	llik <- read.table(file = "llik.qgg", header = FALSE, colClasses = "numeric")
	names(llik) <- "logLikelihood" 
	theta <- read.table(file = "theta.qgg", header = FALSE, colClasses = "numeric")
	colnames(theta) <- "Estimate"
	rownames(theta) <- 1:nrow(theta)
	asd <- read.table(file = "thetaASD.qgg", header = FALSE, colClasses = "numeric") 
	colnames(asd) <- rownames(asd) <- 1:ncol(asd)
	b <- read.table(file = "beta.qgg", header = FALSE, colClasses = "numeric")    
	colnames(b) <- "Estimate"
	rownames(b) <- 1:nrow(b)
	varb <- read.table(file = "betaASD.qgg", header = FALSE, colClasses = "numeric")    
	colnames(varb) <- rownames(varb) <- 1:nrow(b)
	u <- read.table(file = "uhat.qgg", header = FALSE, colClasses = "numeric")
	colnames(u) <- 1:(nrow(theta) - 1)
	e <- read.table(file = "residuals.qgg", header = FALSE, colClasses = "numeric")    
	colnames(e) <- "residuals"
	rownames(e) <- rownames(u) <- 1:nrow(u)
	Vy <- read.table(file = "Vy.qgg", header = FALSE, colClasses = "numeric")    
	rownames(Vy) <- 1:nrow(u)
	Py <- read.table(file = "Py.qgg", header = FALSE, colClasses = "numeric")    
	rownames(Py) <- 1:nrow(u)
	trPG <- as.vector(unlist(read.table(file = "trPG.qgg", header = FALSE, colClasses = "numeric")[, 1]))    
	names(trPG) <- 1:nrow(theta)
	trVG <- as.vector(unlist(read.table(file = "trVG.qgg", header = FALSE, colClasses = "numeric")[, 1]))    
	names(trVG) <- 1:nrow(theta)
	fit <- list(llik = llik, theta = theta, asd = asd, b = b, varb = varb, g = u, e = e, Vy = Vy, Py = Py, trPG = trPG, trVG = trVG)
	fit <- lapply(fit, as.matrix)
      
	return(fit)
      
}

clean.reml <- function(wkdir = NULL) {
    
	fnames <- c("llik.qgg", "theta.qgg", "thetaASD.qgg", "beta.qgg", "betaASD.qgg", 
				"uhat.qgg", "residuals.qgg", "Vy.qgg", "Py.qgg", "trPG.qgg", "trVG.qgg") 
	file.remove(fnames)
      
}

####################################################################################################################

# REML R functions 

remlR <- function(y=NULL, X=NULL, Glist=NULL, G=NULL, theta=NULL, ids=NULL, maxit=100, tol=0.00001, bin=NULL,nthreads=1,wkdir=getwd(), verbose=FALSE )
  
  #reml <- function( y=NULL, X=NULL, Glist=NULL, G=NULL,theta=NULL, ids=NULL, maxit=100, verbose=FALSE)
{
  
  np <- length(G) + 1
  if (is.null(theta)) theta <- rep(sd(y)/np**2,np)
  n <- length(y)
  ai <- matrix(0, ncol=np, nrow=np)
  s <- matrix(0, ncol=1, nrow=np)
  tol <- 0.00001
  delta <- 100
  it <- 0
  G[[np]] <- diag(1,length(y))
  
  while ( max(delta)>tol ) {
    V <- matrix(0,n,n)
    u <- Pu <- matrix(0,nrow=n,ncol=np)
    it <- it + 1
    for ( i in 1:np) { V <- V + G[[i]]*theta[i] }
    Vi <- chol2inv(chol(V))
    remove(V)
    XViXi <- chol2inv(chol(crossprod(X,crossprod(Vi,X) ) ) )
    ViX <- crossprod(Vi,X) 
    ViXXViXi <- tcrossprod(ViX,XViXi)
    remove(XViXi)
    P <- Vi - tcrossprod(ViXXViXi,ViX)
    remove(Vi)
    Py <- crossprod(P,y)
    for ( i in 1:np) {
      u[,i] <- crossprod(G[[i]],Py)
      Pu[,i] <- crossprod(P,u[,i])
    }
    for ( i in 1:np) {
      for ( j in i:np) {
        ai[i,j] <- 0.5*sum(u[,i]*Pu[,j])
        ai[j,i] <- ai[i,j]
      }
      if (i<np) s[i,1] <- -0.5*(sum(G[[i]]*P)-sum(u[,i]*Py))
      if (i==np) s[i,1] <- -0.5*(sum(diag(P))-sum(Py*Py))
    }
    theta.cov <- solve(ai)
    theta0 <- theta + solve(ai)%*%s
    theta0[theta0<0] <- 0.000000001
    delta <- abs(theta - theta0)
    theta <- theta0
    if (verbose) print(paste(c("Iteration:",it,"Theta:",round(theta,5)), sep=""))
    if (it==maxit) break
  }
  V <- matrix(0,n,n)
  for ( i in 1:np) { V <- V + G[[i]]*theta[i] }
  chlV <- chol(V)
  remove(V)
  ldV <- log(sum(diag(chlV)))
  Vi <- chol2inv(chlV)
  remove(chlV)
  chlXVX <- chol(crossprod(X,crossprod(Vi,X) ))
  ldXVX <- log(sum(diag(chlXVX)))
  XViXi <- chol2inv(chlXVX)
  ViX <- crossprod(Vi,X)
  ViXXViXi <- tcrossprod(ViX,XViXi)
  b <- crossprod(ViXXViXi,y)
  vb <- XViXi
  P <- Vi - tcrossprod(ViXXViXi,ViX)
  trPG <- trVG <- rep(0,length(theta))
  for (i in 1:np) {
    trVG[i] <- sum(Vi*G[[i]])
    trPG[i] <- sum(P*G[[i]])
  } 
  Vy <- crossprod(Vi,y)
  remove(Vi)
  Py <- crossprod(P,y)
  yPy <- sum(y*Py)
  yVy <- sum(y*Vy)
  llik <- -0.5*(ldV+ldXVX+yPy)
  
  u <- NULL
  for (i in 1:(length(theta)-1)) {
    u <- cbind(u, crossprod(G[[i]]*theta[i],Py) )       
  }
  fitted <- X%*%b
  predicted <- rowSums(u)+fitted
  
  return(list( y=y, X=X, b=b, vb=vb, g=u, fitted=fitted, predicted=predicted, Py=Py, Vy=Vy, theta=theta, asd=theta.cov, llik=llik, niter=it,trPG=trPG, trVG=trVG,ids=names(y),yVy=yVy   ))
}


cvreml <- function(y=NULL, X=NULL, Glist=NULL, G=NULL, theta=NULL, ids=NULL, validate=NULL, maxit=100, tol=0.00001,bin=NULL,nthreads=1,wkdir=getwd(), verbose=FALSE)
{
  n <- length(y)     
  theta <- pa <- mspe <- yobs <- ypred <- r2 <- llik <- slope <- intercept <- NULL
  for (i in 1:ncol(validate)) {
    v <- validate[,i]
    t <- (1:n)[-v]
    fit <- remlR( y=y[t], X=X[t,], G=lapply(G,function(x){x[t,t]}), verbose=verbose)
    theta <- rbind(theta, as.vector(fit$theta))
    np <- length(fit$theta)
    yhat <- X[v, ] %*% fit$b
    for (j in 1:(np-1)) {
      yhat <- yhat + G[[j]][v,t]%*%fit$Py*fit$theta[j]
    }
    pa <- c(pa, cor(yhat, y[v]))
    mspe <- c(mspe, sum((yhat - y[v])^2)/length(v))
    intercept <- c(intercept,lm( y[v] ~ yhat )$coef[1])
    slope <- c(slope,lm( y[v] ~ yhat )$coef[2])
    r2 <- c(r2,summary(lm( y[v] ~ yhat ))$r.squared)
    llik <- c(llik,fit$llik)
    yobs <- c(yobs, y[v])
    ypred <- c(ypred, yhat)
    if (i > 1) {
      colnames(theta) <- c(names(G),"E")
      layout(matrix(1:4, ncol = 2))
      boxplot(pa, main = "Predictive Ability", ylab = "Correlation")
      boxplot(mspe, main = "Prediction Error", ylab = "MSPE")
      boxplot(theta, main = "Estimates", ylab = "Variance")
      plot(yobs, ypred, ylab = "Predicted", xlab = "Observed")
      coef <- lm(yobs ~ ypred)$coef
      abline(a = coef[1], b = coef[2], lwd = 2, col = 2, lty = 2)
    }
    
  }    
  res <- data.frame(pa,r2,intercept,slope,mspe,llik,theta)
  #return(list(pa=pa,mspe=mspe,theta=theta,ypred=ypred,yobs=yobs))
}


