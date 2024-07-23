{{/*

To generate the Dockerfile:

1. Create an ARG for each global var and dockerfile-specific arg
2. Create a stage for the make-env image, which contains itself as well as all of the necessary tool downloaders (curl, go, pipx, etc)
3. For each tool:
    1. Create a stage from the stage in step 2
    2. Create an empty ARG for each global var and dockerfile-specific arg
    2. Create an ARG for each tool-specific var
    3. For HTTP tools, create an arg for the url. If the tool is within a zip, create an arg for the download location.
    4. Create a RUN with which performs the download to a standard location
4. Create a final stage from a user-supplied image
5. Create an empty ARG for each global var and dockerfile-specific arg
6. Add any user-supplied pre-copy statements
7. For each tool, add a COPY --from for the binary as well as any supporting data (e.g. pipx venvs)
8. Add any user-supplied post-copy statements

*/}}

{{- define "make-env.dockerfile.http-tool-tar-flags" -}}
-x
{{- if eq .Tar.Compression "gzip" }} -z
{{- else if eq .Tar.Compression "bzip2" }} -j
{{- else if eq .Tar.Compression "lzma" }} -J 
{{- end -}}
{{- end -}}

{{- define "make-env.dockerfile.to-base64" -}}
$(echo {{ . }} | base64 -w0)
{{- end -}}

{{- define "make-env.dockerfile.http-tool-tar" -}}
{{- $dot := . }}
{{- $downloadSubPath := tpl (.toolCfg.HTTP.Tar.Path | default $dot.toolName) .tplDot }}
{{- $downloadPath := print $dot.toolDownloadPrefix "/" $downloadSubPath }}
{{- $finalPath := print $dot.toolBinPrefix "/" $dot.toolName }}
{{- $tarFlags := include "make-env.dockerfile.http-tool-tar-flags" $dot.toolCfg.HTTP }}
RUN ${MAKE_ENV_MKDIR} -p {{ $dot.toolDownloadPrefix }} {{ $dot.toolBinPrefix }} \
 && ${MAKE_ENV_CURL} -vfL {{ $dot.urlArgRef }} | tar {{ $tarFlags }} -C {{ $dot.toolDownloadPrefix }} {{ $downloadSubPath }} \
 && ${MAKE_ENV_MV} {{ $downloadPath }} {{ $finalPath }} \
 && ${MAKE_ENV_CHMOD} +x {{ $finalPath }}
{{- end -}}

{{- define "make-env.dockerfile.http-tool-zip" -}}
{{- $dot := . }} 
{{- $downloadSubPath := .toolCfg.HTTP.Zip.Path | default $dot.toolName }}
{{- $downloadPath := print $dot.toolDownloadPrefix "/" $downloadSubPath }}
{{- $finalPath := print $dot.toolBinPrefix "/" $dot.toolName }}
RUN ${MAKE_ENV_MKDIR} -p {{ $dot.toolDownloadPrefix }} {{ $dot.toolBinPrefix }} \
 && ${MAKE_ENV_UNZIP} {{ $dot.zipPath }} -d {{ $dot.toolDownloadPrefix }} {{ $downloadSubPath }} \
 && ${MAKE_ENV_MV} {{ $downloadPath }} {{ $finalPath }} \
 && ${MAKE_ENV_CHMOD} +x {{ $finalPath }}
{{- end -}}

{{- define "make-env.dockerfile.http-tool-raw" -}}
{{- $dot := . }} 
{{ $downloadPath := print $dot.toolBinPrefix "/" $dot.toolName }}
RUN ${MAKE_ENV_MKDIR} -p {{ $dot.toolDownloadPrefix }} {{ $dot.toolBinPrefix }} \
 && ${MAKE_ENV_CURL} -vfL {{ $dot.urlArgRef }} -o {{ $downloadPath }} \
 && ${MAKE_ENV_CHMOD} +x {{ $downloadPath }}
{{- end -}}

{{- define "make-env.dockerfile.http-tool" -}}
{{- $dot := . }}
{{- $urlVarName := $dot.toolName | toURLVarName }}
{{- $urlArgRef := $urlVarName | toArgRef }}
ARG {{ $urlVarName }}={{ tpl $dot.toolCfg.HTTP.URL $dot.tplDot }}
{{- with $dot.toolCfg.HTTP.Zip }}
{{- $zipPath := print $dot.toolDownloadPrefix "/" $dot.toolName ".zip" }}
{{- $dot = set $dot "zipPath" $zipPath }}
RUN $(MAKE_ENV_CURL) -vfL {{ $urlArgRef }} -o {{ $zipPath }}
{{- end }}{{/* with $dot.toolCfg.HTTP.Zip */}}
{{- $dot = set $dot "urlVarName" $urlVarName }}
{{- $dot = set $dot "urlArgRef" $urlArgRef }}
{{- if $dot.toolCfg.HTTP.Zip }} 
{{- include "make-env.dockerfile.http-tool-zip" $dot }}
{{- end }}{{/* with $dot.toolCfg.HTTP.Zip */}}
{{- if $dot.toolCfg.HTTP.Tar }}
{{- include "make-env.dockerfile.http-tool-tar" $dot }}
{{- end }}{{/* with $dot.toolCfg.HTTP.Tar */}}
{{- if not (or $dot.toolCfg.HTTP.Tar $dot.toolCfg.HTTP.Zip) }}
{{- include "make-env.dockerfile.http-tool-raw" $dot }}
{{- end }}{{/* if not (or $dot.toolCfg.HTTP.Tar $dot.toolCfg.HTTP.Zip) */}}
{{- end -}}

{{- define "make-env.dockerfile.go-tool" -}}
{{- $dot := . }}
{{- $module := tpl $dot.toolCfg.Go.Module .tplDot }}
{{- $version := tpl $dot.toolCfg.Go.Version .tplDot }}
{{- $subPath := tpl ($dot.toolCfg.Go.SubPath | default "") $dot.tplDot | trimSuffix "/" }}
{{- if $subPath }}
{{- $subPath = print "/" $subPath }}
{{- end }}
{{- $gopath := print $dot.toolBinPrefix ".make-env/go" }}
RUN GOBIN={{ $dot.toolBinPrefix }} \
    {{- range $k, $v := .toolCfg.Go.Env }}
    {{ $k }}={{ tpl $v $.tplDot }} \
    {{- end }}
    ${MAKE_ENV_GO} install \
    	{{- range .Flags }}
    	{{ tpl . $dot.tplDot }} \
    	{{- end }}
    	{{ $module }}{{ $subPath }}@{{ $version }}
{{- end -}}



{{- $config := .Config }}

{{- range $k, $v := $config.Vars }}
ARG {{ $k | toVarName }}={{ $v }}
{{- end }}
{{- range $k, $v := $config.Dockerfile.Args }}
ARG {{ $k | toVarName }}{{ with $v }}={{ . }}{{ end }}
{{- end }}

{{- $argDict := dict }}
{{- range $k, $v := $config.Vars | toArgDict "" }}
{{- $argDict = set $argDict $k $v }}
{{- end }}
{{- range $k, $v := $config.Dockerfile.Args | toArgDict "" }}
{{- $argDict = set $argDict $k $v }}
{{- end }}
{{- $tplDot := dict "Config" $config "Vars" $argDict }}


{{- $builtins := dict "go" $config.Commands.Go "curl" $config.Commands.Curl "tar" $config.Commands.Tar "unzip" $config.Commands.Unzip "base64" $config.Commands.Base64 "mkdir" $config.Commands.Mkdir "chmod" $config.Commands.Chmod "rm" $config.Commands.Rm "ln" $config.Commands.Ln "touch" $config.Commands.Touch "mv" $config.Commands.Mv }}
{{- range $builtin, $default := $builtins }}
{{- $toolArgName := print "MAKE_ENV_" ($builtin | toVarName) }}
{{- $toolArgRef := $toolArgName | toArgRef }}
ARG {{ $toolArgName }}={{ $default }}
{{- end }}

{{- range $toolName, $toolCfg := $config.Tools }}

{{- $toolStage := print ($config.Dockerfile.StagePrefix | trimSuffix "-") "-" $toolName }}

{{- if $toolCfg.HTTP }}
FROM {{ $config.Dockerfile.CurlImage }} AS {{ $toolStage }}
{{- end }}
{{- if $toolCfg.Go }}
FROM {{ $config.Dockerfile.GoImage }} AS {{ $toolStage }}
{{- end }}
{{- if $toolCfg.Pipx }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if $toolCfg.S3 }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if not (or $toolCfg.Provided $toolCfg.HTTP $toolCfg.Go $toolCfg.Pipx $toolCfg.S3) }}
{{ print "Tool " $toolName " did not specify a type" | fail }}
{{- end }}

{{- range $builtin, $default := $builtins }}
{{- $toolArgName := print "MAKE_ENV_" ($builtin | toVarName) }}
ARG {{ $toolArgName }}
{{- end }}



{{- $toolArgDict := dict }}

{{- range $k, $v := $config.Vars }}
ARG {{ $k | toVarName }}
{{- end }}
{{- range $k, $v := $config.Dockerfile.Args }}
ARG {{ $k | toVarName }}
{{- end }}
{{- range $k, $v := $toolCfg.Vars }}
ARG {{ $toolName | toVarName }}_{{ $k | toVarName }}{{ with $v }}={{ . }}{{ end }}
{{- end }}

{{- range $k, $v := $argDict }}
{{- $toolArgDict = set $toolArgDict $k $v }}
{{- end }}
{{- range $k, $v := $toolCfg.Vars | toArgDict $toolName }}
{{- $toolArgDict = set $toolArgDict $k $v }}
{{- end }}
{{- $tplDot := dict "Config" $config "Vars" $toolArgDict }}
{{- $includeDot := dict "toolName" $toolName "toolCfg" $toolCfg "toolArgDict" $toolArgDict "tplDot" $tplDot "toolDownloadPrefix" "/opt/make-env/download" "toolBinPrefix" "/opt/make-env/bin" }}
{{- if $toolCfg.HTTP }}
{{ include "make-env.dockerfile.http-tool" $includeDot }}
{{- end }}
{{- if $toolCfg.Go }}
{{ include "make-env.dockerfile.go-tool" $includeDot }}
{{- end }}
{{- if $toolCfg.Pipx }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if $toolCfg.S3 }}
{{ fail "UNIMPLEMENTED" }}
{{- end }}
{{- if not (or $toolCfg.Provided $toolCfg.HTTP $toolCfg.Go $toolCfg.Pipx $toolCfg.S3) }}
{{ print "Tool " $toolName " did not specify a type" | fail }}
{{- end }}
{{- end }}{{/* range $toolName, $toolCfg */}}

FROM {{ $config.Dockerfile.From }}{{ with $config.Dockerfile.FinalStage }} AS {{ . }}{{ end }}

{{- $localBinArgName := $config.LocalBinVar }}
ARG {{ $localBinArgName }}={{ $config.Dockerfile.FinalBin }}
{{- $localBinArgRef := $config.LocalBinVar | toArgRef }}
ENV {{ $localBinArgName }}={{ $localBinArgRef }}
ENV PATH=${PATH}:{{ $localBinArgRef }}


{{- with $config.Dockerfile.PreCopy }}
{{ . }}
{{- end }}

{{- range $toolName, $toolCfg := $config.Tools }}
{{- $toolStage := print ($config.Dockerfile.StagePrefix | trimSuffix "-") "-" $toolName }}
COPY --from={{ $toolStage }} /opt/make-env/bin/. {{ $localBinArgRef }}/

{{- end }}{{/* range $toolName, $toolCfg */}}

{{- with $config.Dockerfile.PostCopy }}
{{ . }}
{{- end }}

