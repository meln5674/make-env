# MakeEnv

MakeEnv is a tool to generate Makefiles and Dockerfiles for building reproducible dev/build/test enviroments from a parseable, scriptable configuration file.

## Concept

MakeEnv is controlled by a single configuration file, in JSON or YAML format. This file contains a set of executables that are to be installed, variables about
those executables, such as versions, repositories, mirrors, and URLs, and instructions on how to download, extract, and/or install them to an isolated directory
specific to the project in question.

This file is then used to generate a Makefile which contains targets to perform these actions, using variables that can be referenced by other Makefiles in order
to execute them as part of an existing build process, as well as a Dockerfile which installs the same set of tools.

## Configuration Format

```yaml
vars:
  <global_name>: <value>
tools:
  <tool_name>:
    <install_type>:
      <install_parameter_name>: <values>
      ...
    variables:
      <variable_name>: <default_value>
    dependsOn:
    - <extra_target>
    ...
sets:
  <set_name>:
  - <tool_name>
  - <other_dependency>
  ...
output_name: <output_makefile_filename>
```

Each "tool" represents an executable to be installed, and "type" indicates how it is installed, with a set of "parameters" to configure that installation, based on the types.
Each tool will generate two targets, one which is a variable containing the absolute path of the executable, which installs it to that location,
and the other is the name of the tool itself, which is a phony target with a dependency on the "real" target. The variable name will be the tool name converted to
SCREAMING\_SNAKE\_CASE.

Additionally, each tool can specify a set of variables, which each generate a matching Makefile variable, prefixed with the tool's variable name and an underscore., and can be referenced from the parameters of the tool type.

Because tools are Makefile targets, they can declare arbitrary extra dependencies, including on other tools installed by MakeEnv.

Tools can be grouped into "sets" to generate phony targets which install a set of tools by include their "real" targets as dependencies.

The above example would generate the following makefile:

```Makefile
LOCALBIN ?= $(shell pwd)/bin

TOOL_VARIABLE_NAME ?= <default_value>
TOOL_NAME ?= $(LOCALBIN)/name:
	<commands to install tool>
.PHONY: tool_name
tool_name: $(TOOL_NAME)

.PHONY: set_name
set_name: $(TOOL_NAME)
```

## Supported Install Types.

### Provided

Provided tools are not installed, but instead, expected to be provided by the user. Provided tools still provide a single variable which can then be
used in targets so that instances of this tool can be globally overridden, and targets can explicitly declare a dependency on that tool. The target
generated for such a tool simply confirms it exists, and if the value is a relative path, ensures it is on the $PATH.

This is intended to provide the same experience as many older hand-written Makefiles which provide a $(CC) variable to configure the C compiler used.

```yaml
example:
  provided:
    # An optional default, can either be an absolute path or a command name to be searched on the $PATH
    default: example-tool-name 
```

```Makefile
EXAMPLE ?= $(shell which example-tool-name)
$(EXAMPLE):
    stat $(EXAMPLE) >/dev/null
```

MakeEnv provides a set of "built-in" provided tools, one for each command it uses in the generated makefile targets for other tools types.

### HTTP

The "http" type is for executables that are downloaded from an HTTP(s) URL, and then optionally extracted from an archive, such as a tar or zip file.
These operations are performed using native code.
The "curl" command is expected to be either on the PATH or specified with an absolute path. The same applies to "tar" and "zip", if they are to be used.
Archives from "zip" will generate an additional target, suffixed with \_ZIP, as zip files cannot be extracted from a stream.

```yaml
example:
  http:
    # Required, The URL containing the binary or archive
    url: '{{ .Vars.mirror }}/example-{{ .Vars.version }}'
    # If the binary is within a tar archive
    tar:
       # Optional, location within the archive, defaults to the tool name at the root of the archive.
       path: path/in/tar/example
       # Optional compression of the archive, one of none, gzip, bzip, defaults to none
       compression: none
    # If the binary is within a zip archive
    zip:
       # Required, location within the archive
       path: path/in/zip/example
  # Variable can be used to configure the URL
  variables:
    mirror: https://example.com
    version: 1.2.3
```


```Makefile
EXAMPLE_MIRROR ?= https://example.com
EXAMPLE_VERSION ?= 1.2.3
EXAMPLE_URL ?= $(EXAMPLE_MIRROR)/example-$(EXAMPLE_VERSION)
# Only if zip archive 
EXAMPLE_ZIP ?= $(LOCALBIN)example.zip:
$(EXAMPLE_ZIP)
	curl -vfL $(EXAMPLE_URL) -o $(EXAMPLE_ZIP)
EXAMPLE ?= $(LOCALBIN)/example:
$(EXAMPLE):
	# If no archive
	curl -vfL $(EXAMPLE_URL) -o $(EXAMPLE)
	# If zip archive
	unzip $(EXAMPLE_ZIP) -d $(LOCALBIN) --no-dir-entries path/in/zip/example
	# If curl archive
	curl -vfL $(EXAMPLE_URL) | tar x -C $(LOCAL_BIN) --strip-components=3 path/in/tar/example
example: $(EXAMPLE)
```

### Go

The "go" type is for executables built from golang modules, installed using the "go install" command. Each project maintains its own GOBIN directory, and optionally its own GOPATH.
The "go" command is expected to be either on the PATH or specified with an absolute path.

```yaml
example:
  go:
    # All fields can reference variables using the {{ }} syntax
    # Required, the module to install
    module: example.com/example/module
    # Optional, the subdirectory within the module containing the main package
    subpath: command
    # Required, the version of the module, as found in go.mod
    version: {{ .Vars.version }}
    # Optional, environment varibles to provide to the go install command
    env:
        CGO_ENABLED: 0
    # Optional, flags to provide to the go install command
    flags: [-tags, netgo, -ldflags, '-w -extldflags "-static"']
  variables:
    version: v1.2.3
```

### S3

The "s3" type is for executables that are downloaded from an S3 (or compatible) bucket. This offers the same archive extracting options as "http".
The "aws-cli" command is expected to be either on the PATH, or specified with an absolute path, as are tar, zip, etc, if they are to be used.

NOT YET IMPLEMENTED

### PipX

The "pipx" type is for executables installed using pipx. Each project will maintain its own set of virtual envs and installed packages.
The "pipx" command is expected ot be either on the PATH or specified with an absolute path.

NOT YET IMPLEMENTED

### Maven

The "maven" type is for java JAR files which are installed, along with their dependencies, using maven.
The "maven" command is expected to be either on the PATH or specified with an absolute path.

NOT YET IMPLEMENTED
