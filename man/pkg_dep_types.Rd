% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dep-utils.R
\name{pkg_dep_types_hard}
\alias{pkg_dep_types_hard}
\alias{pkg_dep_types_soft}
\alias{pkg_dep_types}
\title{Possible package dependency types}
\usage{
pkg_dep_types_hard()

pkg_dep_types_soft()

pkg_dep_types()
}
\value{
A string vector of dependency types, capitalized.
}
\description{
Hard dependencies are needed for a package to load, soft dependencies
are optional.
}
\seealso{
Other package dependency utilities: 
\code{\link{as_pkg_dependencies}()}
}
\concept{package dependency utilities}
