library(dplyr)
library(CPOP)
library(glmnet)

Frankenstein_CPOP <- function(x_list, y_list, covariates = NULL, dataset_weights = NULL, sample_weights = FALSE) {

  # Catching some errors.
  # y must be a factor or else it will break.
  if(sum(!unlist(lapply(y_list, is.factor))) > 0) {
    factor_rank <- which(!unlist(lapply(y_list, is.factor)) != FALSE)
    stop("The outcome in positiion ", factor_rank, " is not a factor")
  }

  # Convert counts to ratios
  print("Calculating Pairwise Ratios of Features")
  x_list <- lapply(x_list, as.matrix)
  z_list <- lapply(x_list, CPOP::pairwise_col_diff)

  # Calculating the log fold change of each gene between conditions
  lfc <- list()
  print("Calculating Fold Changes of Pairwise Ratios")
  for(i in seq_along(z_list)) {
    lfc[[i]] <- lfc_calculate(z_list[[i]], y_list[[i]])
  }

  # Taking the average lfc across all datasets
  ## If there is some weights supplied
  if(!is.null(dataset_weights)) {
    # Sample weights
    print("Calculating Weights for each Dataset")
    sample.weights <- unlist(dataset_weights) %>%
      data.frame() %>%
      mutate(Organ = as.character(.)) %>%
      group_by(Organ) %>%
      summarise(n = n()) %>%
      mutate(freq = n / sum(n))
    un_weights <- unlist(dataset_weights) %>%
      data.frame() %>%
      mutate(Organ = as.character(.),
             weight = 1)
    for(i in 1:nrow(un_weights)) { # nolint
      idx <- which(un_weights$Organ[i] == sample.weights$Organ)
      un_weights$weight[i] <- sample.weights$freq[idx]
    }
    sample.weights <- un_weights$weight
  }

  # We want to account for datasets that do not have equal sample numbers
  ## If there are sample weights.
  if(sample_weights == TRUE) {
    print("Modifing Fold Change of Ratios based on sample_weights")
    lfc <- do.call("cbind", lfc)

    freq_samples <- sapply(x_list, dim)[1,] %>%
      data.frame() %>%
      tibble::rownames_to_column() %>%
      mutate(inv_freq = sum(.) / .)

    aggregate_lfc <- abs(apply(lfc, 1, function(x) weighted.mean(x,freq_samples$inv_freq)))
    variance_lfc <- sqrt(apply(lfc, 1, function(x) Hmisc::wtd.var(x,freq_samples$inv_freq)))
  }
  ## If there are none supplied.
  else if(sample_weights == FALSE) {
    lfc <- do.call("cbind", lfc)
    aggregate_lfc <- abs(apply(lfc, 1, mean))
    variance_lfc <- apply(lfc, 1, sd)
  }

  fudge_vector <- variance_lfc[variance_lfc != 0]
  fudge <- quantile(fudge_vector, 0.05, na.rm = TRUE)

  # Take a moderated test statistic
  print("Calculating Final Weights")
  moderated_test <- aggregate_lfc/(variance_lfc + fudge)

  # Preparring data for lasso model.
  lasso_x <- do.call("rbind", z_list)
  lasso_y <- factor(unlist(y_list))

  # Adding covariates to the model.
  if(!is.null(covariates)) {
    print("Fitting covariates into the model")
    covariates <- do.call("rbind", covariates)
    covariates <- covariates %>%
      data.frame()

    # Adding covariates to the final matrix.
    lasso_x <- cbind(lasso_x, covariates)
    lasso_x <- glmnet::makeX(as(lasso_x, "data.frame"))

    # Altering the wights of the final lasso model
    covariate_weights <- rep(Inf, ncol(glmnet::makeX(as(covariates, "data.frame"))))
    moderated_test <- append(moderated_test, covariate_weights)
    names(moderated_test) <- colnames(lasso_x)
  }

  # Using selectExponent to determine best exponent
  print("Determining Best Exponent")
  exponent <- selectExponent(lasso_x, lasso_y, weights_lasso, sample.weights = sample.weights)
  weights_lasso <- 1/(moderated_test)^(exponent)
  print(paste("The best exponent was: ",exponent))

  # Lasso model for all datasets with updated weights
  if(!is.null(dataset_weights)) {
    print("Fitting final lasso model")
    model <- glmnet::cv.glmnet(
      x = as.matrix(lasso_x),
      y = lasso_y,
      family = "binomial",
      weights = sample.weights,
      penalty.factor = weights_lasso,
      alpha = 1)
  }
  else if(is.null(dataset_weights)) {
    print("Fitting final lasso model")
    model <- glmnet::cv.glmnet(
      x = as.matrix(lasso_x),
      y = lasso_y,
      family = "binomial",
      penalty.factor = weights_lasso,
      alpha = 1)
  }

  result = list(models = model,
                feature = moderated_test)
  return(result)
}



predict_cpop2 = function(cpop_result, newx, covariates = NULL, s = "lambda.min") {
  # Determine z for the new x
  newz = CPOP::pairwise_col_diff(newx)
  if (!is.null(covariates)) {
    w3 <- glmnet::makeX(cbind(newz, covariates))
    result_response = predict(object = cpop_result, newx = w3, s = s,
                              type = "response")
  }
  else {
    result_response = predict(object = cpop_result, newx = newz, s = s,
                              type = "response")
  }
  return(result_response)
}