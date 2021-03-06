
## ------------------------------------------------------------------------
## API

parse_remote_standard <- function(specs, config, ...) {

  ## This is the same as CRAN, but possibly with standard::
  parsed_specs <- re_match(specs, standard_rx())
  parsed_specs$ref <- parsed_specs$.text
  cn <- setdiff(colnames(parsed_specs), c(".match", ".text"))
  parsed_specs <- parsed_specs[, cn]
  parsed_specs$type <- "standard"
  lapply(
    seq_len(nrow(parsed_specs)),
    function(i) as.list(parsed_specs[i,])
  )
}

resolve_remote_standard <- function(remote, direct, config,
                                    cache, dependencies, ...) {
  force(remote); force(direct); force(dependencies)
  versions <- if ("type" %in% names(remote)) {
    remote$version
  } else  {
    vcapply(remote, "[[", "version")
  }

  if (all(versions %in% c("", "current"))) {
    resolve_from_metadata(remote, direct, config, cache, dependencies)
  } else {
    type_cran_resolve_version(remote, direct, config, cache, dependencies)
  }
}

download_remote_standard <- function(resolution, target, target_tree,
                                     config, cache, which, on_progress) {

  # This is slightly different for cran and bioc packages.
  rptp <- resolution$repotype
  if (identical(rptp, "cran")) {
    download_remote_cran(resolution, target, target_tree, config, cache,
                         which, on_progress)
  } else if (identical(rptp, "bioc")) {
    download_remote_bioc(resolution, target, target_tree, config, cache,
                         which, on_progress)
  } else {
    # this will always ping in practice, because we only have a sha in
    # the metadata for CRAN currently
    download_ping_if_no_sha(resolution, target, config, cache,
                            on_progress)
  }
}

satisfy_remote_standard <- function(resolution, candidate, config, ...) {

  ## A standard ref is special, in that any ref source can satisfy it,
  ## as long as the package name is the same, and the version
  ## requirements are satisfied.

  ## 1. package name must be the same
  if (resolution$package != candidate$package) {
    return(structure(FALSE, reason = "Package names differ"))
  }

  ## 2. if this is a direct ref, then it has to be a CRAN or
  ## bioc package. If the candidate is an installed package, we
  ## need to check where it was installed from.
  ## Also, an installed package is only accepted if it is not older,
  ## for direct refs.
  if (resolution$direct) {
    if (candidate$type == "installed") {
      type <- candidate$extra[[1]][["repotype"]] %||% "unknown"
      if (is.na(type)) type <- "unknown"
      remotetype <- candidate$extra[[1]][["remotetype"]] %||% "unknown"
      if (is.na(remotetype)) remotetype <- "unknown"
    } else {
      type <- candidate$type
      remotetype <- "unknown"
    }
    if (!type %in% c("cran", "bioc", "standard") && remotetype != "standard") {
      return(structure(FALSE, reason = "User requested CRAN package"))
    }
    if (candidate$type == "installed" &&
        package_version(resolution$version) > candidate$version) {
      return(structure(FALSE, reason = "Direct ref needs update"))
    }
  }

  ## 3. version requirements must be satisfied
  version <- tryCatch(resolution$remote[[1]]$version, error = function(e) "")
  if (version == "") return(TRUE)

  if (!version_satisfies(
         candidate$version,
         resolution$remote[[1]]$atleast,
         version)) {
    return(structure(FALSE, reason = "Insufficient version"))
  }

  TRUE
}
