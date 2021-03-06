#' Rank endpoints by category
#' 
#' The \code{endpoint_hits_DT} (data.table (DT) option) and \code{endpoint_hits} 
#' (data frame option) functions create tables with one row per endPoint, and 
#' one column per category("Biological", "Chemical", or "Chemical Class"). The 
#' values in the table are the number of sites where the EAR exceeded the 
#' user-defined EAR hit_threshold in that endpoint/category combination. If the 
#' category "Chemical" is chosen, an "info" link is provided to the 
#' chemical/endpoint information available in the "ToxCast Dashboard" 
#' \url{https://actor.epa.gov/dashboard/}.
#' 
#' The tables show slightly different results when choosing to explore data
#' from a single site rather than all sites. The value displayed in this 
#' instance is the number of samples with hits rather than the number of sites
#' with hits. 
#' 
#' @param chemicalSummary Data frame from \code{get_chemical_summary}
#' @param mean_logic Logical.  \code{TRUE} displays the mean sample from each site,
#' FALSE displays the maximum sample from each site.
#' @param sum_logic Logical. \code{TRUE} sums the EARs in a specified grouping,
#' \code{FALSE} does not. \code{FALSE} indicates that EAR values are not considered to be 
#' additive and often will be a more appropriate choice for traditional 
#' benchmarks as opposed to ToxCast benchmarks.
#' @param category Character. Either "Biological", "Chemical Class", or "Chemical".
#' @param hit_threshold Numeric. EAR threshold defining a "hit".
#' @param include_links Logical. whether or not to include a link to the ToxCast 
#' dashboard. Only needed for the "Chemical" category.
#' @export
#' @import DT
#' @rdname endpoint_hits_DT
#' @importFrom stats median
#' @importFrom tidyr spread unite
#' @importFrom dplyr full_join filter mutate select left_join right_join
#' @examples
#' # This is the example workflow:
#' path_to_tox <-  system.file("extdata", package="toxEval")
#' file_name <- "OWC_data_fromSup.xlsx"
#'
#' full_path <- file.path(path_to_tox, file_name)
#' \dontrun{
#' tox_list <- create_toxEval(full_path)
#' 
#' ACClong <- get_ACC(tox_list$chem_info$CAS)
#' ACClong <- remove_flags(ACClong)
#' 
#' cleaned_ep <- clean_endPoint_info(endPointInfo)
#' filtered_ep <- filter_groups(cleaned_ep)
#' chemicalSummary <- get_chemical_summary(tox_list, ACClong, filtered_ep)
#' 
#' hits_df <- endpoint_hits(chemicalSummary, category = "Biological")                        
#' endpoint_hits_DT(chemicalSummary, category = "Biological")
#' endpoint_hits_DT(chemicalSummary, category = "Chemical Class")
#' endpoint_hits_DT(chemicalSummary, category = "Chemical")
#' }
endpoint_hits_DT <- function(chemicalSummary, 
                           category = "Biological",
                           mean_logic = FALSE,
                           sum_logic = TRUE,
                           hit_threshold = 0.1,
                           include_links = TRUE){
  
  chnm <- CAS <- ".dplyr"

  fullData <- endpoint_hits(chemicalSummary = chemicalSummary,
                           category = category,
                           mean_logic = mean_logic,
                           sum_logic = sum_logic,
                           hit_threshold = hit_threshold)

  if(category == "Chemical"){
    orig_names <- names(fullData)
    
    casKey <- select(chemicalSummary, chnm, CAS) %>%
      distinct()
    
    numeric_hits <- fullData
    hits <- sapply(fullData, function(x) as.character(x))

    if(include_links){
      for(k in 1:nrow(fullData)){
        for(z in 2:ncol(fullData)){
          if(!is.na(fullData[k,z])){
            if(fullData[k,z] < 10){
              hit_char <- paste0("0",fullData[k,z])
            } else{
              hit_char <- as.character(fullData[k,z])
            }
            hits[k,z] <- paste(hit_char,createLink(cas = casKey$CAS[casKey$chnm == names(fullData)[z]],
                                    endpoint = fullData[k,1]))
          }
        }
      }
    }
    fullData <- data.frame(hits, stringsAsFactors = FALSE)
    names(fullData) <- orig_names
  }
  
  n <- ncol(fullData)-1
  
  if(n > 20 & n<30){
    colors <- c(brewer.pal(n = 12, name = "Set3"),
                brewer.pal(n = 8, name = "Set2"),
                brewer.pal(n = max(c(3,n-20)), name = "Set1"))
  } else if (n <= 20){
    colors <- c(brewer.pal(n = 12, name = "Set3"),
                brewer.pal(n =  max(c(3,n-12)), name = "Set2"))     
  } else {
    colors <- colorRampPalette(brewer.pal(11,"Spectral"))(n)
  }
  
  fullData_dt <- DT::datatable(fullData, extensions = 'Buttons',
                              escape = FALSE,
                              rownames = FALSE,
                              options = list(dom = 'Bfrtip',
                                             buttons = list('colvis'),
                                             scrollX = TRUE,
                                             order=list(list(1,'desc'))))
  
  for(i in 2:ncol(fullData)){
    fullData_dt <- formatStyle(fullData_dt,
                             names(fullData)[i],
                             backgroundColor = colors[i])

    if(category != "Chemical"){
      fullData_dt <- formatStyle(fullData_dt, names(fullData)[i],
                                 background = styleColorBar(range(fullData[,names(fullData)[i]],na.rm = TRUE), 'goldenrod'),
                                 backgroundSize = '100% 90%',
                                 backgroundRepeat = 'no-repeat',
                                 backgroundPosition = 'center' )      
    } 

  }
  
  return(fullData_dt)
}

#' @rdname endpoint_hits_DT
#' @export
endpoint_hits <- function(chemicalSummary, 
                         category = "Biological",
                         mean_logic = FALSE,
                         sum_logic = TRUE,
                         hit_threshold = 0.1){
  Bio_category <- Class <- EAR <- sumEAR <- value <- calc <- chnm <- choice_calc <- n <- nHits <- site <- ".dplyr"
  endPoint <- meanEAR <- nSites <- CAS <- ".dplyr"
  
  match.arg(category, c("Biological","Chemical Class","Chemical"))

  fullData_init <- data.frame(endPoint="",stringsAsFactors = FALSE)
  fullData <- fullData_init
  
  if(category == "Chemical"){
    chemicalSummary <- mutate(chemicalSummary, category = chnm)
  } else if (category == "Chemical Class"){
    chemicalSummary <- mutate(chemicalSummary, category = Class)
  } else {
    chemicalSummary <- mutate(chemicalSummary, category = Bio_category)
  }
  
  if(length(unique(chemicalSummary$site)) > 1){
    
    if(!sum_logic){
      fullData <- chemicalSummary %>%
        group_by(site, category, endPoint, date) %>%
        summarize(sumEAR = max(EAR)) %>%
        group_by(site, category, endPoint) %>%
        summarize(meanEAR = ifelse(mean_logic, mean(sumEAR),max(sumEAR))) %>%
        group_by(category, endPoint) %>%
        summarize(nSites = sum(meanEAR > hit_threshold)) %>%
        spread(category, nSites)       
    } else {
      fullData <- chemicalSummary %>%
        group_by(site, category, endPoint, date) %>%
        summarize(sumEAR = sum(EAR)) %>%
        group_by(site, category, endPoint) %>%
        summarize(meanEAR = ifelse(mean_logic, mean(sumEAR),max(sumEAR))) %>%
        group_by(category, endPoint) %>%
        summarize(nSites = sum(meanEAR > hit_threshold)) %>%
        spread(category, nSites)      
    }

  } else {
    if(!sum_logic){
      fullData <- chemicalSummary %>%
        group_by(category, endPoint) %>%
        summarise(nSites = sum(EAR > hit_threshold)) %>%
        spread(category, nSites)        
    } else {
      fullData <- chemicalSummary %>%
        group_by(category, endPoint, date) %>%
        summarize(sumEAR = sum(EAR)) %>%
        group_by(category, endPoint) %>%
        summarise(nSites = sum(sumEAR > hit_threshold)) %>%
        spread(category, nSites)      
    }
  }

  if(any(rowSums(fullData[,-1],na.rm = TRUE) > 0)){
    fullData <- fullData[(rowSums(fullData[,-1],na.rm = TRUE) != 0),]    
  }

  fullData <- fullData[, colSums(is.na(fullData)) != nrow(fullData)]

  sumOfColumns <- colSums(fullData[c(-1)],na.rm = TRUE)
  if(!all(sumOfColumns == 0)){
    orderData <- order(sumOfColumns,decreasing = TRUE)
    orderData <- orderData[sumOfColumns[orderData] != 0] + 1
    
    fullData <- fullData[,c(1,orderData)]   
  }
  
  fullData <- fullData[order(fullData[[2]], decreasing = TRUE),]
  
  return(fullData)
}

#' createLink
#' 
#' Create links
#' @param cas character
#' @param endpoint character
#' @param hits character
#' @export
#' @keywords internal
createLink <- function(cas, endpoint) {
  paste0('<a href="http://actor.epa.gov/dashboard/#selected/',cas,"+",endpoint,'" target="_blank">&#9432;</a>')
}