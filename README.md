# codebase.md

A CLI tool to turn your entire codebase into a single Markdown file. Typically used
to generate a file so that you can easily create context of your entire codebase.

## Installation

Check the [releases](https://github.com/Eckhardt-D/codebase.md/releases) page for the latest binary for your platform.

## Usage

```sh
codemd [flags] [path]

path:
  defaults to the current working directory

flags:
  -h, --help             prints this message
  -o, --output  string   output file (defaults to stdout)
  --ignore-path string   path to .gitignore file (default is <cwd>/.gitignore)
```

By default codebase.md looks at your `.gitignore` file for folders and files to ignore. It also has hard defaults:

```
.env
.env.prod*
node_modules
```

## Todo

- [ ] Refactor the walk to collect file paths for second pass
- [ ] Add support for output
- [ ] Check .gitignore for ignored files
