#' @export
#'

auc <- function(yobs=NULL, ypred=NULL) {
     n0 <- length(yobs[yobs==0])
     n1 <- length(yobs[yobs==1])
     y <- cbind(yobs, ypred)
     y <- y[order(y[,2], decreasing=TRUE),]
     y <- cbind(y, seq(from=nrow(y), to=1))
     rd <- mean(y[y[,1]==1,][,3])
     auc <- (1/n0)*(rd-(n1/2)-(1/2))
     auc 
}

#' @export
#'

rnag <- function(yobs=NULL,ypred=NULL) {
     fit0 <- glm(yobs~1,family=binomial(link='logit'))
     fit1 <- glm(yobs~1+ypred,family=binomial(link='logit'))
     n <- length(yobs)
     LR <- anova(fit1)$Deviance[2]
     L0 <-  as.numeric(logLik(fit0))
     r2nag <- (1-exp(-LR/n))/(1-exp(-(-2*L0)/n))
     return(r2nag)
}

#' @export
#'

acc <- function(yobs=NULL,ypred=NULL,typeoftrait="quantitative") {
     fit <- lm(ypred ~ yobs)
     r2 <- summary(fit)$r.squared
     pa <- cor(ypred, yobs)
     mspe <- sum((ypred - yobs)^2)/length(yobs)
     intercept <- fit$coef[1]
     slope <- fit$coef[2]
     aurc <- r2nag <- NA
     if(typeoftrait=="binary") aurc <- auc(yobs=yobs,ypred=ypred)
     if(typeoftrait=="binary") r2nag <- rnag(yobs=yobs,ypred=ypred)
     res <- round(c(pa,r2,r2nag,aurc,intercept,slope,mspe),3)
     names(res) <- c("Corr","R2","Nagel R2", "AUC", "intercept", "slope", "MSPE")
     return(res)
}

#' @export
#'

fastlm <- function (y=NULL, X=NULL, sets=NULL) {
     
     XX <-crossprod(X)
     XXi <- chol2inv(chol(XX))
     Xy <- crossprod(X,y)
     coef <- crossprod(XXi,Xy)
     rownames(coef) <- colnames(X)
     yhat <- crossprod(t(X),coef)
     
     sse <- sum((y-yhat)**2)
     dfe <- length(y)-ncol(X)
     
     se <- sqrt(sse/dfe)*sqrt(diag(XXi))
     stat <- coef/se
     p <- 2 * pt(-abs(stat), df = dfe)
     names(se) <- colnames(X)
     
     sigma_e <- sse/dfe
     ftest <- NULL
     if (!is.null(sets)) {
          for ( i in 1:nsets) {
               rws <- sets[[i]]
               dfq <- length(rws)
               q <- crossprod(coef[rws,],crossprod(solve(XXi[rws,rws]*sigma_e),coef[rws,]))
               pq <- pchisq(q, df=dfq, lower.tail = FALSE)
               pfstat <- pf(q/dfq, dfq, dfe, lower.tail=FALSE)
               ftest <- rbind(ftest,c(q/dfq,dfq,dfe,pfstat))
          }
          colnames(ftest) <- c("F-stat","dfq","dfe","p")
          rownames(ftest) <- names(sets)
     }
     
     fit <- list(coef=coef,se=se,stat=stat,p=p,ftest=ftest, yhat=yhat) 
     
     return(fit)
     
} 



panel.cor <- function(x, y, ...) {
     par(usr = c(0, 1, 0, 1))
     txt <- paste("R2=",as.character(format(cor(x, y)**2, digits=2)))
     text(0.5, 0.5, txt, cex = 1, col=1)
}

get_lower_tri<-function(cormat){
     cormat[upper.tri(cormat)] <- NA
     return(cormat)
}
get_upper_tri <- function(cormat){
     cormat[lower.tri(cormat)]<- NA
     return(cormat)
}

reorder_cormat <- function(cormat){
     dd <- as.dist((1-cormat)/2)
     hc <- hclust(dd)
     cormat <-cormat[hc$order, hc$order]
     cormat
}

#' @export
#'

hmmat <- function(df=NULL,xlab="Cols",ylab="Rows",title=NULL,fname=NULL) {
     
     rowOrder <- order(rowSums(df))
     colOrder <- order(colSums(abs(df)))
     melted_df <- melt(df[rowOrder,colOrder], na.rm = TRUE)
     colnames(melted_df)[1:2] <- c(ylab,xlab)
     
     tiff(file=fname,res = 300, width = 2800, height = 2200,compression = "lzw")
     
     hmplot <- ggplot(melted_df, aes_string(y=ylab,x=xlab)) +
          ggtitle(title) +
          geom_tile(aes(fill = value)) + 
          scale_fill_gradient2(low = "blue", high = "red", mid = "white", midpoint = 0, space = "Lab", name="Statistics")  +
          theme(axis.text.x = element_text(angle = 45, vjust = 1, size = 8, hjust = 1)) + 
          coord_fixed()
     
     print(hmplot)
     
     dev.off()
     
}

#' @export
#'

hmcor <- function(df=NULL,fname=NULL) {
     cormat <- round(cor(df),2)
     cormat <- reorder_cormat(cormat)
     melted_cormat <- melt(get_upper_tri(cormat), na.rm = TRUE)
     colnames(melted_cormat)[1:2] <- c("Study1","Study2")
     
     tiff(file = fname,res = 300, width = 2800, height = 2200,compression = "lzw") 
     
     hmplot <- ggplot(melted_cormat, aes(Study2, Study1, fill = value)) +
          geom_tile(color = "white") +
          scale_fill_gradient2(low = "blue", high = "red", mid = "white", midpoint = 0, limit = c(-1,1), space = "Lab", name="Pearson\nCorrelation") +
          theme_minimal() + 
          theme(axis.text.x = element_text(angle = 45, vjust = 1, size = 12, hjust = 1)) +
          geom_text(aes(Study2, Study1, label = value), color = "black", size = 4) +
          coord_fixed()
     
     print(hmplot)
     dev.off()
}


# y <- c(5,8,6,2,3,1,2,4,5)     #dependent/observation
# x <- c(-1,-1,-1,0,0,0,1,1,1)  #independent
# d1 <- as.data.frame(cbind(y=y,x=x))
# 
# model <- glm(y~x, data=d1, family = poisson(link="log"))
# summary(model)
# 
# X <- cbind(1,x)
# 
# #write an interatively reweighted least squares function with log link
# glmfunc.log <- function(d,betas,iterations=1)
# {
#      X <- cbind(1,d[,"x"])
#      for(i in 1:iterations) {
#           z <- as.matrix(betas[1]+betas[2]*d[,"x"]+((d[,"y"]-exp(betas[1]+betas[2]*d[,"x"]))/exp(betas[1]+betas[2]*d[,"x"])))
#           W <- diag(exp(betas[1]+betas[2]*d[,"x"]))
#           betas <- solve(t(X)%*%W%*%X)%*%t(X)%*%W%*%z
#           print(betas) 
#      }
#      return(list(betas=betas,Information=t(X)%*%W%*%X))
# }
# 
# #run the function
# model <- glmfunc.log(d=d1,betas=c(1,0),iterations=10)
