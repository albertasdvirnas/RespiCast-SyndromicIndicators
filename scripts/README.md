# GP-EDM setup

Tooling that makes R's [GPEDM](https://tanyalrogers.github.io/GPEDM) package
(Gaussian Process regression for Empirical Dynamic Modeling, Munch & Rogers)
runnable against this hub's target data. This is the modelling stack behind the
`IceLab-EDM` submissions; nothing here touches `model-output/` or
`model-metadata/`, so hub validation is unaffected.

## Usage

```bash
./scripts/setup-gpedm.sh          # install R + the GP-EDM stack (idempotent)
Rscript scripts/gpedm-smoke-test.R  # verify it works end to end
```

In Claude Code on the web the setup runs automatically via
`.claude/hooks/session-start.sh`, so GP-EDM is ready when the session starts.

## What gets installed

| package | version tested | source |
| --- | --- | --- |
| R | 4.3.3 | Ubuntu `r-base-dev` |
| Rcpp | 1.0.12 | Ubuntu `r-cran-rcpp` |
| Matrix | 1.6.5 | Ubuntu `r-cran-matrix` |
| tgp | 2.4.22 | Ubuntu `r-cran-tgp` (laGP dependency) |
| laGP | 1.5.10 | source build from the CRAN mirror `github.com/cran/laGP` |
| GPEDM | 0.0.0.9010 | source build from `github.com/tanyalrogers/GPEDM` |

`laGP` and `GPEDM` are not in the Ubuntu archive, so they are compiled from
git. That path was chosen deliberately: **CRAN is blocked by the egress policy
of Claude Code's remote environment**, and `remotes::install_github()` does not
work there either because it fetches tarballs from `codeload.github.com`, which
is also blocked. Plain `git clone` of public repositories is allowed, so the
script clones and runs `R CMD INSTALL`. Where CRAN *is* reachable the script
still prefers distro packages for the dependencies and falls back to
`install.packages()` when apt is unavailable.

Overrides: `GPEDM_SRC_DIR` (clone location), `GPEDM_REPO`, `LAGP_REPO`.

## Smoke test

`scripts/gpedm-smoke-test.R` checks three things:

1. the GPEDM package example fits (proves the compiled code loads and runs);
2. a hierarchical GP-EDM fits this hub's `target-data/latest-ARI_incidence.csv`,
   pooling countries as populations with `E = 4` weekly lags;
3. `predict_iter()` produces an iterated 4-week-ahead forecast — the horizon the
   hub actually asks for — with finite mean and sd for every country.

It fits the four longest country series by default and takes ~20s. Set
`GPEDM_SMOKE_LOCATIONS="BE,FR,NL"` to pick countries, or `"all"` to fit every
eligible country (realistic, but many minutes).

The smoke test is a *runnability* check, not the IceLab-EDM model: it does no
hyperparameter selection, no quantile calibration, and writes no submission
file.

## Linting

```bash
Rscript -e 'lintr::lint("scripts/gpedm-smoke-test.R")'
```

`.lintr` at the repo root raises the line limit to 100 and allows UPPERCASE
names so that EDM notation (`E` for embedding dimension, `H` for horizon) can
match the GPEDM API.
