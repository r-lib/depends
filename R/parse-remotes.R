
#' Package references
#'
#' @description
#' A package reference (ref) specifies a location from which an R package
#' can be obtained from. The full syntax of a reference is `type::ref`, but
#' `type` can be often omitted, the common ref types have shortcuts.
#'
#' @includeRmd tools/doc/pkg-refs.Rmd
#' @name pkg_refs
NULL

package_name_rx <- function() "[a-zA-Z][a-zA-Z0-9.]*[a-zA-Z0-9]"

## CRAN and GitHub are special, because they have shorthands,
## so we need to know their regexes to find the type of the remotes

standard_rx <- function(remote_name = "standard") {
  paste0(
    "^",
    ## Optional remote type
    "(?:", remote_name, "::)?",
    ## Package name, only valid names
    "(?<package>", package_name_rx(), ")",
    ## Package version, only valid version numbers
    "(?:@(?:(?:(?<atleast>>=)?",
    "(?<version>[0-9]+[-\\.][0-9]+(?:[-\\.][0-9]+)*|current|last))))?",
    "$"
  )
}

#' Match a GitHub username
#'
#' * may only contain alphanumeric characters or hyphens
#' * cannot have multiple consecutive hyphens
#' * cannot begin or end with a hyphen
#' * maximum 39 characters
#'
#' Based on <https://github.com/shinnn/github-username-regex>
#'
#' @noRd

github_username_rx <- function() {
  "(?<username>(?:[a-zA-Z\\d](?:[a-zA-Z\\d-]){0,38}))"
}

github_repo_rx <- function() "(?<repo>[^/@#]+)"
github_subdir_rx <- function() "(?:/(?<subdir>(?:[^@#]*[^@#/])/?))"
github_commitish_rx <- function() "(?:@(?<commitish>[^*].*))"
github_pull_rx <- function() "(?:#(?<pull>[0-9]+))"
github_release_rx <- function() "(?:@(?<release>[*]release))"
github_detail_rx <- function() {
  sprintf(
    "(?:(?:%s)|(?:%s)|(?:%s))?",
    github_commitish_rx(),
    github_pull_rx(),
    github_release_rx()
  )
}

github_rx <- function() {
  paste0(
    "^",
    ## Optional package name
    "(?:(?<package>", package_name_rx(), ")=)?",
    ## Optional remote type
    "(?:github::)?",
    github_username_rx(), "/",
    github_repo_rx(),
    github_subdir_rx(), "?",
    ## Commit / PR / Release
    github_detail_rx(),
    "$"
  )
}

github_url_commitish_rx <- function() {
  "(?:(?:tree|commit|releases/tag)/(?<commitish>.+$))"
}

github_url_pull_rx <- function() "(?:pull/(?<pull>.+$))"

github_url_release_rx <- function() "(?:releases/)(?<release>.+$)"

github_url_detail_rx <- function() {
  glue("(?:/(?:",
       "{github_url_commitish_rx()}",
       "|{github_url_pull_rx()}",
       "|{github_url_release_rx()}",
       "))?")
}

## We need to select the shortest match here, to avoid matching a
## a .git suffix

github_url_repo_rx <- function() "(?<repo>[^/@#]+?)"

github_url_rx <- function() {
  paste0(
    "^",
    ## Optional package name
    "(?:(?<package>", package_name_rx(), ")=)?",
    ## Optional remote type
    "(?:github::)?",
    ## Optional protocol
    "(?:(?:https?://)|(?:ssh://(?:[^@]+@)?)?)",
    ## Servername
    "(?:[^/:]+)[/:]",
    ## Username
    github_username_rx(), "/",
    ## Repo
    github_url_repo_rx(),
    ## subdir, always empty
    "(?<subdir>)",
    ## Optional Extension
    "(?:[.]git)?",
    ## Commit / PR / Release
    github_url_detail_rx(),
    "$"
  )
}

remote_type_rx <- function() {
  paste0(
    "^",
    ## Optional package name
    "(?:(?<package>", package_name_rx(), ")=)?",
    ## Remote type
    "(?:(?<type>[-_[:alnum:]]+)::)?",
    ## Rest of ref
    "(?<rest>.*)$"
  )
}

local_rx <- function() {
  typed <- "local::(?<path>.*)"
  sugar <- "(?<path>(?:/|\\\\|~|[.]/|[.]\\\\|[.]$).*)"
  paste0(
    "^",
    "(?|", typed, "|", sugar, ")",
    "$"
  )
}

#' @importFrom rematch2 re_match

type_default_parse <- function(refs, ...) {
  m <- re_match(refs, remote_type_rx())
  lapply_rows(m, function(x)
    list(package = x$package, type = x$type, rest = x$rest, ref = x$.text)
  )
}

get_remote_types <- function(refs) {
  m <- re_match(refs, remote_type_rx())
  types <- m$type

  types[types == "" & grepl(standard_rx(), refs, perl = TRUE)] <- "standard"
  types[types == "" & grepl(github_rx(), refs, perl = TRUE)] <- "github"
  types[types == "" & grepl(github_url_rx(), refs, perl = TRUE)] <- "github"
  types[types == "" & grepl(local_rx(), refs, perl = TRUE)] <- "local"

  if (any(bad <- types == "")) {
    stop("Can't parse remotes: ", paste(refs[bad], collapse = ", "))
  }

  types
}

#' Parse package location references
#'
#' See [pkg_refs] for more about supported package references.
#'
#' @param refs Character vector of references.
#' @param remote_types Custom remote types can be added here, this is
#'   for advanced use, and experimental currently.
#' @param ... Additional arguments are passed to the individual parser
#'   functions.
#' @return `parse_pkg_refs()` returns a list of parsed references.
#' `parse_pkg_ref()` returns one parsed reference. A parsed reference is
#' a list, with at least elements:
#' - `ref`: The original reference string.
#' - `type`: The reference type.
#' - `package`: The package name.
#' It typically contains additional data, specific to the various
#' reference types. See [pkg_refs] for details.
#' The parsed reference always has class `remote_ref_<type>` and
#' `remote_ref`.
#'
#' @export

parse_pkg_refs <- function(refs, remote_types = NULL, ...) {
  remote_types <- c(default_remote_types(), remote_types)
  params <- parse_ref_params(refs)
  refs <- params$refs
  types <- get_remote_types(refs)
  unique_types <- unique(types)
  res <- vector("list", length(refs))

  if (length(bad <- setdiff(unique_types, names(remote_types)))) {
    stop("Unknown remote type(s): ", format_items(bad))
  }

  for (this in unique_types) {
    parser <- remote_types[[this]]$parse %||% type_default_parse
    this_refs <- refs[types == this]
    new_remotes <- parser(this_refs, ...)
    new_remotes <- lapply(new_remotes, function(x) { x$type <- this; x })
    new_remotes <- lapply(
      new_remotes,
      add_class,
      c(paste0("remote_ref_", this), "remote_ref")
    )
    res[types == this] <- new_remotes
  }

  add_ref_params(res, params$params)
}

#' @param ref A package reference, like `refs`, but a length one vector,
#' for convenience.
#' @export
#' @rdname parse_pkg_refs

parse_pkg_ref <- function(ref, remote_types = NULL, ...) {
  assert_that(is_string(ref))
  parse_pkg_refs(ref, remote_types = remote_types, ...)[[1]]
}

parse_ref_params <- function(refs) {
  list(
    refs = sub("[?].*$", "", refs),
    params = lapply(sub("^[^?]*(\\?|$)", "", refs), parse_query)
  )
}

add_ref_params <- function(res, params) {
  if (length(res) != length(params)) {
    stop("Internal error, param length mismath")
  }
  for (i in seq_along(res)) {
    res[[i]]$params <- if (length(params[[i]])) params[[i]] else character()
  }

  res
}

known_query_params <- c("source", "reinstall", "nocache")

parse_query <- function(query) {
  query <- sub("^[?]", "", query)
  query <- chartr("+", " ", query)
  argstr <- strsplit(query, "&", fixed = TRUE)[[1]]
  argstr <- strsplit(argstr, "=", fixed = TRUE)
  keys <- vcapply(argstr, function(x) utils::URLdecode(x[[1]]))
  vals <- vcapply(argstr, function(x) {
    if (length(x) == 2) utils::URLdecode(x[[2]]) else ""
  })

  if (length(bad <- unique(setdiff(keys, known_query_params)))) {
    cli_alert_warning("Unknown package parameter{?s}: {.val {bad}}.")
  }

  structure(vals, names = keys)
}

is_true_param <- function(params, which) {
  which %in% names(params) &&
    tolower(params[[which]]) %in% c("", "true", "yes", "y", "on", "1")
}
