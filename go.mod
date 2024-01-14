module github.com/meln5674/make-env

go 1.21.5

require (
	github.com/go-task/slim-sprig v0.0.0-20230315185526-52ccab3ef572
	github.com/meln5674/rflag v0.0.0-20231114035053-b81e1b904223
	github.com/spf13/pflag v1.0.5
	gopkg.in/yaml.v3 v3.0.1
)

require github.com/huandu/xstrings v1.4.0

require github.com/pkg/errors v0.9.1 // indirect

replace github.com/meln5674/rflag v0.0.0-20231114035053-b81e1b904223 => ../rflag
