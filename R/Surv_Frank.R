#' @title TOP_surv
#' @description FUNCTION_DESCRIPTION
#' @param x_list A list of data frames, each containing the data for a single batch or dataset. Columns should be features and rows should be observations.
#' @param y_list A list of data frames, where the first columns in each data frame is the time and the second column is the event status. The length of this list should be the same as the length of x_list.
#' @return A cox net model
#' @details DETAILS
#' @examples
#'  #EXAMPLE1
#' @rdname Surv_Frank
#' @export
#' @importFrom ClassifyR colCoxTests
#' @importFrom CPOP pairwise_col_diff
#' @importFrom dplyr select
#' @importFrom Hmisc wtd.var
#' @importFrom tibble enframe
#' @importFrom tibble rownames_to_column column_to_rownames
#' @importFrom purrr reduce
#' @importFrom survival Surv
#' @importFrom glmnet cv.glmnet
#' @importFrom doParallel registerDoParallel
Surv_Frank <- function(
    x_list, y_list, nFeatures = 50, dataset_weights = NULL, 
    sample_weights = FALSE, nCores = 1
    ) {

    parallel <- FALSE
    # register parallel cluster
    if (nCores > 1) {
        parallel <- TRUE
        doParallel::registerDoParallel(nCores)
    }

    # create a loop to run through all datasets
    output <- list()
    for (i in seq_along(x_list)) {
        # Perform colCoxTests on each dataset
        output[[i]] <- ClassifyR::colCoxTests(
            as.matrix(x_list[[i]]), y_list[[i]], option = "fast"
        )
    }

    sig.genes <- colCoxTests_combine(output, nFeatures = nFeatures)

    pairwise_coefficients <- list()
    for (i in seq_along(x_list)) {
        # subset x_list with the rownames of output
        x_subset <- x_list[[i]][, sig.genes]

        # Calculate the pairwise_col_diff of z_list_subset
        z_subset <- CPOP::pairwise_col_diff(x_subset)

        # Run colCoxTests on z_subset
        pairwise_coefficients[[i]] <- ClassifyR::colCoxTests(
            z_subset, y_list[[i]], option = "fast"
        ) |>
            dplyr::select(coef) |>
            data.frame() |>
            tibble::rownames_to_column(var = "Gene")
    }

    # Merging pairwise_coefficients
    coefficients <- pairwise_coefficients |>
        purrr::reduce(dplyr::left_join, by = "Gene") |>
        tibble::column_to_rownames(var = "Gene")

    # If there are sample weights.
    if (sample_weights == TRUE){
        freq_samples <- sapply(x_list, dim)[1, ] |>
            tibble::enframe() |>
            dplyr::mutate(freq = value/sum(value)) |>
            dplyr::mutate(inv_freq = 1 / freq)

        mean_coefficients <- abs(
            apply(coefficients, 1, function(x) stats::weighted.mean(x, freq_samples$inv_freq))
        )
        sd_coefficients <- sqrt(
            apply(coefficients, 1, function(x) Hmisc::wtd.var(x, freq_samples$inv_freq))
        )
        fudge <- stats::quantile(sd_coefficients[sd_coefficients != 0], 0.05, na.rm = TRUE)
    }

    else if (sample_weights == FALSE) {
         # Calculate the average & sd of the coefficients across Datasets
        mean_coefficients <- abs(rowMeans(coefficients))
        sd_coefficients <- apply(coefficients, 1, sd)
        fudge <- stats::quantile(sd_coefficients[sd_coefficients != 0], 0.05, na.rm = TRUE)
    }

    ## If there is some weights supplied
    if (!is.null(dataset_weights)) {
        # Sample weights
        message("Calculating Weights for each Dataset")
        sample.weights <- unlist(dataset_weights) |>
            data.frame() |>
            dplyr::mutate(Organ = as.character(.)) |>
            dplyr::group_by(Organ) |>
            dplyr::summarise(n = dplyr::n()) |>
            dplyr::mutate(freq = n / sum(n))
        un_weights <- unlist(dataset_weights) |>
            data.frame() |>
            dplyr::mutate(
                Organ = as.character(.),
                weight = 1
            )
        for (i in seq_len(nrow(un_weights))) {
            idx <- which(un_weights$Organ[i] == sample.weights$Organ)
            un_weights$weight[i] <- sample.weights$freq[idx]
        }
        sample.weights <- un_weights$weight
    }

    # Calculate the final weights
    weights <- mean_coefficients / (sd_coefficients + fudge)
    final_weights <- 1 / (weights)^(1 / 2)

    # Extract the pairwise ratios for significant genes
    x_list <- lapply(x_list, function(x) x[, sig.genes])
    z_list <- lapply(x_list, CPOP::pairwise_col_diff)
    z_list <- do.call("rbind", z_list)

    # Cleaning the outcome variable
    survival_y <- do.call("rbind", y_list)
    Surv_y <- survival::Surv(
        time = survival_y[, 1], event = survival_y[, 2], type = "right"
    )

    # Run a coxnet model with the final_weights as penalty factors
    coxnet_model <- glmnet::cv.glmnet(
        x = as.matrix(z_list),
        y = Surv_y, family = "cox", type.measure = "C",
        penalty.factor = final_weights,
        parallel = parallel
    )
    coxnet_model <- list(coxnet_model, sig.genes)

    return(coxnet_model)
}


#' @title Create a prediction function.
#' @description FUNCTION_DESCRIPTION
#' @param coxnet_model PARAM_DESCRIPTION
#' @param newx PARAM_DESCRIPTION
#' @return OUTPUT_DESCRIPTION
#' @examples
#'  #EXAMPLE1
#' @rdname Surv_Frank_Pred
#' @export
#' @importFrom CPOP pairwise_col_diff
Surv_Frank_Pred <- function(coxnet_model, newx) {
    # Calculate the pairwise differences of x
    newx <- newx[, coxnet_model[[2]]]
    z <- CPOP::pairwise_col_diff(newx)

    # Predict the survival time
    survScores <- stats::predict(
        coxnet_model[[1]], as.matrix(z), type = "response", newoffset = offset
    )

    return(survScores)
}


#' @title Create a function to calculate the concordance index.
#' @description FUNCTION_DESCRIPTION
#' @param coxnet_model PARAM_DESCRIPTION
#' @param newx PARAM_DESCRIPTION
#' @param newy PARAM_DESCRIPTION
#' @return OUTPUT_DESCRIPTION
#' @examples
#'  # EXAMPLE1
#' @rdname Surv_Frank_CI
#' @export
#' @importFrom CPOP pairwise_col_diff
#' @importFrom survival concordance
Surv_Frank_CI <- function(coxnet_model, newx, newy) {
    # Calculate the pairwise differences of x
    newx <- newx[, coxnet_model[[2]]]
    z <- CPOP::pairwise_col_diff(newx)

    # Predict the survival time
    survScores <- stats::predict(coxnet_model[[1]], as.matrix(z), type = "response", newoffset = offset)

    # Calculate the concordance index
    CI <- survival::concordance(survival::Surv(newy[, 1], newy[, 2]) ~ survScores)

    return(CI)
}