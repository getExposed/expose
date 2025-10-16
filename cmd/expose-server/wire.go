//go:build wireinject
// +build wireinject

package main

import (
	"github.com/getExposed/expose/internal/server"
	"github.com/getExposed/expose/pkg/logger"
	"github.com/google/wire"
)

var providerSet = wire.NewSet(
	logger.ProviderSet,
	server.ProviderSet,
)

func CreateApp(cfg string) (*server.ExposeServer, error) {
	panic(wire.Build(providerSet))
}
