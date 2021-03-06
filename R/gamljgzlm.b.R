library(ggplot2)
#' @import ggplot2
gamljGzlmClass <- R6::R6Class(
  "gamljGzlmClass",
  inherit = gamljGzlmBase,
  private=list(
    .model=NA,
    .postHocRows=NA,
    .cleanData=function() {

        print("cleandata")      
        dep <- self$options$dep
        modelType<-self$options$modelSelection

        covs <- NULL
        if ('covs' %in% names(self$options))
            covs <- self$options$covs
      
        factors <- NULL
        if ('factors' %in% names(self$options))
           factors <- self$options$factors
      
        data <- self$data
        for (factor in factors) {
          data[[factor]] <- as.factor(data[[factor]])
        }
        
      
        for (contrast in self$options$contrasts) {
            levels <- base::levels(data[[contrast$var]])
            stats::contrasts(data[[contrast$var]]) <- .createContrasts(levels, contrast$type)
        }
      
        for (covariate in covs) 
            data[[covariate]] <- as.numeric(as.character(data[[covariate]]))

        for (scaling in self$options$scaling) 
            data[[scaling$var]]<-.scaleContinuous(data[[scaling$var]],scaling$type)

        na.omit(data)
    },
    .init=function() {
        print("init")      
        modelType<-self$options$modelSelection
        afamily<-mf.give_family(modelType)
        if (is.null(afamily))
            return()
        dep <- self$options$dep
        factors <- self$options$factors
        modelTerms <- private$.modelTerms()
        
        infoTable<-self$results$info
        info<-MINFO[[modelType]]
        infoTable$addRow(rowKey="mod",list(info="Model Type",value=info$name[[1]],comm=info$name[[2]]))
        infoTable$addRow(rowKey="link",list(info="Link function",value=info$link[[1]],comm=info$link[[2]]))
        infoTable$addRow(rowKey="family",list(info="Distribution",value=info$distribution[[1]],comm=info$distribution[[2]]))
        infoTable$addRow(rowKey="r2",list(info="R-squared",comm="Proportion of reduction of error"))
        infoTable$addRow(rowKey="aic",list(info="AIC",comm="Less is better"))
        infoTable$addRow(rowKey="dev",list(info="Deviance",comm="Less is better"))
        infoTable$addRow(rowKey="resdf",list(info="Residual DF",comm=""))
        
        if (modelType=="nb" || modelType=="poiover" || modelType=="poisson")
             infoTable$addRow(rowKey="devdf",list(info="Value/DF",comm="Close to 1 is better"))
        
        infoTable$addRow(rowKey="conv",list(info="Converged",comm="Whether the estimation found a solution"))
        if ("note" %in% names(info))
           infoTable$addRow(rowKey="note",list(info="Note",value=info$note[[1]],comm=info$note[[2]]))
        
        if (afamily=="not yet")
           return()
        
        if (length(modelTerms) == 0 | is.null(dep))
            return()
        
        data <- private$.cleanData()
        if (!is.data.frame(data))
            reject(data)
        # update info table based on data
        mi.update(infoTable,modelType,data,dep)
        
        anovaTable      <- self$results$main
        postHocTables   <- self$results$postHoc
        contrastsTables <- self$results$contrasts
        estimatesTable <- self$results$estimates
    
        # main table
        
        

      
        modelTerms <- private$.modelTerms()
        formula<-as.formula(jmvcore::constructFormula(dep, modelTerms))
        terms<-colnames(attr(terms(formula),"factors"))
        
        if (length(terms) > 0) {
             for (term in terms) {
               anovaTable$addRow(rowKey=term, list(name=.nicifyTerms(term)))
            }  
        
           anovaTable$addFormat(col=1, rowNo=1,format=Cell.BEGIN_GROUP)
           anovaTable$addFormat(col=1, rowNo=length(modelTerms), format=Cell.END_GROUP)
           
           } else {
           
           anovaTable$addRow(rowKey='.', list(name='.'))
           anovaTable$addFormat(col=1, rowKey='.', format=Cell.BEGIN_END_GROUP)
           }
      

      # estimates
           formula<-as.formula(jmvcore::constructFormula(dep, modelTerms))
           terms<-colnames(model.matrix(formula,data))  
           labels<-.getFormulaContrastsLabels(self$options$contrasts,formula,data) 
           ciWidth<-self$options$paramCIWidth
           estimatesTable$getColumn('cilow')$setSuperTitle(jmvcore::format('{}% Confidence Interval', ciWidth))
           estimatesTable$getColumn('cihig')$setSuperTitle(jmvcore::format('{}% Confidence Interval', ciWidth))
           
          if (afamily=="multinomial") {
             deplevels<-levels(data[[dep]])[-1]
             deplabels<-.contrastLabels(levels =levels(data[[dep]]),type = "dummy")
             old=1
             for (j in seq_along(deplevels)) 
                 for (i in seq_along(terms)) {
                     estimatesTable$addRow(rowKey=(10*i)+j, list(dep=deplabels[[j]],name=.nicifyTerms(terms[i]),label=.nicifyTerms(labels[i])))
                   #### make rows look nicer  ###
                     if (i==1)
                           estimatesTable$addFormat(rowKey=(10*i)+j, col=1, Cell.BEGIN_GROUP)

                     if (i==length(terms))
                       estimatesTable$addFormat(rowKey=(10*i)+j, col=1, Cell.END_GROUP)

                 }
           } else
                for (i in seq_along(terms)) {
                  estimatesTable$addRow(rowKey=i, list(name=.nicifyTerms(terms[i]),label=.nicifyTerms(labels[i])))
                }
       # contrasts
      
           for (contrast in self$options$contrasts) {
               table <- contrastsTables$addItem(contrast)
               var <- data[[contrast$var]]
               
               if (contrast$type=="default")
                  contrast$type="deviation"
               
               levels <- base::levels(var)
               labels <- .contrastLabels(levels, contrast$type)
               dummies<-paste(contrast$var,1:length(labels),sep="")
               groups<-paste(1:length(levels),levels,sep = "=", collapse = ", ")

               for (i in 1:length(labels)) {
                    table$addRow(rowKey=labels[[i]], values=list(contrast=labels[[i]],term=dummies[[i]],groups=groups))
               }
        
           }
      ######### simple effects tables ##############
      
           variable<-self$options$simpleVariable
           moderator<-self$options$simpleModerator
           threeway<-self$options$simple3way
           if (!is.null(variable) & !is.null(moderator)) {
               # N dummies in X-axis
               xlevels<-length(levels(data[[variable]]))
               xlevels<-ifelse(xlevels>1,(xlevels-1),1)
               # N levels of moderator
               modlevels<-length(levels(data[[moderator]]))
               modlevels<-ifelse(modlevels>1,modlevels,3)
               nrows<-modlevels*xlevels  
               div<-0.1
               if (afamily=="multinomial") {
                    div<-nrows
                    nrows<-modlevels*xlevels*(length(levels(data[[dep]]))-1)
               }
               # create the tables with right rows
               simpleEffectsTables<-self$results$simpleEffects
               simpleEffectsAnovas<-self$results$simpleEffectsAnovas
               if (!is.null(threeway)) {
                  mod2levels<-length(levels(data[[threeway]]))
                  mod2levels<-ifelse(mod2levels>1,mod2levels,3)
                } else
                      mod2levels<-1
               
                for (j in 1:mod2levels) {
                    title<-paste("Simple effects of",variable)
                    key<-paste(variable,j,sep="")
          
                   ## init simple ANOVA tables
                   ftable<-simpleEffectsAnovas$addItem(key=key)
                   ftable$setTitle(title)
                   
                   for (i in 1:modlevels) 
                       ftable$addRow(rowKey=i,list(variable=" "))        
                   
                   ## init simple parameters tables
                   ptable<-simpleEffectsTables$addItem(key=key)
                   ptable$setTitle(title)
                   for (i in 1:nrows) { 
                       ptable$addRow(rowKey=i,list(variable=" "))
                       sw<-(i %% div)
                       if (sw==1)
                       ptable$addFormat(rowKey=i,col=1,Cell.BEGIN_GROUP)
                   }

                }  
      }  # end of simple effects tables
      # post hoc
      tables<-self$results$postHoc
      tables<-rf.initPostHoc(data,self$options, tables,modelType=modelType)     

      # descriptives
      private$.initMeanTables(data)
      private$.initDescPlots(data)
    },
    .run=function() {

      STOP=FALSE
      print(".run")
      suppressWarnings({
        
        dep <- self$options$dep
        factors <- self$options$factors
        covs<-self$options$covs
        modelType<-self$options$modelSelection
        
        modelTerms <- private$.modelTerms()
        
        if (is.null(dep) ||  length(modelTerms) == 0)
          return()
        
        base::options(contrasts = c("contr.sum","contr.poly"))
        
        data <- private$.cleanData()
        #### more cleaning ####
        data<-mf.checkData(self$options,data,modelType)
        
        if (!is.data.frame(data))
               reject(data)
        

        
        ### get the tables ####
        anovaTable <- self$results$main
        estimatesTable <- self$results$estimates
        infoTable<-self$results$info
        
        ### estimate stuff
        formula <- jmvcore::constructFormula(dep, modelTerms)
        formula <- stats::as.formula(formula)
        model <- try(private$.estimate(formula, data))
        if (isError(model)) {
          message <- extractErrorMessage(model)
          reject(message)
        }
        private$.model <- model
        self$results$.setModel(model)
        infoTable$setRow(rowKey="r2",list(value=mi.rsquared(model)))
        infoTable$setRow(rowKey="aic",list(value=mf.getAIC(model)))
        infoTable$setRow(rowKey="dev",list(value=model$deviance))
        infoTable$setRow(rowKey="resdf",list(value=mf.getResDf(model)))
        if (modelType=="nb" || modelType=="poiover" || modelType=="poisson")
             infoTable$setRow(rowKey="devdf",list(value=mf.getValueDf(model)))
        if (modelType=="poiover") {
          infoTable$setRow(rowKey="r2",list(comm="Not available for quasi-poisson"))
          infoTable$setRow(rowKey="aic",list(comm="Not available for quasi-poisson"))
        }
        infoTable$setRow(rowKey="conv",mi.converged(model))
        
        
        anovaResults <- try(mf.anova(model))
          if (isError(anovaResults)) {
            message <- extractErrorMessage(anovaResults)
            anovaTable$setNote("anocrash",message)
            STOP<-TRUE
          }

        rowNames<-rownames(anovaResults)
        for (i in seq_along(rowNames)) {
          rowName <- rowNames[i]
          tableRow<-anovaResults[i,]
          colnames(tableRow)<-TCONV[["glm.f"]]
          anovaTable$setRow(rowNo=i, tableRow)
          }

        if (mi.aliased(model)) {
          infoTable$setRow(rowKey="conv",list(comm="Results may be misleading because of aliased coefficients. See Tables notes"))
          anovaTable$setNote("aliased",WARNS["ano.aliased"])    
          estimatesTable$setNote("aliased",WARNS["ano.aliased"])    
        }          
        parameters<-try(mf.summary(model))
        if (isError(parameters)) {
          message <- extractErrorMessage(parameters)
          estimatesTable$setNote("sumcrash",message)
          STOP<-T
        }
        #### confidence intervals ######
        ciWidth<-self$options$paramCIWidth/100
        if (self$options$showParamsCI) {
        citry<-try({
          ci<-mf.confint(model,level=ciWidth)
          colnames(ci)<-c("cilow","cihig")
          parameters<-cbind(parameters,ci) 
           })
        if (isError(citry)) {
          message <- extractErrorMessage(citry)
          infoTable$setRow(rowKey="conv",list(value="no"))
          estimatesTable$setNote("cicrash",paste(message,". CI cannot be computed"))
        }
        }
        for (i in 1:nrow(parameters)) {
          estimatesTable$setRow(rowNo=i,parameters[i,])
        }

        if (STOP)
            return()
        private$.populateSimple(private$.model)
        private$.prepareDescPlots(private$.model)
        private$.populatePostHoc(model)
        private$.populateDescriptives(model)
        
      }) # suppressWarnings
    },
 
.initMeanTables=function(data) {

  #### expected means ####
  if (self$options$eDesc) {
    emeansTables <- self$results$emeansTables
    factorsAvailable <- self$options$factors
    dep<-self$options$dep
    modelTerms<-private$.modelTerms()
    if (length(factorsAvailable) == 0) 
      return()
    for (term in modelTerms)
      if (all(term %in% factorsAvailable)) {
        mTable<-emeansTables$addItem(key=.nicifyTerms(jmvcore::composeTerm(term)))
        mTable$getColumn('upper')$setSuperTitle(jmvcore::format('{}% Confidence Interval', 95))
        mTable$getColumn('lower')$setSuperTitle(jmvcore::format('{}% Confidence Interval', 95))
        
        depLevel<-1
        istart<-0
        if (self$options$modelSelection=="logistic")
          mTable$getColumn("lsmean")$setTitle("Prob")
        if (self$options$modelSelection=="poisson")
          mTable$getColumn("lsmean")$setTitle("Mean Count")
        if (self$options$modelSelection=="linear")
          mTable$getColumn("lsmean")$setTitle("Mean")
        if (self$options$modelSelection=="multinomial") {
          mTable$getColumn("lsmean")$setTitle("Prob")
          # mTable$addColumn(name="dep", title="Response group", index=1)
          depLevel<-length(levels(data[[dep]]))
          istart<-1
        }
        
        
        ldata <- data[,term]
        ll <- sapply(term, function(a) base::levels(data[[a]]), simplify=F)
        ll$stringsAsFactors <- FALSE
        grid <- do.call(base::expand.grid, ll)
        grid <- as.data.frame(grid,stringsAsFactors=F)
        print(grid)
        for (i in seq_len(ncol(grid))) {
          colName <- colnames(grid)[[i]]
          mTable$addColumn(name=colName, title=term[i], index=i+istart)
        }
        
        for(j in seq_len(depLevel))
        for (i in seq_len(nrow(grid))) {
          tableRow <- as.data.frame(grid[i,],stringsAsFactors=F)
          colnames(tableRow)<-term
          mTable$addRow(rowKey=(j*10)+i, values=tableRow)
          #### make rows look nicer  ###
          if (i==1)
            mTable$addFormat(rowKey=(j*10)+i, col=1, Cell.BEGIN_GROUP)
          
          if (i==nrow(grid))
            mTable$addFormat(rowKey=(j*10)+i, col=1, Cell.END_GROUP)
          
        }
      }
  } # end of  means
  

},     

    .initPostHoc=function(data) {
      
      bs <- self$options$factors
      phTerms <- self$options$postHoc
      modelType <- self$options$modelSelection

      bsLevels <- list()
      for (i in seq_along(bs))
        bsLevels[[bs[i]]] <- levels(data[[bs[i]]])
      
      tables <- self$results$postHoc
      nDepLevels<-1
        
      if (modelType=='multinomial') {
      dep<-self$options$dep
      depLevels<-levels(data[[dep]])
      nDepLevels<-length(depLevels)
      
      }
      for (j in seq_len(nDepLevels))
       for (ph in phTerms) {
        table <- tables$get(key=ph)
        table$setTitle(paste0('Post Hoc Comparisons - ', stringifyTerm(ph)))
        lab<-paste(paste(ph,collapse = ","),paste(ph,collapse = ","),sep=" - ")
        table$getColumn("contrast")$setTitle(lab)
        eg<-nrow(expand.grid(bsLevels[ph]))
        nRows<-(eg*(eg-1))/2
        for (i in seq_len(nRows)) {
                table$addRow(rowKey=((j*10)+i))
                if (modelType=='multinomial')
                   table$setRow(rowKey=((j*10)+i),list(dep=depLevels[j]))
          #### make rows look nicer  ###
                if (i==1)
                   table$addFormat(rowKey=((j*10)+i), col=1, Cell.BEGIN_GROUP)
                if (i==nRows)
                   table$addFormat(rowKey=((j*10)+i), col=1, Cell.END_GROUP)
        }
       }
      },


     .populatePostHoc=function(model) {
      terms <- self$options$postHoc
      modelType <- self$options$modelSelection
      dep<-self$options$dep
      if (length(terms) == 0)
        return()
      tables <- self$results$postHoc
      
      postHocRows <- list()
      
      for (ph in terms) {
        
        table <- tables$get(key=ph)
                 
        term <- jmvcore::composeTerm(ph)
        termB64 <- jmvcore::composeTerm(toB64(ph))
        suppressWarnings({
          none <- mf.posthoc(model,ph,"none")
          bonferroni <- mf.posthoc(model,ph,"bonferroni")
          holm <-mf.posthoc(model,ph,"holm")
        }) # suppressWarnings
        if (is.character(none))
             table$setNote("nojoy",WARNS["ph.nojoy"])
        else {        
            tableData<-as.data.frame(none)
            tableData$contrast<-as.character(tableData$contrast)
            if (modelType=="multinomial") {
               colnames(tableData)<-c("contrast","dep","estimate","se","df","test","p")
               tableData$dep<-as.character(tableData$dep)
               tableData$pbonf<-bonferroni[,7]
               tableData$pholm<-holm[,7]
              }
            else {
               colnames(tableData)<-c("contrast","estimate","se","df","test","p")
               tableData$pbonf<-bonferroni[,6]
               tableData$pholm<-holm[,6]
            }
            .labs<-sapply(tableData$contrast, function(a) {
              strsplit(a,"[-/,]")
            })
            labs<-do.call("rbind",.labs)   
            colnames(labs)<-paste0("c",1:ncol(labs))
            for (i in 1:nrow(tableData)) {
              row<-tableData[i,]
              l<-labs[i,]
              table$setRow(rowNo=i, values=c(row,l))
            }
        }
      }
},
.populateDescriptives=function(model) {
  
  terms<-private$.modelTerms()
  
  if (self$options$eDesc) {
    meanTables<-self$results$emeansTables
    tables<-lf.meansTables(model,terms)  
    for (table in tables)  {
      key<-.nicifyTerms(jmvcore::composeTerm(attr(table,"title")))    
      mTable<-meanTables$get(key=key)
      for (i in seq_len(nrow(table))) {
        values<-as.data.frame(table[i,])
        mTable$setRow(rowNo=i,values)
      }
      note<-attr(table,"note")
      if (!is.null(note)) mTable$setNote(note,WARNS[note])
    }
  } # end of eDesc              
  
  
  
},

.populateSimple=function(model) {
  variable<-self$options$simpleVariable
  moderator<-self$options$simpleModerator
  threeway<-self$options$simple3way
  dep<-self$options$dep
  data<-mf.getModelData(model)
  simpleEffectsTables<-self$results$simpleEffects
  simpleEffectsAnovas<-self$results$simpleEffectsAnovas
  
  .fillTheFTable<-function(results,aTable) {
    ftests<-results[[2]]
    ### ftests      
    for (i in seq_len(dim(ftests)[1])) {
      tableRow<-ftests[i,]
      aTable$setRow(rowNo=i,tableRow)
    }
  } #### end of .fillTheFTable
  
  .fillThePTable<-function(results,aTable) {
    params<-results[[1]]
    if ("dep" %in% colnames(params)) {
      params<-params[order(params$dep),]
#      base<-levels(data[[dep]])[1]
#      params$dep<-paste(params$dep,base,sep="-")
    }
    for (i in seq_len(dim(params)[1])) 
         aTable$setRow(rowNo=i,params[i,])
    
  }  ##### end of .fillThePTable
  
  if (is.null(variable) | is.null(moderator)) 
    return()
  
  if (is.null(threeway)) {

    results<-lf.simpleEffects(model,variable,moderator)
    ### ftests
    key=paste(variable,1,sep="")
    ftable<-simpleEffectsAnovas$get(key=key)
    .fillTheFTable(results,ftable)      
    ### parameters
    ptable<-simpleEffectsTables$get(key=key)
    .fillThePTable(results,ptable)
    #### add some warning ####
    term<-.interaction.term(private$.model,c(variable,moderator))
    if (!is.null(term)) {
      if (.is.scaleDependent(private$.model,term))
        ptable$setNote("inter",WARNS["se.interactions"])
      else if (.term.develop(term)<length(private$.modelTerms()))
        ptable$setNote("covs",WARNS["se.covariates"])
    } else 
      ptable$setNote("noint",WARNS["se.noint"])
    
    ### end of warnings ###
  } else {
    data$mod2<-data[,threeway]
    if (is.factor(data$mod2)) {
      levs<-levels(data$mod2)
    } else 
      levs<-c(mean(data$mod2)-sd(data$mod2),mean(data$mod2),mean(data$mod2)+sd(data$mod2))
    for(i in seq_along(levs)) {
      newdata<-data
      if (is.factor(data$mod2))
        contrasts(newdata[,threeway])<-contr.treatment(length(levs),base=i)
      else
        newdata[,threeway]<-newdata[,threeway]-levs[i]
      
      ## make nice labels and titles
      lev<-ifelse(is.numeric(levs[i]),round(levs[i],digits=2),levs[i])
      title<-paste("Simple effects of ",variable," computed for",threeway,"at",lev)
      # re-estimate the model
      form<-formula(model)
      FUN<-mf.estimate(model)
      model0<-FUN(form,newdata)

      #### populate the R table
      results<-lf.simpleEffects(model0,variable,moderator)
      ### populate the Jamovi table
      key=paste(variable,i,sep="")
      ### F table
      ftable<-simpleEffectsAnovas$get(key=key)
      ftable$setTitle(title)
      .fillTheFTable(results,ftable)      
      ### parameters
      ptable<-simpleEffectsTables$get(key=key)
      ptable$setTitle(title)
      .fillThePTable(results,ptable)
    } 
  } # end of if (is.null(threeway)) 
  
},

##### model local function #########
#### we need an .estimate() here ###
     .estimate=function(form,data) {
        modelType<-self$options$modelSelection
        if (modelType=="multinomial") {
          mod<-nnet::multinom(form,data,model = T)
          mod$call$formula<-form
          return(mod)
        }
        if (modelType=="nb") {
          mod<-MASS::glm.nb(form,data)
          return(mod)
        }
        
        stats::glm(form,data,family=mf.give_family(modelType))
      },

    .modelTerms=function() {
      modelTerms <- self$options$modelTerms
      if (class(modelTerms)!="list")
      modelTerms<-private$.ff()
      # If we are in interactive mode the model should be well specified, otherwise (if R mode)
      # no modelTerms means full model
      modelTerms
    },
    .ff=function() {
      factors <- c(self$options$factors,self$options$covs)
      if (length(factors) > 1) {
        formula <- as.formula(paste('~', paste(paste0('`', factors, '`'), collapse='*')))
        terms   <- attr(stats::terms(formula), 'term.labels')
        modelTerms <- sapply(terms, function(x) as.list(strsplit(x, ':')), USE.NAMES=FALSE)
      } else {
        modelTerms <- as.list(factors)
      }
      
      for (i in seq_along(modelTerms)) {
        term <- modelTerms[[i]]
        quoted <- grepl('^`.*`$', term)
        term[quoted] <- substring(term[quoted], 2, nchar(term[quoted])-1)
        modelTerms[[i]] <- term
      }
      
      modelTerms
    },
#### here comes the plotting machine #######
    .initDescPlots=function(data) {
      isAxis <- ! is.null(self$options$plotHAxis)
      isMulti <- ! is.null(self$options$plotSepPlots)

      self$results$get('descPlot')$setVisible( ! isMulti && isAxis)
      self$results$get('descPlots')$setVisible(isMulti)

      if (isMulti) {
        sepPlotsName <- self$options$plotSepPlots
        sepPlotsVar <- data[[sepPlotsName]]
        if(is.factor(sepPlotsVar))
          sepPlotsLevels <- levels(sepPlotsVar)
        else 
          sepPlotsLevels <- c("-1 SD","Mean","+1 SD")   
        
        array <- self$results$descPlots
        for (level in sepPlotsLevels) {
          title<-paste(sepPlotsName,"=",level)
          array$addItem(title)
        }
      }
      
    },

.prepareDescPlots=function(model) {
  
  depName <- self$options$dep
  groupName <- self$options$plotHAxis
  
  if (length(depName) == 0 || length(groupName) == 0)
    return()
  
  linesName <- self$options$plotSepLines
  plotsName <- self$options$plotSepPlots
  errorBarType <- self$options$plotError
  optionRaw<-self$options$plotRaw
  optionRange<-self$options$plotDvScale
  referToData<-(optionRaw || optionRange)
  modelType <- self$options$modelSelection
  ciWidth   <- self$options$ciWidth
  
  if (referToData)
    rawData=lp.rawData(model,depName,groupName,linesName)
  else 
    rawData<-NULL
  
  predData<-lp.preparePlotData(model,groupName,linesName,plotsName,errorBarType,ciWidth)
  yAxisRange <- lp.range(model,depName,predData,rawData)
  
  if (!optionRaw)
    rawData<-NULL
  
  
  if (is.null(plotsName)) {
    image <- self$results$get('descPlot')
    image$setState(list(data=predData, raw=rawData, range=yAxisRange))
    if (modelType=="multinomial" && !is.null(linesName)) {
      n<-length(levels(predData[,"plots"]))
      image$setSize(500,(250*n))
    }
    
  } else {
    images <- self$results$descPlots
    i<-1
    if (modelType=="multinomial" && !is.null(linesName)) 
          levels<-levels(predData$plots2)
    else
          levels<-levels(predData$plots)
    for (key in images$itemKeys) {
      real<-levels[i]
      i<-i+1
      image <- images$get(key=key)
 
      if (modelType=="multinomial" && !is.null(linesName)) {
        n<-length(levels(predData[["plots"]]))
        image$setSize(500,(250*n))
        plotData=subset(predData,plots2==real)
      } else 
        plotData=subset(predData,plots==real)

      image$setState(list(data=plotData,raw=rawData, range=yAxisRange))
    }
  }
  
},


    .descPlot=function(image, ggtheme, theme, ...) {
         library(ggplot2)
         if (is.null(image$state))
         return(FALSE)
  
         depName <- self$options$dep
         groupName <- self$options$plotHAxis
         linesName <- self$options$plotSepLines
         plotsName <- self$options$plotSepPlots
         errorType <- self$options$plotError
         modelType <- self$options$modelSelection
         ciWidth   <- self$options$ciWidth
         
         if (errorType=="ci")
             errorType<-paste0(ciWidth,"% ",toupper(errorType))
         
         if (modelType=="multinomial")
                   p<-lp.linesMultiPlot(image,ggtheme,depName,groupName,linesName,errorType=errorType)
         else  if ( ! is.null(linesName)) {
                   p<-.twoWaysPlot(image,theme,depName,groupName,linesName,errorType)
               } else {
                      p<-.oneWayPlot(image,theme,depName,groupName,errorType)
               }       
         p<-p+ggtheme
         print(p)
         TRUE
      },

####### this is useful, although I do not know why :-) ########## 
    .sourcifyOption = function(option) {
      
      name <- option$name
      value <- option$value
      
      if (name == 'contrasts') {
        i <- 1
        while (i <= length(value)) {
          item <- value[[i]]
          if (item$type == 'default')
            value[[i]] <- NULL
          else
            i <- i + 1
        }
        if (length(value) == 0)
          return('')
      } else if (name == 'modelTerms') {
        if (base::identical(as.list(value), private$.ff()))
          return('')
      } else if (name == 'postHoc') {
        if (length(value) == 0)
          return('none')
      }
      super$.sourcifyOption(option)
    })
)

