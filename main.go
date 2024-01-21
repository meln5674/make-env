package main

import (
	"bufio"
	"bytes"
	_ "embed"
	"fmt"
	"log"
	"os"
	"strings"
	"text/template"

	sprig "github.com/go-task/slim-sprig"
	"github.com/huandu/xstrings"
	"github.com/meln5674/rflag"
	"github.com/pkg/errors"
	"github.com/spf13/pflag"
	"gopkg.in/yaml.v3"
)

//go:embed Makefile.tpl
var defaultTemplateString string

func mkDefaultTemplate() *template.Template {
	t := template.New("Makefile.tpl")
	return template.Must(t.
		Funcs(map[string]interface{}{
			"toVarName":    toVarName,
			"toURLVarName": toURLVarName,
			"toZipVarName": toZipVarName,
			"toVarRef":     toVarRef,
			"toVarDict":    toVarDict,
			"ntindent":     ntindent,
			"hasTool":      hasTool,
			"tpl":          tpl,
			"include":      templateWithInclude{Template: t}.include,
		}).
		Funcs(sprig.TxtFuncMap()).
		Parse(defaultTemplateString),
	)
}

var defaultTemplate = mkDefaultTemplate()

type Config struct {
	Vars        map[string]string     `json:"vars,omitempty" yaml:"vars,omitempty"`
	LocalBinVar string                `json:"localBinVar,omitempty" yaml:"localBinVar,omitempty"`
	Tools       map[string]ToolConfig `json:"tools,omitempty" yaml:"tools,omitempty"`
	ToolSets    map[string]ToolSet    `json:"toolSets,omitempty" yaml:"toolSets,omitempty"`
	Commands    CommandsConfig        `json:"commands,omitempty" yaml:"commands,omitempty"`
}

func (Config) Defaults() Config {
	return Config{
		LocalBinVar: "LOCALBIN",
		Commands:    CommandsConfig{}.Defaults(),
	}
}

type ToolConfig struct {
	Provided  *ProvidedToolConfig `json:"provided,omitempty" yaml:"provided,omitempty"`
	HTTP      *HTTPToolConfig     `json:"http,omitempty" yaml:"http,omitempty"`
	S3        *S3ToolConfig       `json:"s3,omitempty" yaml:"s3,omitempty"`
	Pipx      *PipxToolConfig     `json:"pipx,omitempty" yaml:"pipx,omitempty"`
	Go        *GoToolConfig       `json:"go,omitempty" yaml:"go,omitempty"`
	Maven     *MavenToolConfig    `json:"maven,omitempty" yaml:"maven,omitempty"`
	Vars      map[string]string   `json:"vars,omitempty" yaml:"vars,omitempty"`
	DependsOn []string            `json:"dependsOn,omitempty" yaml:"dependsOn,omitempty"`
}

type ProvidedToolConfig struct {
	Default string `json:"default,omitempty" yaml:"default,omitempty"`
}

type HTTPToolConfig struct {
	URL string     `json:"url" yaml:"url"`
	Zip *ZipConfig `json:"zip,omitempty" yaml:"zip,omitempty"`
	Tar *TarConfig `json:"tar,omitempty" yaml:"tar,omitempty"`
}

type ZipConfig struct {
	Path string `json:"path,omitempty" yaml:"path,omitempty"`
}

type TarConfig struct {
	Compression string `json:"compression,omitempty" yaml:"compression,omitempty"`
	Path        string `json:"path,omitempty" yaml:"path,omitempty"`
}

type GoToolConfig struct {
	Module  string            `json:"module" yaml:"module"`
	SubPath string            `json:"subPath,omitempty" yaml:"subPath,omitempty"`
	Version string            `json:"version" yaml:"version"`
	Env     map[string]string `json:"env,omitempty" yaml:"env,omitempty"`
	Flags   []string          `json:"flags,omitempty" yaml:"flags,omitempty"`
}

type S3ToolConfig struct {
}

type PipxToolConfig struct {
}

type MavenToolConfig struct {
}

type ToolSet []string

type CommandsConfig struct {
	Go     string
	Curl   string
	Tar    string
	Unzip  string
	Base64 string
	Mkdir  string
	Chmod  string
	Rm     string
	Ln     string
	Touch  string
}

func (CommandsConfig) Defaults() CommandsConfig {
	return CommandsConfig{
		Go:     "go",
		Curl:   "curl",
		Tar:    "tar",
		Unzip:  "unzip",
		Base64: "base64",
		Mkdir:  "mkdir",
		Chmod:  "chmod",
		Rm:     "rm",
		Ln:     "ln",
		Touch:  "touch",
	}
}

func toVarName(toolName string) string {
	return strings.ToUpper(xstrings.ToSnakeCase(toolName))
}

func toVarRef(varName string) string {
	return fmt.Sprintf("$(%s)", varName)
}

func toURLVarName(toolName string) string {
	return fmt.Sprintf("%s_URL", toVarName(toolName))
}

func toZipVarName(toolName string) string {
	return fmt.Sprintf("%s_ZIP", toVarName(toolName))
}

func toVarDict(toolName string, vars map[string]string) map[string]string {
	varDict := make(map[string]string, len(vars))
	for k := range vars {
		varDict[k] = toVarRef(fmt.Sprintf("%s_%s", toVarName(toolName), toVarName(k)))
	}
	return varDict
}

func ntindent(n int, s string) (string, error) {
	// log.Print("Enter: ntindent ", n, " ", s)
	// defer log.Print("Exit: ntindent ", n, " ", s)
	var indentBuilder strings.Builder
	for ix := 0; ix < n; ix++ {
		indentBuilder.WriteString("\t")
	}
	indent := indentBuilder.String()

	var builder strings.Builder
	builder.WriteString(indent)
	builder.WriteString("\n")
	scanner := bufio.NewScanner(strings.NewReader(s))
	for scanner.Scan() {
		// log.Print("Line: ", scanner.Text())
		builder.WriteString(indent)
		builder.WriteString(scanner.Text())
		builder.WriteString("\n")
	}
	// log.Print("Error: ", scanner.Err())
	// log.Print("Out: ", builder.String())
	return builder.String(), scanner.Err()
}

func hasTool(tools map[string]ToolConfig, name string) bool {
	_, ok := tools[name]
	return ok
}

func tpl(s string, data interface{}) (string, error) {
	var buf bytes.Buffer
	t, err := template.New(s).Parse(s)
	if err != nil {
		return "", err
	}
	err = t.Execute(&buf, data)
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

type templateWithInclude struct {
	*template.Template
}

func (t templateWithInclude) include(name string, data interface{}) (string, error) {
	// log.Print("Enter: include ", name)
	// defer log.Print("Exit: include ", name)
	toInclude := t.Lookup(name)
	if toInclude == nil {
		err := fmt.Errorf("No sub-template %s defined", name)
		// log.Print("Error: ", err)
		// log.Print("Out:")
		return "", err
	}
	var buf bytes.Buffer
	err := toInclude.Execute(&buf, data)
	// log.Print("Error: ", err)
	// log.Print("Out: ", buf.String())
	return buf.String(), err
}

type argsT struct {
	Config    string `rflag:"usage=Configuration file to generate from"`
	Out       string `rflag:"usage=Output Makefile to generate"`
	Directory string `rflag:"usage=Directory to change to before running,shorthand=C"`
	Debug     bool   `rflag:"usage=Log debugging information"`
}

func (argsT) Defaults() argsT {
	return argsT{
		Config: "make-env.yaml",
		Out:    "make-env.Makefile",
	}
}

var args = argsT{}.Defaults()

func mainInner() error {
	if args.Directory != "" {
		err := os.Chdir(args.Directory)
		if err != nil {
			return errors.Wrapf(err, "Failed to change directory to %s", args.Directory)
		}
		pwd, err := os.Getwd()
		if err != nil {
			return errors.Wrapf(err, "Failed to change directory to %s", args.Directory)
		}
		if args.Debug {
			log.Printf("Changed directory to %s", pwd)
		}
	}
	in, err := os.Open(args.Config)
	if err != nil {
		return errors.Wrapf(err, "Failed to open config file %s", args.Config)
	}
	defer in.Close()
	config := Config{}.Defaults()
	err = yaml.NewDecoder(in).Decode(&config)
	if err != nil {
		return errors.Wrapf(err, "Failed to parse config file %s", args.Config)
	}
	if args.Debug {
		log.Printf("Parsed config %#v", config)
	}
	out, err := os.Create(args.Out)
	if err != nil {
		return errors.Wrapf(err, "Failed to open output Makefile %s", args.Out)
	}
	defer out.Close()

	err = defaultTemplate.Execute(out, map[string]interface{}{
		"Config":  config,
		"InPath":  args.Config,
		"OutPath": args.Out,
	})
	if err != nil {
		return errors.Wrapf(err, "Failed to generate output Makefile %s", args.Out)
	}
	return nil
}

func main() {
	rflag.MustRegister(rflag.ForPFlag(pflag.CommandLine), "", &args)
	pflag.Parse()
	if len(pflag.CommandLine.Args()) != 0 {
		log.Print("make-env accepts no non-flag arguments")
		log.Fatal(pflag.CommandLine.FlagUsages())
	}
	if args.Debug {
		log.Printf("Parsed args %#v", args)
	}

	err := mainInner()
	if err != nil {
		log.Fatal(err)
	}
}
