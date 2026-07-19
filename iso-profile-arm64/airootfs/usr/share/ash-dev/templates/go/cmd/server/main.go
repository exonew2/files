package main

import (
	"log"
	"net/http"

	"github.com/ash-linux/{{project_name}}/internal/api"
)

func main() {
	router := api.NewRouter()
	log.Println("Starting {{project_name}} on :8080")
	http.ListenAndServe(":8080", router)
}
