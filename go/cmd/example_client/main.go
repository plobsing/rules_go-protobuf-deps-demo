package main

import (
    "context"
    "log"

    "google.golang.org/grpc"

     mypb "github.com/example/project/proto"
)

const addr = "127.0.0.1:1357"

func main() {
    ctx := context.Background()

    conn, err := grpc.Dial(addr)
    if err != nil { log.Fatal(err) }
    defer conn.Close()

    client := mypb.NewExampleClient(conn)
    req := new(mypb.ExampleRequest)
    resp, err := client.Command(ctx, req)
    if err != nil { log.Fatal(err) }
    log.Print(resp)
}
