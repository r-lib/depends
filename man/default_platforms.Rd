% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/platform.R
\name{current_r_platform}
\alias{current_r_platform}
\alias{default_platforms}
\title{The current R platform for packages}
\usage{
current_r_platform()

default_platforms()
}
\value{
\code{current_r_platform()} returns a string:
\code{source}, \code{macos} or \code{windows}.

\code{default_platforms()} return a character vector of package types that
work on the current system. It is a subset of the possible
\code{current_r_platform()} return values.
}
\description{
\code{current_r_platform()} detects the current platform.
\code{default_platforms()} prints the default package types that are used
on the current platform. See also \link[=pkg_config]{'Configuration'}.
}
\examples{
current_r_platform()
default_platforms()
}
\concept{platform functions}
