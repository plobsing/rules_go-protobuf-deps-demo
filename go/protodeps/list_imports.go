// list_imports - list packages imported by Go sources
//
// usage: list_imports SRC_FILE...
package main

import (
	"fmt"
	"go/parser"
	"go/token"
	"log"
	"os"
	"strconv"
)

func main() {
	for _, arg := range os.Args[1:] {
		listImports(arg)
	}
}

func listImports(filename string) {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, filename, nil, parser.ImportsOnly)
	if err != nil {
		log.Fatalf("%s: %s", filename, err)
	}

	for _, spec := range f.Imports {
		pos := fset.Position(spec.Path.ValuePos)
		pos.Column = 0

		pkg, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			log.Fatalf("%s: %s", pos, err)
		}
		fmt.Println(pos, pkg)
	}
}
