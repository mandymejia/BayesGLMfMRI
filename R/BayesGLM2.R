#' Group-level Bayesian GLM
#'
#' Performs group-level Bayesian GLM estimation and inference using the joint
#'  approach described in Mejia et al. (2020).
#'
#' @inheritSection INLA_Description INLA Requirement
#'
#' @param results Either (1) a length \eqn{N} list of \code{"BGLM"} objects,
#'  or (2) a length \eqn{N} character vector of files storing \code{"BGLM"}
#'  objects saved with \code{\link{saveRDS}}. \code{"fit_bglm"} objects
#'  also are accepted.
#' @param contrasts (Optional) A list of contrast vectors that specify the
#'  group-level summaries of interest. If \code{NULL} (DEFAULT), use contrasts that
#'  compute the average of each field (field HRF) across all subjects/sessions.
#'
#'  Each contrast vector is length \eqn{KSN} specifying a group-level summary of
#'  interest, where \eqn{K} is the number of fields in the first-level design
#'  matrices, \eqn{S} is the number of sessions, and \eqn{N} is the number of
#'  subjects. The vector is grouped by fields, then sessions, then subjects.
#'
#'  For a single session/subject, the contrast vector for the first field would be:
#'
#'  \code{c0 <- c(1, rep(0, K-1)) #indexes the first field for a single session}
#'
#'  so the full contrast vector for the group *average over all sessions/subjects
#'  for the first field* would be:
#'
#'  \code{contrasts = rep(c0, S*N) /(S*N)}.
#'
#'  To obtain the group average for the first field, for *just the first session*,
#'  input zeros for the remaining sessions:
#'
#'  \code{c2 <- c(c0, rep(0, K*(S-1)))}
#'  \code{contrasts = rep(c2, N) /N}.
#'
#'  To obtain the group mean *difference between two sessions* (\eqn{S=2}) for the first field:
#'
#'  \code{c3 <- c(c0, -c0)}
#'  \code{contrasts = rep(c3, N) / N}.
#'
#'  To obtain the *mean over sessions* of the first field, just for the first subject:
#'
#'  \code{c4 <- rep(c0, S)}
#'  \code{c(c4, rep(0, K*S*(N-1))) / S}.
#'
#' @param quantiles (Optional) Vector of posterior quantiles to return in
#'  addition to the posterior mean.
#' @param excursion_type (For inference only) The type of excursion function for
#'  the contrast (">", "<", "!="), or a vector thereof (each element
#'  corresponding to one contrast).  If \code{NULL}, no inference performed.
#' @param contrast_names (Optional) Names of contrasts.
#' @param gamma (For inference only) Activation threshold for the excursion set,
#'  or a vector thereof (each element corresponding to one contrast). Default:
#'  \code{0}.
#' @param alpha (For inference only) Significance level for activation for the
#'  excursion set, or a vector thereof (each element corresponding to one
#'  contrast). Default: \code{.05}.
#' @param nsamp_theta Number of theta values to sample from posterior. Default:
#'  \code{50}.
#' @param nsamp_beta Number of beta vectors to sample conditional on each theta
#'  value sampled. Default: \code{100}.
#' @param num_cores The number of cores to use for sampling betas in parallel. If
#'  \code{NULL} (default), do not run in parallel.
#' @inheritParams verbose_Param
#'
#' @return A list containing the estimates, PPMs and areas of activation for each contrast.
#'
#' @importFrom MASS mvrnorm
#' @importFrom Matrix bdiag crossprod
#' @importFrom ciftiTools as.xifti
#'
#' @export
BayesGLM2 <- function(
  results,
  contrasts = NULL,
  quantiles = NULL,
  excursion_type=NULL,
  contrast_names = NULL,
  gamma = 0,
  alpha = 0.05,
  nsamp_theta = 50,
  nsamp_beta = 100,
  num_cores = NULL,
  verbose = 1){

  if (!requireNamespace("abind", quietly = TRUE)) {
    stop("`BayesGLM2` requires the `abind` package. Please install it.", call. = FALSE)
  }

  # Check `results`, reading in the files if needed.
  results_ok <- FALSE
  if (is.character(results)) {
    if (!all(file.exists(results))) {
      stop("`results` is a character vector, but not all elements are existing files.")
    }
    results <- lapply(results, readRDS) # [TO DO]: delete w/ each read-in, stuff not needed
  }
  if (!is.list(results)) {
    stop("`results` must be a list of all `'BGLM'` or all `'fit_bglm'` objects, or a character vector of files with `'BGLM(0)'` results.")
  }
  is_BGLM <- all(vapply(results, inherits, FALSE, "fit_bglm"))
  is_cifti <- all(vapply(results, inherits, FALSE, "BGLM"))
  if (!is_BGLM && !is_cifti) {
    stop("`results` must be a list of all `'BGLM'` or all `'fit_bglm'` objects, or a character vector of files with `'BGLM(0)'` results.")
  }
  rm(is_BGLM) # use `is_cifti`

  model_names <- if (is_cifti) {
    names(results[[1]]$BGLMs)[!vapply(results[[1]]$BGLMs, is.null, FALSE)]
  } else {
    "BayesGLM"
  }

  nM <- length(model_names)                 # models
  nN <- length(results)                     # subjects
  nS <- length(results[[1]]$session_names)  # sessions
  nK <- length(results[[1]]$field_names)     # fields

  session_names <- results[[1]]$session_names
  field_names <- results[[1]]$field_names

  # Check that every subject has the same models, sessions, fields
  for (nn in seq(nN)) {
    sub_nn <- results[[nn]]
    if (is_cifti) {
      stopifnot(identical(
        model_names,
        names(sub_nn$BGLMs)[!vapply(sub_nn$BGLMs, is.null, FALSE)]
      ))
    }
    stopifnot(identical(session_names, sub_nn$session_names))
    stopifnot(identical(field_names, sub_nn$field_names))
  }

  # Check `contrasts`.
  # `contrasts` should be fields * sessions * subjects
  if(!is.null(contrasts) & !is.list(contrasts)) contrasts <- list(contrasts)
  if(is.null(contrasts)) {
    if (verbose>0) cat('Using a contrast that computes the average across subjects for each field. If other contrasts are desired, provide `contrasts`.\n')
    contrasts <- vector('list', length=nK)
    names(contrasts) <- paste0(field_names, '_avg')
    for (kk in 1:nK) {
      # (1/J, 0, 0, ..., 0) for k=1,
      # (0, 1/J, 0, ..., 0) for k=2,
      # ...,
      # (0, 0, ..., 0, 1/J) for k=K
      # for each session, for each subject
      # where J == S * N
      contrast_1 <- c(rep(0, kk-1), 1/(nS*nN), rep(0, nK-kk)) # length nK
      contrasts[[kk]] <- rep(rep(contrast_1, nS), nN)         # length nK*nS*nN
    }
  } else {
    #Check that each contrast vector is numeric and length J*K
    if(any(sapply(contrasts, length) != nK*nS*nN)) {
      stop('Each contrast vector must be of length K*S*N (fields times sessions times subjects).')
    }
    if(any(!sapply(contrasts, is.numeric))) {
      stop('Each contrast vector must be numeric, but at least one is not.')
    }
    if (is.null(names(contrasts))) {
      names(contrasts) <- paste0("contrast_", seq(length(contrasts)))
    }
  }
  # Override `names(contrasts)` with `contrast_names` if provided.
  if (!is.null(contrast_names)) {
    stopifnot(length(contrast_names) == length(contrasts))
    names(contrasts) <- contrast_names
  }
  nC <- length(contrasts)

  #Check `quantiles`
  if(!is.null(quantiles)){
    stopifnot(is.numeric(quantiles))
    if(any(quantiles > 1 | quantiles < 0)) stop('All elements of `quantiles` must be between 0 and 1.')
  }

  do_excur <- !is.null(excursion_type) && (!identical(excursion_type, "none"))
  if (do_excur) {
    if(length(excursion_type) == 1) excursion_type <- rep(excursion_type, nC)
    if(length(gamma) == 1) gamma <- rep(gamma, nC)
    if(length(alpha) == 1) alpha <- rep(alpha, nC)
    if(length(gamma) != nC) stop('Length of gamma must match number of contrasts or be equal to one.')
    if(length(alpha) != nC) stop('Length of alpha must match number of contrasts or be equal to one.')
    if(length(excursion_type) != nC) stop('Length of excursion_type must match number of contrasts or be equal to one.')
  } else {
    excursion_type <- 'none'
  }

  out <- vector("list", nM)
  names(out) <- model_names

  for (mm in 1:nM) {

    if (nM>1) { if (verbose>0) cat(model_names[mm], " ~~~~~~~~~~~\n") }
    results_mm <- if (is_cifti) {
      lapply(results, function(x){ x$BGLMs[[mm]] })
    } else {
      results
    }

    # We know model names match, but still check `spatial_type` match.
    spatial_type <- sapply(results_mm, function(x){
      if('surf' %in% names(x$spatial)) { 'surf' } else if('labels' %in% names(x$spatial)) { 'voxel' } else { stop() } })
    spatial_type <- unique(spatial_type)
    if (length(spatial_type) != 1) {
      stop("`spatial_type` is not unique across subjects for model ", model_names[mm], ".")
    }

    # `Mask`, `mesh`, `spde`, `Amat`
    if (spatial_type == "surf") {
      Mask <- lapply(results_mm, function(x){ x$spatial$mask })
      if (length(unique(vapply(Mask, length, 0))) != 1) {
        stop("Unequal mask lengths--check that the input files are in the same resolution.")
      }
      Mask <- do.call(rbind, Mask)

      # If models have different masks.
      Mask_is_new <- !all(colSums(Mask) %in% c(0, nrow(Mask)))
      Mask <- apply(Mask, 2, all)
      if (Mask_is_new) {
        for (nn in seq(nN)) {
          # [TO DO] test this
          results_mm[[nn]] <- retro_mask_BGLM(
            results_mm[[nn]], Mask[results_mm[[nn]]$mask]
          )
        }
      }

      mesh <- results_mm[[1]]$spde$mesh
      if (Mask_is_new) {
        mesh <- retro_mask_mesh(mesh, Mask[results_mm[[1]]$mask])
      }
      spde <- INLA::inla.spde2.matern(mesh)

      # `Amat`
      Amat <- INLA::inla.spde.make.A(mesh) #Psi_{km} (for one field and subject, a VxN matrix, V=num_vox, N=num_mesh)
      Amat <- Amat[mesh$idx$loc,]

    } else if (spatial_type == "voxel") {
      # Check features of spatial that are expected to match for all subjects.
      spatials_expEq <- unique(lapply(results_mm, function(x){ x$spatial[c(
        "spatial_type", "labels", "trans_mat", "trans_units,",
        "nbhd_order", "buffer")] }))
      if (length(unique(spatials_expEq)) != 1) {
        stop("`spatial`s for voxel model are expected to match, differing only in the `buffer_mask`.")
      }
      spatials_expEq <- spatials_expEq[[1]]

      Mask <- lapply(results_mm, function(x){ x$spatial$buffer_mask })
      if (length(unique(vapply(Mask, length, 0))) != 1) {
        stop("Unequal mask lengths--check that the input files are in the same resolution.")
      }
      Mask <- do.call(rbind, Mask)
      Mask_is_new <- !all(colSums(Mask) %in% c(0, nrow(Mask)))
      Mask <- apply(Mask, 2, all)
      if (verbose > 0 && Mask_is_new) { cat("Number of in-mask locations: ", sum(Mask)) }

      # Get `spde`
      # SPDE_from_voxel(spatial, logkappa = NULL, logtau = NULL)
      spde <- lapply(results_mm, function(x){ x$spde })
      if (length(unique(spde)) != 1) {
        stop("spde for voxel model are not the same--not supported.")
      }
      spde <- spde[[1]]

      mesh <- results_mm[[1]]$spde$mesh
      Amat <- make_A_mat(results_mm[[1]]$spatial) #[TO DO]?
    }

    Amat.tot <- bdiag(rep(list(Amat), nK)) #Psi_m from paper (VKxNK)

    # Collecting theta posteriors from subject models
    Qmu_theta <- Q_theta <- 0
    # Collecting X and y cross-products from subject models (for posterior distribution of beta)
    Xcros.all <- Xycros.all <- vector("list", nN)
    for (nn in seq(nN)) {
      # Check that mesh has same neighborhood structure
      if (!all.equal(results_mm[[nn]]$mesh$faces, mesh$faces, check.attribute=FALSE)) {
        stop(paste0(
          'Subject ', nn,
          ' does not have the same mesh neighborhood structure as subject 1.',
          ' Check meshes for discrepancies.'
        ))
      }

      #Collect posterior mean and precision of hyperparameters
      mu_theta_mm <- results_mm[[nn]]$INLA_model_obj$misc$theta.mode
      Q_theta_mm <- solve(results_mm[[nn]]$INLA_model_obj$misc$cov.intern)
      #iteratively compute Q_theta and mu_theta (mean and precision of q(theta|y))
      Qmu_theta <- Qmu_theta + as.vector(Q_theta_mm%*%mu_theta_mm)
      Q_theta <- Q_theta + Q_theta_mm
      rm(mu_theta_mm, Q_theta_mm)

      # compute Xcros = Psi'X'XPsi and Xycros = Psi'X'y
      # (all these matrices for a specific subject mm)
      y_vec <- results_mm[[nn]]$y
      X_list <- results_mm[[nn]]$X

      if (spatial_type=="voxel") {
        for (ss in seq(nS)) {
          # X_list[[ss]][,rep(Mask, times = nK)] <- 0 # Too computationally intensive
          X_list[[ss]] <- dgCMatrix_cols_to_zero(X_list[[ss]], which(rep(!Mask, times=nK)))
        }
      }

      if (length(X_list) > 1) {
        n_sess <- length(X_list)
        X_list <- Matrix::bdiag(X_list) #block-diagonialize over sessions
        Amat.final <- Matrix::bdiag(rep(list(Amat.tot),n_sess))
      } else {
        X_list <- X_list[[1]] #single-session case
        Amat.final <- Amat.tot
      }
      Xmat <- X_list #%*% Amat.final #already done within BayesGLM
      Xcros.all[[nn]] <- Matrix::crossprod(Xmat)
      Xycros.all[[nn]] <- Matrix::crossprod(Xmat, y_vec)
    }
    rm(results_mm, y_vec, X_list, Xmat) # save memory

    mu_theta <- solve(Q_theta, Qmu_theta) #mu_theta = poterior mean of q(theta|y) (Normal approximation) from paper, Q_theta = posterior precision
    #### DRAW SAMPLES FROM q(theta|y)
    #theta.tmp <- mvrnorm(nsamp_theta, mu_theta, solve(Q_theta))
    if (verbose>0) cat(paste0('Sampling ',nsamp_theta,' posterior samples of thetas \n'))
    theta.samp <- INLA::inla.qsample(n=nsamp_theta, Q = Q_theta, mu = mu_theta)
    #### COMPUTE WEIGHT OF EACH SAMPLES FROM q(theta|y) BASED ON PRIOR
    if (verbose>0) cat('Computing weights for each theta sample \n')
    logwt <- rep(NA, nsamp_theta)
    for (tt in seq(nsamp_theta)) {
      logwt[tt] <- F.logwt(theta.samp[,tt], spde, mu_theta, Q_theta, nN)
    }
    #weights to apply to each posterior sample of theta
    wt.tmp <- exp(logwt - max(logwt))
    wt <- wt.tmp/(sum(wt.tmp))

    # # Above, but trying to not use INLA.
    # # theta.samp <- qsample(n=nsamp_theta, Q = Q_theta, mu = mu_theta) # ?
    # mu_theta <- mu_theta / nN
    # theta.samp <- as.matrix(mu_theta)
    # wt <- 1

    #get posterior quantities of beta, conditional on a value of theta
    if (verbose>0) cat(paste0('Sampling ',nsamp_beta,' betas for each value of theta \n'))
    if (is.null(num_cores)) {
      #6 minutes in simuation
      beta.posteriors <- apply(
        theta.samp,
        MARGIN = 2,
        FUN = beta.posterior.thetasamp,
        spde = spde,
        Xcros = Xcros.all,
        Xycros = Xycros.all,
        contrasts = contrasts,
        quantiles = quantiles,
        excursion_type = excursion_type,
        gamma = gamma,
        alpha = alpha,
        nsamp_beta = nsamp_beta
      )
    } else {
      if (!requireNamespace("parallel", quietly = TRUE)) {
        stop(
          "`BayesGLM2` requires the `parallel` package. Please install it.",
          call. = FALSE
        )
      }

      #2 minutes in simulation (4 cores)
      max_num_cores <- min(parallel::detectCores() - 1, 25)
      num_cores <- min(max_num_cores, num_cores)
      cl <- parallel::makeCluster(num_cores)

      if (verbose>0) cat(paste0('\t ... running in parallel with ',num_cores,' cores \n'))

      beta.posteriors <- parallel::parApply(
        cl, theta.samp,
        MARGIN=2,
        FUN=beta.posterior.thetasamp,
        spde=spde,
        Xcros = Xcros.all,
        Xycros = Xycros.all,
        contrasts=contrasts,
        quantiles=quantiles,
        excursion_type=excursion_type,
        gamma=gamma,
        alpha=alpha,
        nsamp_beta=nsamp_beta
      )
      parallel::stopCluster(cl)
    }

    ## Sum over samples using weights

    if (verbose>0) cat('Computing weighted summaries over beta samples \n')

    ## Posterior mean of each contrast
    betas.all <- lapply(beta.posteriors, function(x) return(x$mu))
    betas.wt <- mapply(
      function(x, a){return(x*a)},
      betas.all, wt, SIMPLIFY=FALSE
    ) #apply weight to each element of betas.all (one for each theta sample)
    betas.summ <- apply(abind::abind(betas.wt, along=3), MARGIN = c(1,2), sum)  #N x L (# of contrasts)
    dimnames(betas.summ) <- NULL

    ## Posterior quantiles of each contrast
    num_quantiles <- length(quantiles)
    if(num_quantiles > 0){
      quantiles.summ <- vector('list', num_quantiles)
      names(quantiles.summ) <- quantiles
      for(iq in 1:num_quantiles){
        quantiles.all_iq <- lapply(beta.posteriors, function(x) return(x$quantiles[[iq]]))
        betas.wt_iq <- mapply(function(x, a){return(x*a)}, quantiles.all_iq, wt, SIMPLIFY=FALSE) #apply weight to each element of quantiles.all_iq (one for each theta sample)
        quantiles.summ[[iq]] <- apply(abind::abind(betas.wt_iq, along=3), MARGIN = c(1,2), sum)  #N x L (# of contrasts)
        dimnames(quantiles.summ[[iq]]) <- NULL
      }
    } else {
      quantiles.summ <- NULL
    }

    ## Posterior probabilities and activations
    if(do_excur){
      ppm.all <- lapply(beta.posteriors, function(x) return(x$F))
      ppm.wt <- mapply(function(x, a){return(x*a)}, ppm.all, wt, SIMPLIFY=FALSE) #apply weight to each element of ppm.all (one for each theta sample)
      ppm.summ <- apply(abind::abind(ppm.wt, along=3), MARGIN = c(1,2), sum) #N x L (# of contrasts)
      dimnames(ppm.summ) <- NULL
      active <- array(0, dim=dim(ppm.summ))
      for (cc in seq(nC)) { active[ppm.summ[,cc] > (1-alpha[cc]),cc] <- 1 }
    } else {
      ppm.summ <- active <- NULL
    }

    ### Save results
    out[[mm]] <- list(
      estimates = betas.summ,
      quantiles = quantiles.summ,
      ppm = ppm.summ,
      active = active,
      mask = Mask,
      Amat = Amat # not Amat.final?
    )

    if (nM>1) { cat("\n") }
  }

  out <- list(
    model_results = out,
    contrasts = contrasts,
    excursion_type = excursion_type,
    field_names=field_names,
    session_names=session_names,
    gamma = gamma,
    alpha = alpha,
    nsamp_theta = nsamp_theta,
    nsamp_beta = nsamp_beta
  )
  class(out) <- "fit_bglm2"

  if (is_cifti) {
    out <- list(
      contrast_estimate_xii = as.xifti(
        out$model_results$cortexL$estimates,
        out$model_results$cortexL$mask,
        out$model_results$cortexR$estimates,
        out$model_results$cortexR$mask
      ),
      activations_xii = NULL,
      BayesGLM2_results = out
    )
    out$contrast_estimate_xii$meta$cifti$names <- names(contrasts)
    if (do_excur) {
      act_xii <- as.xifti(
        out$BayesGLM2_results$model_results$cortexL$active,
        out$BayesGLM2_results$model_results$cortexL$mask,
        out$BayesGLM2_results$model_results$cortexR$active,
        out$BayesGLM2_results$model_results$cortexR$mask
      )
      out$activations_xii <- convert_xifti(act_xii, "dlabel", colors='red')
      out$activations_xii$meta$cifti$names <- names(contrasts)
      names(out$activations_xii$meta$cifti$labels) <- names(contrasts)
    }
    class(out) <- "BGLM2"
  }

  out
}

#' @rdname BayesGLM2
#' @export
BayesGLM_group <- function(
  results,
  contrasts = NULL,
  quantiles = NULL,
  excursion_type=NULL,
  gamma = 0,
  alpha = 0.05,
  nsamp_theta = 50,
  nsamp_beta = 100,
  num_cores = NULL,
  verbose = 1){

  BayesGLM2(
    results=results,
    contrasts=contrasts,
    quantiles=quantiles,
    excursion_type=excursion_type,
    gamma=gamma, alpha=alpha,
    nsamp_theta=nsamp_theta, nsamp_beta=nsamp_beta,
    num_cores=num_cores, verbose=verbose
  )
}
