####################################################################################################################
#    Module 5: GSOLVE 
####################################################################################################################


#' @export
#'

gscore <- function(Glist=NULL,S=NULL,ids=NULL,rsids=NULL,rws=NULL, cls=NULL, scaled=TRUE, msize=100, ncores=1) { 
     
     if (is.vector(S)) S <- as.matrix(S)
     rsids <- rownames(S)
     #if(any( !rsids%in%Glist$rsids )) stop("rsids not found in Glist")
     rsidsinWlist <- rsids%in%Glist$rsids
     if(any( !rsidsinWlist )) {
          warning("Some rsids not found in Glist")
          print(paste("Number of rsids missing;",sum(!rsidsinWlist)))
          print(paste("Number of rsids used;",sum(rsidsinWlist)))
          S <- S[rsidsinWlist,]
          rsids <- rownames(S)
     }
     
     nprs <- ncol(S)
     
     n <- Glist$n
     m <- Glist$m
     nbytes <- ceiling(n/4)
     cls <- match(rsids,Glist$rsids)
     nc <- length(cls)
     
     rws <- 1:n
     if(!is.null(ids)) rws <- match(ids,Glist$ids)
     if(!is.null(Glist$study_ids)) rws <- match(Glist$study_ids,Glist$ids)
     nr <- length(rws)
     
     
     fnRAW <- Glist$fnRAW
     # prsbed(n,nr,rws,nc,cls,scaled,nprs,s,prs,nbytes,fnRAW)
     # prsbed(n,nr,rws,nc,cls,scaled,nbytes,fnRAW,msize,ncores,nprs,s,prs)	
     prs <- .Fortran("mmbed", 
                     n = as.integer(n),
                     nr = as.integer(nr),
                     rws = as.integer(rws),
                     nc = as.integer(nc),
                     cls = as.integer(cls),
                     scaled = as.integer(scaled),
                     nbytes = as.integer(nbytes),
                     fnRAW = as.character(fnRAW),
                     msize = as.integer(msize),
                     ncores = as.integer(ncores),
                     nprs = as.integer(nprs),
                     s = matrix(as.double(S),nrow=nc,ncol=nprs),
                     prs = matrix(as.double(0),nrow=nr,ncol=nprs),
                     PACKAGE = 'qgg'
                     
     )
     colnames(prs$prs) <- colnames(S)
     rownames(prs$prs) <- Glist$ids[rws]
     return(prs$prs)
}



#' @export

gsolve <- function( y=NULL, X=NULL, W=NULL, sets=NULL, msets=100, lambda=NULL, validate=NULL, weights=FALSE, method="gsru", maxit=500, tol=0.0000001) { 
     if(is.null(validate)) {
        if(method=="gsru")  fit <- gsru(y=y, W=W, X=X, sets=sets, lambda=lambda, weights=weights, maxit=maxit, tol=tol)
        if(method=="gsqr")  fit <- gsqr(y=y, W=W, X=X, sets=sets,msets=msets,lambda=lambda,weights=weights, maxit=maxit, tol=tol)
     }
     if(!is.null(validate)) { 
          n <- length(y)     
          #pa <- mspe <- intercept <- slope <- r2 <- NULL
          res <- NULL
          for ( k in 1:ncol(validate)) {
               v <- validate[, k]
               t <- (1:n)[-v]
               if(method=="gsru")  fit <- gsru(y=y[t], X=as.matrix(X[t,]), W=W[t,], sets=sets, lambda=lambda, weights=weights, maxit=maxit, tol=tol)
               if(method=="gsqr")  fit <- gsqr(y=y[t], X=as.matrix(X[t,]), W=W[t,], sets=sets, msets=msets, lambda=lambda, weights=weights, maxit=maxit, tol=tol)
               #yv <- y[v]
               #yvhat <- W[v,]%*%fit$s
               #if(!is.null(X)) yvhat <- yvhat + X[v,]%*%fit$b
               yobs <- y[v]
               ypred <- W[v,]%*%fit$s
               if(!is.null(X)) ypred <- ypred + X[v,]%*%fit$b
               #r2 <- c(r2, summary(lm(yv ~ yvhat))$r.squared)
               #pa <- c(pa, cor(yvhat, yv))
               #mspe <- c(mspe, sum((yvhat - yv)^2)/length(yv))
               #intercept <- c(intercept, lm(yv ~ yvhat )$coef[1])
               #slope <- c(slope, lm(yv ~ yvhat)$coef[2])
               res <- rbind(res,qcpred(yobs=yobs,ypred=ypred))
          }
          #res <- data.frame(Corr=pa, R2=r2, R2NAG=NA, AUC=NA, intercept, slope, MSPE=mspe)
          #colnames(res)[3] <- "Nagel R2"
          fit <- res
     }   
     return(fit)         
}


#' @export

gsru <- function( y=NULL, X=NULL, W=NULL, sets=NULL, lambda=NULL, weights=FALSE, maxit=500, tol=0.0000001) { 
     n <- length(y)                        # number of observations
     m <- ncol(W)                          # number of markers
     dww <- rep(0,m)                       # initialize diagonal elements of the W'W matrix
     for( i in 1:m) { dww[i] <- sum(W[,i]**2) }                 
     b <- bold <- bnew <- NULL
     if (!is.null(X)) {
          b <- (solve(t(X)%*%X)%*%t(X))%*%y     # initialize b
          bold <- rep(0,ncol(X))              # initialize b
     }
     if(length(lambda)==1) { lambda <- rep(lambda,m)}
     e <- y
     if (!is.null(X)) e <- y-X%*%b                                # initialize e
     s <- (crossprod(W,e)/dww)/m      # initialize s
     sold <- rep(0,m)                      # initialize s
     if (weights) {
     p<- apply(W,2,function(x){cor.test(x,e)$p.value})
     logP <- -log10(p)
     lambda <- lambda/((logP/sum(logP))*ncol(W)) #1/logP
     }
     if(is.null(sets)) { sets <- as.list(1:m)} 
     nsets <- length(sets)
     nit <- 0
     delta <- 1
     while ( delta>tol ) {
          nit <- nit + 1
          for( i in 1:nsets) {
               rws <- sets[[i]] 
               lhs <- dww[rws] + lambda[rws]          # form lhs
               rhs <- crossprod(W[,rws],e) + dww[rws]*s[rws]  # form rhs with y corrected by other effects
               snew <- rhs/lhs
               e  <- e - tcrossprod(W[,rws],matrix((snew-s[rws]),nrow=1))          # update e with current estimate of b
               s[rws] <- snew                         # update estimates
          }
          gc()
          #if (!is.null(X)) {
          #  bnew <- solve(t(X)%*%X)%*%t(X)%*%e 
          #  e  <- e - X%*%(bnew-bold)            
          #}
          delta <- sum((s-sold)**2)
          #if (!is.null(X)) delta <- sum((s-sold)**2) + sum((b-bold)**2)
          delta <- delta/sqrt(m)
          sold <- s
          bold <- bnew 
          if (nit==maxit) break
          print(paste("Iteration",nit,"delta",delta))
     }
     ghat <- W%*%s
     if (!is.null(X)) b <- (solve(t(X)%*%X)%*%t(X))%*%(y-ghat)     # initialize b
     if (!is.null(X)) yhat <- ghat + X%*%b
     e <- y - yhat
     return(list(s=s,b=b,nit=nit,delta=delta, e=e, yhat=yhat, g=ghat))
}

#' @export

rsolve <- function( y=NULL, X=NULL, Glist=NULL, ids=NULL, rsids=NULL, sets=NULL, lambda=NULL, weights=FALSE, maxit=500, tol=0.0000001) { 
     
     cls <- match(rsids,Glist$rsids)
     
     maf <- unlist(Glist$maf)[cls]
     meanW <- 2*maf
     sdW <- sqrt(2*maf*(1-maf))
     gc()
     
     
     if(!is.null(ids)) yt <- y[ids]
     if(!is.null(ids)) Xt <- as.matrix(X[ids,])
     
     n <- Glist$n                        # number of observations
     m <- Glist$m                          # number of markers
     if(!is.null(rsids)) m <- length(rsids)
     rwsW <- 1:Glist$n 
     if(!is.null(ids)) rwsW <- match(ids,Glist$ids)
     b <- bold <- bnew <- NULL
     if (!is.null(X)) {
          b <- (solve(t(Xt)%*%Xt)%*%t(Xt))%*%yt     # initialize b
          bold <- rep(0,ncol(Xt))              # initialize b
     }
     e <- yt
     if (!is.null(Xt)) e <- yt-Xt%*%b         # initialize e
     
     if(length(lambda)==1) { lambda <- rep(lambda,m)}
     dww <- rep(0,m)                       # initialize diagonal elements of the W'W matrix
     s <- rep(0,m)                         # initialize diagonal elements of the W'W matrix
     
     current <- 0
     bfW <- file(Glist$fnRAW,"rb")
     for( i in 1:m ) {
      where <- (cls[i]-current-1)*Glist$n
      current <- cls[i]
      seek(bfW,where=where, origin="current", rw="read")
      w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
      #w[w>0] <- as.vector(scale(w[w>0]))
      w[w>0] <- (w[w>0]-1-meanW[i])/sdW[i]
      dww[i] <- sum(w[rwsW]**2)
      if(!dww[i]==0) s[i] <- (sum(w[rwsW]*e)/dww[i])/m      # initialize s
     } 
     close(bfW)
     gc()
     s[dww==0] <- 0
     sold <- rep(0,m)                      # initialize s
     nit <- 0
     delta <- 1
     while ( delta>tol ) {
       nit <- nit + 1
       bfW <- file(Glist$fnRAW,"rb")
       current <- 0
       for( i in 1:m) {
          where <- (cls[i]-current-1)*Glist$n
          current <- cls[i]
          seek(bfW, where=where, origin="current", rw="read")
          w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
          #w[w>0] <- as.vector(scale(w[w>0]))
          w[w>0] <- (w[w>0]-1-meanW[i])/sdW[i]
          lhs <- dww[i] + lambda[i]          # form lhs
          rhs <- crossprod(w[rwsW],e) + dww[i]*s[i]  # form rhs with y corrected by other effects
          snew <- rhs/lhs
          if(dww[i]==0) snew <- 0
          e  <- e - w[rwsW]*(snew-s[i])          # update e with current estimate of b
          s[i] <- snew                         # update estimates
        } 
        close(bfW) 
        gc()
        delta <- sum((s-sold)**2)/sqrt(m)
        sold <- s
        bold <- bnew 
        if (nit==maxit) break
        print(paste("Iteration",nit,"delta",delta))
     }
     names(s) <- rsids
     ghat <- rep(0,Glist$n)
     bfW <- file(Glist$fnRAW,"rb")
     current <- 0
     for( i in 1:m) {
       where <- (cls[i]-current-1)*Glist$n
       current <- cls[i]
       seek(bfW, where=where, origin="current", rw="read")
       w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
       #w[w>0] <- as.vector(scale(w[w>0]))
       w[w>0] <- (w[w>0]-meanW[i])/sdW[i]
       ghat <- ghat + w*s[i]
     } 
     close(bfW) 
     names(ghat) <- Glist$ids
     if (!is.null(X)) yhat <- ghat[names(y)] + X[names(y),]%*%b
     e <- y - yhat
     return(list(s=s,b=b,nit=nit,delta=delta, e=e, yhat=yhat, g=ghat[names(y)]))
}




#' @export

qrSets <- function( W=NULL, sets=NULL, msets=100, return.level="Q") {
     m <- ncol(W)
     if(is.null(sets)) sets <- split(1:m, ceiling(seq_along(1:m)/msets))
     qrR <- list() 
     for ( i in 1:length(sets) ) {
          qrW <- qr(W[,sets[[i]]])
          W[,sets[[i]]] <- qr.Q(qrW)
          qrR[[i]] <- qr.R(qrW) 
          gc()
     }
     QRlist <- W
     if(return.level=="QR") QRlist <- list(Q=W,R=qrR,sets=sets)
     return(QRlist)
}  

#' @export

plotGS <- function( fit=NULL, s=NULL, sets=NULL ) {
     if(is.null(s)) s <- fit$s
     m <- length(s) 
     plot(y=s,x=1:m,ylab="Coefficients",xlab="Position",col=1,   
          pch=".",frame.plot=FALSE)
     points(y=s[sets],x=(1:m)[sets],col=2)  
}  

gsqr <- function( y=NULL, X=NULL, W=NULL, sets=NULL, msets=100, lambda=NULL, weights=FALSE, maxit=500, tol=0.0000001) { 
     QRlist <- qrSets(W=W,msets=msets,return.level="QR")
     #lambdaR <- sapply(QRlist$R,function(x){(1/diag(x))**2})
     #lambda <- lambda*lambdaR 
     fit <- gsru(y=y, X=X, W=QRlist$Q, sets=QRlist$sets, lambda=lambda, weights=weights) 
     nsets <- length(QRlist$sets)
     for ( i in 1:nsets) {
          rws <- QRlist$sets[[i]]
          #fit$s[rws] <- solve(QRlist$R[[i]])%*%fit$s[rws,1]
          fit$s[rws] <- backsolve(QRlist$R[[i]],fit$s[rws,1])
     }
     return(fit)
}  

#' @export

fsolve <- function(n=NULL,nr=NULL,rws=NULL,nc=NULL,cls=NULL,scaled=TRUE,nbytes=NULL,fnRAW=NULL,ncores=1,nit=NULL,lambda=NULL,tol=NULL,y=NULL,g=NULL,e=NULL,s=NULL,meanw=NULL,sdw=NULL) { 

     OS <- .Platform$OS.type
     if(OS=="windows") fnRAW <- tolower(gsub( "/", "\\" , fnRAW, fixed=T ))    
     fit <- .Fortran("solvebed", 
           n = as.integer(n),
           nr = as.integer(nr),
           rws = as.integer(rws),
           nc = as.integer(nc),
           cls = as.integer(cls),
           scaled = as.integer(scaled),
           nbytes = as.integer(nbytes),
           fnRAW = as.character(fnRAW),
           ncores = as.integer(ncores),
           nit = as.integer(nit),
           lambda = as.double(lambda),
           tol = as.double(tol),
           y = as.double(y),
           g = as.double(g),
           e = as.double(e),
           s = as.double(s),
           mean = as.double(meanw),
           sd = as.double(sdw),
           PACKAGE = 'qgg'
     )
     return(fit)
}


#' @export


bigsolve <- function( y=NULL, X=NULL, Glist=NULL, ids=NULL, rsids=NULL, sets=NULL, scaled=TRUE, lambda=NULL, weights=FALSE, maxit=500, tol=0.00001, ncores=1) { 
     
     ids <- names(y)
     fnRAW <- Glist$fnRAW
     n <- Glist$n
     nbytes <- ceiling(n/4)
     cls <- match(rsids,Glist$rsids)
     nc <- length(cls)
     rws <- match(ids,Glist$ids)
     nr <- length(rws)

     maf <- unlist(Glist$maf)[cls]
     meanw <- 2*maf
     sdw <- sqrt(2*maf*(1-maf))

     b <- bold <- bnew <- NULL
     #if (!is.null(X)) {
     #     b <- (solve(t(Xt)%*%Xt)%*%t(Xt))%*%yt     # initialize b
     #     bold <- rep(0,ncol(Xt))              # initialize b
     #}
     
     #if (!is.null(Xt)) yt <- yt-Xt%*%b         # initialize e
     
     if(length(lambda)==1) { lambda <- rep(lambda,nc)}
     s <- rep(0,nc)                         # initialize diagonal elements of the W'W matrix
     
     yn <- gn <- en <- rep(0,n)
     yn[rws] <- as.vector(y)
     
     fit <- fsolve(n=n,nr=nr,rws=rws,nc=nc,cls=cls,scaled=scaled,nbytes=nbytes,fnRAW=fnRAW,ncores=ncores,nit=maxit,lambda=lambda,tol=tol,y=yn,g=gn,e=en,s=s,meanw=meanw,sdw=sdw) 
     #fit <- fsolve(n=n,nc=nc,cls=cls,nr=nr,rws=rws,fnRAW=fnRAW,nit=maxit,lambda=lambda,tol=tol,y=y,g=g,e=e,s=s,meanw=meanw,sdw=sdw)
     
     #if (!is.null(X)) yhat <- ghat[names(y)] + X[names(y),]%*%b
     yhat <- NULL
     names(fit$g) <- Glist$ids
     #e <- y - yhat
     delta <- NULL
     return(list(s=fit$s,b=b,nit=fit$nit,delta=delta, e=fit$e, yhat=yhat, g=fit$g))
}



#' bigsolve_old <- function( y=NULL, X=NULL, Glist=NULL, ids=NULL, rsids=NULL, sets=NULL, lambda=NULL, weights=FALSE, maxit=500, tol=0.0000001) { 
#'      
#'      indxSets <- lapply(Glist$rsids,function(x){ (1:length(x))[x%in%rsids] })
#'      rsidsSets <- lapply(Glist$rsids,function(x){ x[x%in%rsids] })
#'      rsids <- unlist(rsidsSets) # reordered rsids
#'      indxS <- lapply(rsidsSets,function(x){ match(x,rsids) })
#'      
#'      if(!is.null(ids)) yt <- y[ids]
#'      if(!is.null(ids)) Xt <- as.matrix(X[ids,])
#'      
#'      n <- Glist$n                        # number of observations
#'      m <- Glist$m                          # number of markers
#'      if(!is.null(rsids)) m <- length(rsids)
#'      rwsW <- 1:Glist$n 
#'      if(!is.null(ids)) rwsW <- match(ids,Glist$ids)
#'      b <- bold <- bnew <- NULL
#'      if (!is.null(X)) {
#'           b <- (solve(t(Xt)%*%Xt)%*%t(Xt))%*%yt     # initialize b
#'           bold <- rep(0,ncol(Xt))              # initialize b
#'      }
#'      e <- yt
#'      if (!is.null(Xt)) e <- yt-Xt%*%b         # initialize e
#'      
#'      if(length(lambda)==1) { lambda <- rep(lambda,m)}
#'      dww <- rep(0,m)                       # initialize diagonal elements of the W'W matrix
#'      s <- rep(0,m)                         # initialize diagonal elements of the W'W matrix
#'      
#'      for (chr in 1:length(indxSets)) {
#'           mChr <- length(indxSets[[chr]])          
#'           if(mChr>0) {
#'                bfW <- file(Glist$fnRAW[chr],"rb")
#'                for( i in 1:length(indxSets[[chr]])) {
#'                     rws <- indxS[[chr]][i]   
#'                     where <- (indxSets[[chr]][i]-1)*Glist$n 
#'                     seek(bfW,where=where, rw="read")
#'                     w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
#'                     w[w>0] <- as.vector(scale(w[w>0])) 
#'                     dww[rws] <- sum(w[rwsW]**2)
#'                     s[rws] <- (sum(w[rwsW]*e)/dww[rws])/m      # initialize s
#'                } 
#'                close(bfW) 
#'           }
#'      }
#'      s[dww==0] <- 0
#'      sold <- rep(0,m)                      # initialize s
#'      nit <- 0
#'      delta <- 1
#'      while ( delta>tol ) {
#'           nit <- nit + 1
#'           for (chr in 1:length(indxSets)) {
#'                mChr <- length(indxSets[[chr]])          
#'                if(mChr>0 ) {
#'                     bfW <- file(Glist$fnRAW[chr],"rb")
#'                     for( i in 1:mChr) {
#'                          rws <- indxS[[chr]][i]   
#'                          where <- (indxSets[[chr]][i]-1)*Glist$n 
#'                          seek(bfW,where=where, rw="read")
#'                          w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
#'                          w[w>0] <- as.vector(scale(w[w>0])) 
#'                          lhs <- dww[rws] + lambda[rws]          # form lhs
#'                          rhs <- crossprod(w[rwsW],e) + dww[rws]*s[rws]  # form rhs with y corrected by other effects
#'                          snew <- rhs/lhs
#'                          if(dww[rws]==0) snew <- 0
#'                          e  <- e - w[rwsW]*(snew-s[rws])          # update e with current estimate of b
#'                          s[rws] <- snew                         # update estimates
#'                     } 
#'                     close(bfW) 
#'                }
#'           }
#'           gc()
#'           delta <- sum((s-sold)**2)/sqrt(m)
#'           sold <- s
#'           bold <- bnew 
#'           if (nit==maxit) break
#'           print(paste("Iteration",nit,"delta",delta))
#'      }
#'      names(s) <- rsids
#'      ghat <- rep(0,n)
#'      for (chr in 1:length(indxSets)) {
#'           mChr <- length(indxSets[[chr]])          
#'           if(mChr>0 ) {
#'                bfW <- file(Glist$fnRAW[chr],"rb")
#'                for( i in 1:length(indxSets[[chr]])) {
#'                     rws <- indxS[[chr]][i]
#'                     where <- (indxSets[[chr]][i]-1)*Glist$n 
#'                     seek(bfW,where=where, rw="read")
#'                     w <- as.double(readBin( bfW, "raw", n=Glist$n, size = 1, endian = "little"))
#'                     w[w>0] <- as.vector(scale(w[w>0])) 
#'                     # check if coding is OK
#'                     ghat <- ghat + w*s[rws]
#'                } 
#'                close(bfW) 
#'           }
#'      }
#'      names(ghat) <- Glist$ids
#'      if (!is.null(X)) yhat <- ghat[names(y)] + X[names(y),]%*%b
#'      e <- y - yhat
#'      return(list(s=s,b=b,nit=nit,delta=delta, e=e, yhat=yhat, g=ghat[names(y)]))
#' }
#' 
#' 
#' 
#' bigsolve_old_old <- function( y=NULL, X=NULL, Glist=NULL, ids=NULL, rsids=NULL, sets=NULL, lambda=NULL, weights=FALSE, maxit=500, tol=0.0000001) { 
#'      
#'      if(!is.null(ids)) yt <- y[ids]
#'      if(!is.null(ids)) Xt <- as.matrix(X[ids,])
#'      
#'      n <- Glist$n                        # number of observations
#'      m <- Glist$m                          # number of markers
#'      rwsW <- 1:Glist$n 
#'      if(!is.null(ids)) rwsW <- match(ids,Glist$ids)
#'      b <- bold <- bnew <- NULL
#'      if (!is.null(X)) {
#'           b <- (solve(t(Xt)%*%Xt)%*%t(Xt))%*%yt     # initialize b
#'           bold <- rep(0,ncol(Xt))              # initialize b
#'      }
#'      if(length(lambda)==1) { lambda <- rep(lambda,m)}
#'      e <- yt
#'      if (!is.null(Xt)) e <- yt-Xt%*%b         # initialize e
#'      dww <- rep(0,m)                       # initialize diagonal elements of the W'W matrix
#'      s <- rep(0,m)                         # initialize diagonal elements of the W'W matrix
#'      bfW <- file(Glist$fnW,"rb")
#'      for( i in 1:m) {
#'           w <- readBin( bfW, "double", n=n, size = 8, endian = "little")
#'           dww[i] <- sum(w[rwsW]**2)
#'           s[i] <- (sum(w[rwsW]*e)/dww[i])/m      # initialize s
#'      } 
#'      close(bfW)
#'      sold <- rep(0,m)                      # initialize s
#'      if(is.null(sets)) { sets <- as.list(1:m)} 
#'      nsets <- length(sets)
#'      nit <- 0
#'      delta <- 1
#'      while ( delta>tol ) {
#'           nit <- nit + 1
#'           bfW <- file(Glist$fnW,"rb")
#'           for( i in 1:nsets) {
#'                rws <- sets[[i]] 
#'                lhs <- dww[rws] + lambda[rws]          # form lhs
#'                w <- readBin( bfW, "double", n=n, size = 8, endian = "little")
#'                rhs <- crossprod(w[rwsW],e) + dww[rws]*s[rws]  # form rhs with y corrected by other effects
#'                snew <- rhs/lhs
#'                e  <- e - w[rwsW]*(snew-s[rws])          # update e with current estimate of b
#'                s[rws] <- snew                         # update estimates
#'           }
#'           close(bfW)
#'           gc()
#'           delta <- sum((s-sold)**2)
#'           delta <- delta/sqrt(m)
#'           sold <- s
#'           bold <- bnew 
#'           if (nit==maxit) break
#'           print(paste("Iteration",nit,"delta",delta))
#'      }
#'      ghat <- rep(0,n)
#'      bfW <- file(Glist$fnW,"rb")
#'      for( i in 1:m) {
#'           w <- readBin( bfW, "double", n=n, size = 8, endian = "little")
#'           ghat <- ghat + w*s[i]
#'      } 
#'      close(bfW)
#'      names(ghat) <- Glist$ids
#'      if (!is.null(X)) yhat <- ghat[names(y)] + X[names(y),]%*%b
#'      e <- y - yhat
#'      return(list(s=s,b=b,nit=nit,delta=delta, e=e, yhat=yhat, g=ghat[names(y)]))
#' }
#' 
