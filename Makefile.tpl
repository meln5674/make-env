{{/*
To generate the Makefile:

1. Create a variable for each global var
2. Create a provided-type tool for each of the built-in necessary tools (curl, go, etc)
3. For each tool:
    1. Create a variable prefixed with the tool name for each tool-specific var
    2. For HTTP tools, create a variable for the url. If the tool is within a zip, create a variable for the download location.
    3. Create a variable for the tool which points to its name in the local bin directory
    4. Create a target with that variable's value as the name, which performs the download into a hidden directory in a way that is unique for the given configuration,
        e.g. the http url, or the go module/path/version, so that changing this results in a new download, and then create a symlink to it in the local
        bin directory, ensuring to re-create it so that updates point to the new tool.
    5. Create a phony target that is the same as the tools name which does nothing but depends on the target named by the variable in step 3
4. For each tool set, create a phony target that does nothing
    1. For each item in the toolset that is a tool name, add a dependency that is the value of the variable for that tool from step 3.3
    2. For each item in the toolset that is not a tool name, add a dependency on that verbatim name
5. Add a target for the generate Makefile that uses the input and output files supplied on the command line
*/}}

{{- define "make-env.path-to-command" -}}
$(shell command -v {{ . }})
{{- end -}}

{{- define "make-env.provided-tool" -}}
{{ .toolVarName }} ?= {{ include "make-env.path-to-command" .toolCfg.Provided.Default }}
{{ .toolVarRef }}: {{ .toolCfg.DependsOn | join " " }}
	stat {{ .toolVarRef }} >/dev/null
{{- end -}}

{{- define "make-env.http-tool-tar-flags" -}}
-x {{ if eq .Tar.Compression "gzip" }}-z {{ else if eq .Tar.Compression "bzip" }}-j {{ end }}
{{- end -}}

{{- define "make-env.to-base64" -}}
$(shell echo {{ . }} | base64 -w0)
{{- end -}}

{{- define "make-env.http-tool-tar" -}}
{{- $dot := . }}
{{- $downloadDir := print $dot.localBinVarRef "/.make-env/http/" (include "make-env.to-base64" $dot.urlVarRef) }}
{{- $downloadSubPath := tpl (.toolCfg.HTTP.Tar.Path | default $dot.toolName) .tplDot }}
{{- $downloadPath := print $downloadDir "/" $downloadSubPath }}
{{- $tarFlags := include "make-env.http-tool-tar-flags" $dot.toolCfg.HTTP }}
$(MAKE_ENV_MKDIR) -p {{ $downloadDir }}
$(MAKE_ENV_CURL) -vfL {{ $dot.urlVarRef }} | tar {{ $tarFlags }} -C {{ $downloadDir }} {{ $downloadSubPath }}
$(MAKE_ENV_CHMOD) +x {{ $downloadPath }}
$(MAKE_ENV_RM) -f {{ $dot.toolVarRef }}
$(MAKE_ENV_LN) -s {{ $downloadPath }} {{ $dot.toolVarRef }}
{{- end -}}

{{- define "make-env.http-tool-zip" -}}
{{- $dot := . }} 
{{- $downloadDir := print $dot.localBinVarRef "/.make-env/http/" (include "make-env.to-base64" $dot.urlVarRef) }}
{{- $downloadSubPath := .toolCfg.HTTP.Zip.Path | default $dot.toolName }}
{{- $downloadPath := print $downloadDir "/" $downloadSubPath }}
$(MAKE_ENV_MKDIR) -p {{ $downloadDir }})
$(MAKE_ENV_UNZIP) {{ $dot.zipVarRef }} -d {{ $downloadDir }} {{ $dot.zipVarRef }} {{ $downloadSubPath }}
$(MAKE_ENV_CHMOD) +x {{ $downloadPath }}
$(MAKE_ENV_RM) -f {{ $dot.toolVarRef }}
$(MAKE_ENV_LN) -s {{ $downloadPath }} {{ $dot.toolVarRef }}
{{- end -}}

{{- define "make-env.http-tool-raw" -}}
{{- $dot := . }} 
{{- $downloadDir := print $dot.localBinVarRef "/.make-env/http" }}
{{- $downloadPath := print $downloadDir (include "make-env.to-base64" $dot.urlVarRef) }}
$(MAKE_ENV_MKDIR) -p {{ $downloadDir }}
$(MAKE_ENV_CURL) -vfL {{ $dot.urlVarRef }} -o {{ $downloadPath }}
$(MAKE_ENV_CHMOD) +x {{ $downloadPath }}
$(MAKE_ENV_RM) -f {{ $dot.toolVarRef }}
$(MAKE_ENV_LN) -s {{ $downloadPath }} {{ $dot.toolVarRef }}
{{- end -}}

{{- define "make-env.http-tool" -}}
{{- $dot := . }}
{{- $urlVarName := $dot.toolName | toURLVarName }}
{{- $urlVarRef := $urlVarName | toVarRef }}
{{ $urlVarName }} ?= {{ tpl $dot.toolCfg.HTTP.URL $dot.tplDot }}
{{- $zipVarName := "" }}
{{- $zipVarRef := "" }}
{{- with $dot.toolCfg.HTTP.Zip }}
{{- $zipVarName = $dot.toolName | toZipVarName }}
{{- $zipVarRef = $zipVarName | toVarRef }}
{{ $zipVarName }} ?= {{ $dot.localBinVarRef }}/http/$(shell base64 -w0 <<< {{ $urlVarRef }}).zip
{{ $zipVarRef }}:
	$(MAKE_ENV_CURL) -vfL {{ $urlVarRef }} -o {{ $zipVarRef }}
{{- end }}{{/* with $dot.toolCfg.HTTP.Zip */}}
{{- $dot = set $dot "urlVarName" $urlVarName }}
{{- $dot = set $dot "urlVarRef" $urlVarRef }}
{{- $dot = set $dot "zipVarName" $zipVarName }}
{{- $dot = set $dot "zipVarRef" $zipVarRef }}
{{ $dot.toolVarRef }}: {{ if $dot.toolCfg.HTTP.Zip }}{{ $zipVarRef }}{{ end }} {{ .toolCfg.DependsOn | join " " }}
	{{- if $dot.toolCfg.HTTP.Zip }} 
	{{- include "make-env.http-tool-zip" $dot | ntindent 1 }}
	{{- end }}{{/* with $dot.toolCfg.HTTP.Zip */}}
	{{- if $dot.toolCfg.HTTP.Tar }}
	{{- include "make-env.http-tool-tar" $dot | ntindent 1 }}
	{{- end }}{{/* with $dot.toolCfg.HTTP.Tar */}}
	{{- if not (or $dot.toolCfg.HTTP.Tar $dot.toolCfg.HTTP.Zip) }}
	{{- include "make-env.http-tool-raw" $dot | ntindent 1 }}
	{{- end }}{{/* if not (or $dot.toolCfg.HTTP.Tar $dot.toolCfg.HTTP.Zip) */}}
{{- end -}}

{{- define "make-env.go-tool" -}}
{{ .toolVarRef }}: $(MAKE_ENV_GO) {{ .toolCfg.DependsOn | join " " }}
	{{- $module := tpl .toolCfg.Go.Module .tplDot }}
	{{- $version := tpl .toolCfg.Go.Version .tplDot }}
	{{- $subPath := tpl (.toolCfg.Go.SubPath | default "") .tplDot | trimSuffix "/" }}
	{{- if $subPath }}
	{{- $subPath = print "/" $subPath }}
	{{- end }}
	{{- $downloadDir := print .localBinVarRef "/.make-env/go/" $module $subPath "/" $version }}
	GOBIN={{ $downloadDir }} \
	{{- range $k, $v := .toolCfg.Go.Env }}
	{{ $k }}={{ tpl $v $.tplDot }} \
	{{- end }}
	$(MAKE_ENV_GO) install \
		{{- range .Flags }}
		{{ tpl . $.tplDot }} \
		{{- end }}
		{{ $module }}{{ $subPath }}@{{ $version }}
	$(MAKE_ENV_RM) -f {{ .toolVarRef }}
	$(MAKE_ENV_LN) -s {{ $downloadDir }}/{{ .toolName }} {{ .toolVarRef }}
{{- end -}}

{{- $config := .Config }}
{{- $globalVarDict := $config.Vars | toVarDict "" }}
{{- range $k, $v := $config.Vars }}
{{ $k | toVarName }} ?= {{ $v }}
{{- end }}
{{- range $builtin, $default := dict "go" $config.Commands.Go "curl" $config.Commands.Curl "tar" $config.Commands.Tar "unzip" $config.Commands.Unzip "base64" $config.Commands.Base64 "mkdir" $config.Commands.Mkdir "chmod" $config.Commands.Chmod "rm" $config.Commands.Rm "ln" $config.Commands.Ln "touch" $config.Commands.Touch }}
{{- $toolVarName := print "MAKE_ENV_" ($builtin | toVarName) }}
{{- $toolVarRef := $toolVarName | toVarRef }}
{{- $toolCfg := (dict "Provided" (dict "Default" $default)) }}
{{- $includeDot := (dict "toolVarName" $toolVarName "toolVarRef" $toolVarRef "toolCfg" $toolCfg ) }}
{{ include "make-env.provided-tool" $includeDot }}
{{- end }}
{{- $localBinVarName := $config.LocalBinVar }}
{{- $localBinVarRef := $localBinVarName | toVarRef }}
{{ $localBinVarName }} ?= $(shell pwd)/bin
{{ $localBinVarRef }}:
	$(MAKE_ENV_MKDIR) -p {{ $localBinVarRef }}
	$(MAKE_ENV_TOUCH) {{ $localBinVarRef }}
{{ $localBinVarRef }}/: {{ $localBinVarRef }} {{ .toolCfg.DependsOn | join " " }}

{{- range $toolName, $toolCfg := $config.Tools }}

{{ "" }}

{{- $localVarDict := $toolCfg.Vars | toVarDict $toolName }}
{{- $varDict := dict }}
{{- range $k, $v := $globalVarDict }}
{{- $varDict = set $varDict $k $v }}
{{- end }}
{{- range $k, $v := $localVarDict }}
{{- $varDict = set $varDict $k $v }}
{{- end }}
{{- $tplDot := dict "Config" $config "Vars" $varDict }}
{{- $toolVarName := $toolName | toVarName }}
{{- $toolVarRef := $toolVarName | toVarRef }}
{{- if not $toolCfg.Provided }}
{{ $toolVarName }} ?= {{ $localBinVarRef }}/{{ $toolName }}
{{- end }}
{{- range $varName, $varValue := $toolCfg.Vars }}
{{ $toolVarName }}_{{ $varName | toVarName }} ?= {{ tpl $varValue $tplDot }}
{{- end }}{{/* range $varName, $varValue */}}
{{- $includeDot := dict "localBinVarName" $localBinVarName "localBinVarRef" $localBinVarRef "toolName" $toolName "toolCfg" $toolCfg "varDict" $varDict "tplDot" $tplDot "toolVarName" $toolVarName "toolVarRef" $toolVarRef }}
{{- if $toolCfg.Provided }}
{{ include "make-env.provided-tool" $includeDot }}
{{- end }}
{{- if $toolCfg.HTTP }}
{{ include "make-env.http-tool" $includeDot }}
{{- end }}{{/* with $toolCfg.HTTP */}}
{{- if $toolCfg.Go }}
{{ include "make-env.go-tool" $includeDot }}
{{- end }}{{/* if $toolCfg.Go */}}
{{- if $toolCfg.Pipx }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if $toolCfg.S3 }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if not (or $toolCfg.Provided $toolCfg.HTTP $toolCfg.Go $toolCfg.Pipx $toolCfg.S3) }}
{{ print "Tool " $toolName " did not specify a type" | fail }}
{{- end }}
.PHONY: {{ $toolName }}
{{ $toolName }}: {{ $toolVarRef }}
{{ end }}{{/* range $toolName, $toolCfg */}}

{{- range $setName, $names := $config.ToolSets }}
.PHONY: {{ $setName }}
{{ $setName }}:{{ range $name := $names }} {{ if hasTool $config.Tools $name }}{{ $name | toVarName | toVarRef }}{{ else }}{{ $name }}{{ end }}{{ end }}
{{ end }}{{/* range $setName, $toolNames */}}
{{ .OutPath }}: {{ .InPath }}
	make-env --config '{{ .InPath }}' --out '{{ .OutPath }}'
