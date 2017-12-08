# Copyright 2017 Google Inc. All rights reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

""" Rules that create an output script to install packages via apt-get."""

CACHE_DIR = "/tmp/install"

ARCHIVE_DIR = "."

load(
    "//package_managers:package_manager_provider.bzl",
    "package_manager_provider",
)
load(
    "@io_bazel_rules_docker//skylib:filetype.bzl",
    tar_filetype = "tar",
)

def _generate_download_commands(ctx):
    commands = []
    # Fetch Index
    commands.append('apt-get update -y')
    # Make partial dir
    commands.append('mkdir -p {0}/{1}/partial'.format(CACHE_DIR, ARCHIVE_DIR))
    install_command = ('apt-get install --no-install-recommends -y -q -o ' +
                       'Dir::Cache="{0}" -o Dir::Cache::archives="{1}" {2} ' +
                       '--download-only'
                      ).format(
                          CACHE_DIR,
                          ARCHIVE_DIR,
                          ' '.join(ctx.attr.packages)
                      )
    # Install command
    commands.append(install_command)
    # Tar command to only include all the *.deb files and ignore other
    # directories placed in the cache dir.
    tar_command = ('tar -cpf {output}.tar --directory {cache}/{archive} ' +
                   '`cd {cache}/{archive} && ls *.deb`'
                  ).format(
                      output=ctx.attr.name,
                      cache=CACHE_DIR,
                      archive=ARCHIVE_DIR
                  )
    commands.append(tar_command)
    return commands

def _generate_install_commands(ctx, tar):
    commands = []
    commands.append('tar -xvf {output}'.format(output=tar))
    commands.append('dpkg -i ./*.deb')
    commands.append('apt-get install -f')
    return commands

def _impl(ctx):
    if not ctx.attr.packages and not ctx.attr.tar:
      fail("Cannot install packages. \nEither a list of packages or a tar " +
           "with debs should be provided")
    elif ctx.attr.packages and ctx.attr.tar:
      fail("Cannot specify both list of packages and a tar with debs")
    shell_file_contents = []
    # Shell file commands
    shell_file_contents.append('#!/bin/bash')
    shell_file_contents.append('set -x')

    download_commands = _generate_download_commands(ctx) if ctx.attr.packages else []
    tar_name = "{0}.tar".format(ctx.attr.name) if ctx.attr.packages else "{0}".format(ctx.file.tar.short_path)
    install_commands = _generate_install_commands(ctx, tar_name)

    apt_get = package_manager_provider(
        download_commands = download_commands,
        install_commands = install_commands,
    )

    shell_file_contents.append(' && '.join(download_commands))
    shell_file_contents.append(' && '.join(install_commands))

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = '\n'.join(shell_file_contents),
    )

    runfiles = ctx.runfiles(files=[])
    if ctx.attr.tar:
      runfiles = ctx.runfiles(files=ctx.attr.tar.files.to_list())
    return struct(
        files = depset([ctx.outputs.executable]),
        runfiles = runfiles,
        package_manager_provider = apt_get,
        providers = [apt_get],
    )

generate_apt_get = rule(
    attrs = {
        "packages": attr.string_list(
            doc = "list of packages to download",
            mandatory = False,
        ),
        "tar": attr.label(
            doc = "tar with package debs to install",
            mandatory = False,
            allow_files = tar_filetype,
            single_file = True,
        ),
    },
    executable = True,
    implementation = _impl,
)

"""Fetches and Installs packages via apt-get or bundled debs.

This rule fetches and installs packages via apt-get or tar with debs.

Args:
  packages: List of packages to fetch and install.
  tar: Tar with package deb bundled.
"""
