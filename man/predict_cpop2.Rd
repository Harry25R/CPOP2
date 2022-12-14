% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Frankenstein_CPOP.R
\name{predict_cpop2}
\alias{predict_cpop2}
\title{Prectict using the CPOP2 results.}
\usage{
predict_cpop2(cpop_result, newx, covariates = NULL, s = "lambda.min")
}
\arguments{
\item{cpop_result}{The output from the Frankenstein_CPOP function.}

\item{newx}{A matrix of the new data to be predicted. The columns should be features and the rows should be samples.}

\item{covariates}{A data frame of the same covariates that were used in the CPOP2 model, Default: NULL}

\item{s}{Lambda value for the lasso model, Default: 'lambda.min'}
}
\value{
A vector of predictions for the new data.
}
\description{
A prediction function for the CPOP2 model.
}
\examples{
\dontrun{
if(interactive()){
 #EXAMPLE1
 }
}
}
