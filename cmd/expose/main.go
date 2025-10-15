package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/getExposed/expose/internal/client"
	"github.com/getExposed/expose/internal/version"
)

var help = `
Usage: expose [options]

Options:
	-s, SSH server remote host (default: getexposed.io)
	-p, SSH server remote port (default: 2200)
	-ls, Local HTTP server host (default: localhost)
	-lp, Local HTTP server port (default: 7500)
	-bp, Remote TCP bind port, (default: 0 (random))
	-id, ID to use when generating URL (default: "" (random))
	-pw, Password for remote server authentication (default: "")
	-a, Keep tunnel connection alive (default: true)
	-r, Auto-reconnect if connection failed (default: true)
	-version, prints expose version and build info

Read more:
	https://github.com/getExposed/expose
`

var (
	remoteServer  = flag.String("s", "getexposed.io", "")
	remotePort    = flag.Int("p", 2200, "")
	localServer   = flag.String("ls", "localhost", "")
	localPort     = flag.Int("lp", 80, "")
	bindPort      = flag.Int("bp", 0, "")
	id            = flag.String("id", "", "")
	password      = flag.String("pw", "", "")
	keepAlive     = flag.Bool("a", true, "")
	autoReconnect = flag.Bool("r", true, "")
	versionFlag   = flag.Bool("version", false, "version")
)

func main() {
	flag.Usage = func() {
		fmt.Print(help)
		os.Exit(0)
	}
	flag.Parse()

	if *versionFlag {
		fmt.Printf("%s\n", version.GenerateBuildVersionString())
		os.Exit(0)
	}

	exposeClient := client.NewExposeClient(client.Config{
		RemoteServer: *remoteServer,
		RemotePort:   *remotePort,
		LocalServer:  *localServer,
		LocalPort:    *localPort,
		BindPort:     *bindPort,
		ID:           *id,
		Password:     *password,
		KeepAlive:    *keepAlive,
	})

connect:
	if err := exposeClient.Run(); err != nil {
		if !*autoReconnect {
			log.Fatal(err)
		}
		log.Println("connection failed due: ", err.Error(), "reconnecting in 5s...")
		time.Sleep(time.Second * 5)
		goto connect
	}

	os.Exit(0)
}
