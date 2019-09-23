
pkg_plan <- R6::R6Class(
  "pkg_plan",
  public = list(
    initialize = function(refs, config = list(), library = NULL,
                          remote_types = NULL)
      pkgplan_init(self, private, refs, config, library, remote_types),

    get_refs = function() private$refs,
    has_resolution = function() !is.null(private$resolution$result),
    has_clean_resolution = function()
      has_resolution() && (all(private$resolution$result$status == "OK")),
    has_resolution_downloads = function() !is.null(private$downloads),
    has_solution_downloads = function() !is.null(private$solution_downloads),
    has_solution = function() !is.null(private$solution),
    get_config = function() private$config,

    async_resolve = function()
      pkgplan_async_resolve(self, private),
    resolve = function()
      pkgplan_resolve(self, private),
    get_resolution = function()
      pkgplan_get_resolution(self, private),

    async_download_resolution = function()
      pkgplan_async_download_resolution(self, private),
    download_resolution = function()
      pkgplan_download_resolution(self, private),
    get_resolution_download = function()
      pkgplan_get_resolution_download(self, private),
    
    solve = function(policy = c("lazy", "upgrade"))
      pkgplan_solve(self, private, match.arg(policy)),
    delete_solution = function()
      private$solution <- NULL,
    stop_for_solve_error = function()
      pkgplan_stop_for_solve_error(self, private),
    get_solution = function()
      pkgplan_get_solution(self, private),
    get_install_plan = function()
      pkgplan_install_plan(self, private, downloads = TRUE),
    export_install_plan = function(plan_file = stdout())
      pkgplan_export_install_plan(self, private, plan_file),
    draw_solution_tree = function(pkgs = NULL, types = NULL)
      pkgplan_draw_solution_tree(self, private, pkgs, types),

    async_download_solution = function()
      pkgplan_async_download_solution(self, private),
    download_solution = function()
      pkgplan_download_solution(self, private),
    get_solution_download = function()
      pkgplan_get_solution_download(self, private),
    stop_for_solution_download_error = function()
      pkgplan_stop_for_solution_download_error(self, private),

    print = function(...)
      pkgplan_print(self, private, ...)
  ),

  private = list(
    refs = NULL,
    dirty = FALSE,
    remotes = list(),
    cache = NULL,
    resolution = NULL,
    solution = NULL,
    downloads = NULL,
    solution_downloads = NULL,
    download_cache = NULL,
    config = NULL,
    progress_bar = NULL,
    progress_bar_timer = NULL,
    remote_types = NULL,

    download_res = function(res, which, on_progress = NULL)
      pkgplan_download_res(self, private, res, which, on_progress),
    subset_resolution = function(which)
      pkgplan__subset_resolution(self, private, which),
    create_lp_problem = function(pkgs, policy)
      pkgplan__create_lp_problem(self, private, pkgs, policy),
    solve_lp_problem = function(problem)
      pkgplan__solve_lp_problem(self, private, problem),

    create_progress_bar = function(what)
      pkgplan__create_progress_bar(self, private, what),
    update_progress_bar = function(idx, data)
      pkgplan__update_progress_bar(self, private, idx, data),
    show_progress_bar = function()
      pkgplan__show_progress_bar(self, private),
    done_progress_bar = function()
      pkgplan__done_progress_bar(self, private)
  )
)

#' @importFrom utils modifyList

pkgplan_init <- function(self, private, refs, config, library,
                         remote_types) {

  assert_that(is_character(refs),
              is_valid_config(config),
              is_path_or_null(library))

  private$refs <- refs
  private$remotes <- parse_pkg_refs(refs)
  private$config <- modifyList(pkgplan_default_config(), config)
  private$config$library <- library
  private$remote_types <- remote_types %||% default_remote_types()

  if (!is.null(library)) {
    mkdirp(library, msg = "Creating library directory")
    library <- normalizePath(library)
  }
  mkdirp(private$download_cache <- private$config$cache_dir)

  private$cache <- list(
    metadata = pkgcache::cranlike_metadata_cache$new(
      replica_path = private$config$metadata_cache_dir,
      platforms = private$config$platforms,
      r_version = private$config$`r-version`,
      cran_mirror = private$config$`cran-mirror`),
    package = pkgcache::package_cache$new(private$config$package_cache_dir),
    installed = if (!is.null(library)) make_installed_cache(library)
  )

  private$dirty <- TRUE
  invisible(self)
}

pkgplan_default_config <- function() {
  structure(list(
    "library"            = NULL,
    "cache_dir"          = detect_download_cache_dir(),
    "package_cache_dir"  = NULL,
    "metadata_cache_dir" = tempfile(),
    "platforms"          = default_platforms(),
    "cran-mirror"        = default_cran_mirror(),
    "dependencies"       = pkg_dep_types_hard(),
    "r-versions"         = current_r_version()
  ), class = "pkg_config")
}

#' @export

format.pkg_config <- function(x, ...) {

  format_dependencies <- function(dep) {
    dep <- as_pkg_dependencies(dep)
    paste0("direct: ", paste(dep$direct, collapse = ", "),
           ", indirect: ", paste(dep$indirect, collapse = ", "))
  }

  c("+ config:",
    paste0("  - library: ", x$library),
    paste0("  - cache_dir: ", x$cache_dir),
    paste0("  - package_cache_dir: ", x$package_cache_dir %||% "<default>"),
    paste0("  - metadata_cache_dir: ", x$metadata_cache_dir),
    paste0("  - platforms: ", paste(x$platforms, collapse = ", ")),
    paste0("  - cran-mirror: ", x$`cran-mirror`),
    paste0("  - dependencies: ", format_dependencies(x$dependencies)),
    paste0("  - r-versions: ", paste(x$`r-versions`, collapse = ", "))
    )
}

#' @export

print.pkg_config <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
}

is_valid_config <- function(x) {
  assert_that(is.list(x), all_named(x))
  assert_that(all(names(x) %in% names(pkgplan_default_config())))
  for (n in names(x)) {
    switch (
      n,
      library            = assert_that(is_path(x[[n]])),
      cache_dir          = assert_that(is_path(x[[n]])),
      package_cache_dir  = assert_that(is_path(x[[n]])),
      metadata_cache_dir = assert_that(is_path(x[[n]])),
      platforms          = assert_that(is_platform_list(x[[n]])),
      "cran-mirror"      = assert_that(is_string(x[[n]])),
      dependencies       = assert_that(is_dependencies(x[[n]])),
      "r-versions"       = assert_that(is_r_version_list(x[[n]]))
    )
  }
  TRUE
}

on_failure(is_valid_config) <- function(call, env) {
  paste0(deparse(call$x), " is not a valid configuration list")
}

pkgplan_get_total_files <- function(self, private) {
  nrow(private$resolution$result)
}

pkgplan_print <- function(self, private, ...) {
  cat("<pkg_plan>\n")

  ## refs
  refs <- self$get_refs()
  cat(
    strwrap(
      paste0("- refs: ", paste(backtick(refs), collapse = ", ")),
      indent = 0, exdent = 4
    ),
    sep = "\n"
  )

  ## library
  if (!is.null(private$config$library)) {
    cat("- library:", backtick(private$config$library), "\n")
  }

  ## resolution
  if (self$has_resolution()) {
    if (self$has_clean_resolution()) {
      cat("- has resolution\n")
    } else {
      cat("- has resolution, with errors\n")
    }
  }

  ## solution
  if (!is.null(private$solution$result)) {
    if (private$solution$result$status == "OK") {
      cat("- has solution\n")
    } else {
      cat("- has solution, with errors\n")
    }
  }

  invisible(self)
}