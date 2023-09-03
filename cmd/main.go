package main

import (
	"fmt"
	"html/template"
	"net/http"
)

var templates *template.Template

func rootHandler(w http.ResponseWriter, r *http.Request) {
	templates.ExecuteTemplate(w, "index.html", nil)
}

func main() {
	templates = template.Must(template.ParseGlob("./templates/*.html"))

	fmt.Println("Templates loaded:")
	for _, tmpl := range templates.Templates() {
		fmt.Println("-", tmpl.Name())
	}

	fmt.Println("Listening on port 80.")
	router := http.NewServeMux()
	router.HandleFunc("/", rootHandler)
	http.ListenAndServe(":80", router)

}
