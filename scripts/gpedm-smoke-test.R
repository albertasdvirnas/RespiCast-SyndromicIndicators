#!/usr/bin/env Rscript
#
# Verifies that the GP-EDM stack is runnable in this checkout.
#
# 1. fits the GPEDM package example (checks the compiled code works at all)
# 2. fits a hierarchical GP-EDM to this hub's ARI target data and iterates a
#    4-week-ahead forecast, i.e. the shape of an actual IceLab-EDM submission
#
# Usage:   Rscript scripts/gpedm-smoke-test.R
# Options: GPEDM_SMOKE_LOCATIONS="BE,FR,NL,SE"  countries to fit (default: 4
#            longest series). "all" fits every eligible country, which is a
#            realistic run but takes many minutes - the default stays quick.

suppressPackageStartupMessages(library(GPEDM))

hub_root <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
if (is.na(hub_root)) {
  args <- commandArgs(trailingOnly = FALSE)
  this <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
  hub_root <- if (length(this)) {
    dirname(dirname(normalizePath(this)))
  } else {
    getwd()
  }
}

ok <- function(...) cat("PASS:", ..., "\n")
r2_of  <- function(fit) fit$insampfitstats[["R2"]]
rho_of <- function(fit) fit$pars[["rho"]]

# -- 1. package example -------------------------------------------------------
data(thetalog2pop)
ex <- fitGP(data = thetalog2pop, y = "Abundance", pop = "Population",
            time = "Time", E = 3, tau = 1, scaling = "local")
stopifnot(length(r2_of(ex)) == 1L, is.finite(r2_of(ex)), r2_of(ex) > 0.9)
ok(sprintf("GPEDM example fit, in-sample R2 = %.4f", r2_of(ex)))

# -- 2. this hub's ARI target data -------------------------------------------
target <- file.path(hub_root, "target-data", "latest-ARI_incidence.csv")
stopifnot(file.exists(target))

E <- 4L
H <- 4L   # the hub forecasts four weeks ahead

d <- read.csv(target)
d$truth_date <- as.Date(d$truth_date)
d <- d[!is.na(d$value), ]

# Countries need a series long enough to embed at E lags.
counts <- sort(table(d$location), decreasing = TRUE)
eligible <- names(counts)[counts >= 40]

sel <- Sys.getenv("GPEDM_SMOKE_LOCATIONS", unset = "")
locs <- if (identical(sel, "all")) {
  eligible
} else if (nzchar(sel)) {
  intersect(trimws(strsplit(sel, ",")[[1]]), eligible)
} else {
  utils::head(eligible, 4L)
}
stopifnot(length(locs) > 0)

d <- d[d$location %in% locs, ]
d <- d[order(d$location, d$truth_date), ]
# makelags wants a regular weekly index per country
d$tstep <- ave(as.integer(d$truth_date), d$location,
               FUN = function(x) (x - min(x)) / 7L)
cat(sprintf("INFO: %d rows across %d countries: %s\n",
            nrow(d), length(locs), paste(locs, collapse = ", ")))

lags <- makelags(data = d, y = "value", pop = "location", time = "tstep",
                 E = E, tau = 1, append = TRUE)
fit <- fitGP(data = lags, y = "value",
             x = paste0("value_", seq_len(E)),
             pop = "location", time = "tstep", scaling = "local")
stopifnot(length(r2_of(fit)) == 1L, is.finite(r2_of(fit)), r2_of(fit) > 0.5)
ok(sprintf("hierarchical GP-EDM on ARI data, in-sample R2 = %.4f, rho = %.4f",
           r2_of(fit), rho_of(fit)))

# -- 3. iterated 4-week-ahead forecast ---------------------------------------
fore <- makelags(data = d, y = "value", pop = "location", time = "tstep",
                 E = E, tau = 1, forecast = TRUE)
# blank rows for horizons 2..H, filled in as the model iterates forward
future <- expand.grid(tstep = seq_len(H - 1L), location = unique(fore$location),
                      stringsAsFactors = FALSE)
future$tstep <- future$tstep + fore$tstep[match(future$location, fore$location)]
blank <- matrix(NA_real_, nrow(future), E,
                dimnames = list(NULL, paste0("value_", seq_len(E))))
fore <- rbind(fore, cbind(future, blank))
fore <- fore[order(fore$location, fore$tstep), ]

pred <- predict_iter(fit, newdata = fore)
res <- pred$outsampresults
stopifnot(nrow(res) == length(locs) * H,
          all(is.finite(res$predmean)), all(is.finite(res$predsd)))
ok(sprintf("iterated %d-week forecast for %d countries (%d predictions)",
           H, length(locs), nrow(res)))

cat("\nfirst rows of the forecast:\n")
print(utils::head(res, 6))
cat("\nAll GP-EDM checks passed.\n")
